// SPDX-License-Identifier: GPL-3.0-or-later
//! frameworkd: exposes Framework Laptop EC controls on the system bus.
//!
//! Reads are unrestricted, writes are gated by polkit actions
//! (see data/io.github.frameworkkcm.policy).

mod ec;
mod polkit;
mod state;

use std::future::Future;
use std::sync::{Arc, Mutex, MutexGuard};

use framework_lib::chromium_ec::CrosEc;
use zbus::message::Header;
use zbus::Connection;

use ec::{dict, Dict};
use state::{ChargeLimitOverride, State};

const BUS_NAME: &str = "io.github.frameworkkcm.Daemon1";
const OBJECT_PATH: &str = "/io/github/frameworkkcm/Daemon1";

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "io.github.frameworkkcm.Error")]
enum Error {
    #[zbus(error)]
    ZBus(zbus::Error),
    NotAuthorized(String),
    Failed(String),
}

/// Last fan command we sent; the EC can't report it back
#[derive(Debug, Clone, Copy, PartialEq)]
enum FanControl {
    Auto,
    Duty(i32),
    Rpm(i32),
}

struct Inner {
    ec: Mutex<CrosEc>,
    state: Mutex<State>,
    fan: Mutex<FanControl>,
}

#[derive(Clone)]
struct Daemon(Arc<Inner>);

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    // A panic inside framework_lib shouldn't wedge the daemon forever
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Daemon {
    fn new() -> Self {
        Daemon(Arc::new(Inner {
            ec: Mutex::new(CrosEc::new()),
            state: Mutex::new(State::load()),
            fan: Mutex::new(FanControl::Auto),
        }))
    }

    /// Run blocking EC work off the async executor, one request at a time.
    async fn with_ec<T, F>(&self, f: F) -> Result<T, Error>
    where
        T: Send + 'static,
        F: FnOnce(&CrosEc) -> Result<T, String> + Send + 'static,
    {
        let inner = self.0.clone();
        blocking(move || f(&lock(&inner.ec))).await
    }

    async fn authorize(
        &self,
        conn: &Connection,
        hdr: &Header<'_>,
        action: &str,
    ) -> Result<(), Error> {
        if polkit::check(conn, hdr, action).await? {
            Ok(())
        } else {
            Err(Error::NotAuthorized("Not authorized".into()))
        }
    }

    fn update_state(&self, f: impl FnOnce(&mut State)) {
        let mut state = lock(&self.0.state);
        f(&mut state);
        state.save();
    }

    /// Re-apply settings the hardware forgets or can't report back.
    async fn reapply(&self) {
        let state = lock(&self.0.state).clone();
        if let Some(o) = state
            .charge_limit_override
            .filter(|o| o.boot_id != state::boot_id())
        {
            let max = o.restore_max as i32;
            // On failure keep the override so we try again on the next start
            if restore(
                "charge limit after override",
                self.with_ec(move |ec| ec::set_charge_limit(ec, max)),
            )
            .await
            {
                log::info!("Charge limit override ended, restored limit to {max}%");
                self.update_state(|s| s.charge_limit_override = None);
            }
        }
        if let Some(rate) = state.charge_rate_limit.filter(|r| *r < 1.0) {
            let soc = state.charge_rate_soc;
            restore(
                "charge rate limit",
                self.with_ec(move |ec| ec::set_charge_rate_limit(ec, rate, soc)),
            )
            .await;
        }
        if let Some(v) = state.haptic_intensity {
            restore(
                "haptic intensity",
                blocking(move || ec::set_haptic_intensity(v as i32)),
            )
            .await;
        }
        if let Some(force) = state.click_force {
            restore("click force", blocking(move || ec::set_click_force(&force))).await;
        }
    }

    /// Hand fans back to the EC so we never leave them pinned when we exit.
    async fn restore_auto_fan(&self) {
        if *lock(&self.0.fan) != FanControl::Auto {
            restore(
                "automatic fan control",
                self.with_ec(|ec| ec::set_auto_fan(ec, -1)),
            )
            .await;
        }
    }
}

/// Run blocking hardware work (EC or HID) off the async executor.
async fn blocking<T, F>(f: F) -> Result<T, Error>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| Error::Failed(format!("Hardware access failed: {e}")))?
        .map_err(Error::Failed)
}

/// Await a re-apply step, logging instead of failing. Returns whether it worked.
async fn restore(what: &str, work: impl Future<Output = Result<(), Error>>) -> bool {
    match work.await {
        Ok(()) => true,
        Err(e) => {
            log::warn!("Failed to restore {what}: {e:?}");
            false
        }
    }
}

#[zbus::interface(name = "io.github.frameworkkcm.Daemon1")]
impl Daemon {
    #[zbus(property)]
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").to_string()
    }

    // ----- Reads --------------------------------------------------------

    async fn get_system_info(&self) -> Result<Dict, Error> {
        let mut info = self.with_ec(|ec| Ok(ec::system_info(ec))).await?;
        info.insert("daemonVersion".into(), ec::val(env!("CARGO_PKG_VERSION")));
        Ok(info)
    }

    async fn get_power(&self) -> Result<Dict, Error> {
        self.with_ec(ec::power).await
    }

    async fn get_charge_settings(&self) -> Result<Dict, Error> {
        let (_, max) = self.with_ec(ec::charge_limit).await?;
        let state = lock(&self.0.state).clone();
        // While overridden the EC is at 100%; report the user's limit instead
        let limit = state
            .charge_limit_override
            .as_ref()
            .map_or(max, |o| o.restore_max);
        Ok(dict! {
            "maxLimit" => limit as i32,
            "overrideActive" => state.charge_limit_override.is_some(),
            "rateLimit" => state.charge_rate_limit.unwrap_or(1.0),
            "rateLimitSoc" => state.charge_rate_soc.unwrap_or(-1.0),
        })
    }

    /// Returns (sensors, fans, throttle)
    async fn get_thermal(&self) -> Result<(Vec<Dict>, Vec<Dict>, Dict), Error> {
        self.with_ec(ec::thermal).await
    }

    async fn get_fan_control(&self) -> Dict {
        let (mode, value) = match *lock(&self.0.fan) {
            FanControl::Auto => ("auto", 0),
            FanControl::Duty(percent) => ("duty", percent),
            FanControl::Rpm(rpm) => ("rpm", rpm),
        };
        dict! { "mode" => mode, "value" => value }
    }

    async fn get_input(&self) -> Result<Dict, Error> {
        let fp = self.with_ec(|ec| Ok(ec::fp_led(ec))).await?;
        let state = lock(&self.0.state).clone();
        let (fp_percent, fp_level) = fp
            .as_ref()
            .map(|(p, l)| (*p as i32, l.clone()))
            .unwrap_or((-1, String::new()));
        Ok(dict! {
            "fpLedSupported" => fp.is_ok(),
            "fpLedPercent" => fp_percent,
            "fpLedLevel" => fp_level,
            "hapticIntensity" => state.haptic_intensity.map(|v| v as i32).unwrap_or(-1),
            "clickForce" => state.click_force.unwrap_or_default(),
        })
    }

    async fn get_ports(&self) -> Result<Vec<Dict>, Error> {
        self.with_ec(|ec| Ok(ec::ports(ec))).await
    }

    // ----- Battery ------------------------------------------------------

    async fn set_charge_limit(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        max: i32,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_BATTERY).await?;
        self.with_ec(move |ec| ec::set_charge_limit(ec, max))
            .await?;
        // An explicitly chosen limit replaces any pending override
        if lock(&self.0.state).charge_limit_override.is_some() {
            self.update_state(|s| s.charge_limit_override = None);
        }
        Ok(())
    }

    /// Charge to 100% until the next boot, then go back to the current limit.
    async fn override_charge_limit(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_BATTERY).await?;
        if lock(&self.0.state).charge_limit_override.is_some() {
            return Ok(());
        }
        let (_, max) = self.with_ec(ec::charge_limit).await?;
        if max >= 100 {
            return Err(Error::Failed("The charge limit is already 100%".into()));
        }
        self.with_ec(|ec| ec::set_charge_limit(ec, 100)).await?;
        self.update_state(|s| {
            s.charge_limit_override = Some(ChargeLimitOverride {
                restore_max: max,
                boot_id: state::boot_id(),
            })
        });
        Ok(())
    }

    /// End an override now instead of at the next boot.
    async fn cancel_charge_limit_override(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_BATTERY).await?;
        let Some(o) = lock(&self.0.state).charge_limit_override.clone() else {
            return Ok(());
        };
        let max = o.restore_max as i32;
        self.with_ec(move |ec| ec::set_charge_limit(ec, max))
            .await?;
        self.update_state(|s| s.charge_limit_override = None);
        Ok(())
    }

    /// `rate` in C (1.0 removes the limit); `soc` < 0 applies it at any battery level.
    async fn set_charge_rate_limit(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        rate: f64,
        soc: f64,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_BATTERY).await?;
        let soc = (soc >= 0.0).then_some(soc);
        self.with_ec(move |ec| ec::set_charge_rate_limit(ec, rate, soc))
            .await?;
        self.update_state(|s| {
            s.charge_rate_limit = Some(rate);
            s.charge_rate_soc = soc;
        });
        Ok(())
    }

    // ----- Fans ---------------------------------------------------------

    /// `fan` < 0 applies to all fans.
    async fn set_fan_duty(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        fan: i32,
        percent: i32,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_FAN).await?;
        self.with_ec(move |ec| ec::set_fan_duty(ec, fan, percent))
            .await?;
        *lock(&self.0.fan) = FanControl::Duty(percent);
        Ok(())
    }

    async fn set_fan_rpm(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        fan: i32,
        rpm: i32,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_FAN).await?;
        self.with_ec(move |ec| ec::set_fan_rpm(ec, fan, rpm))
            .await?;
        *lock(&self.0.fan) = FanControl::Rpm(rpm);
        Ok(())
    }

    async fn set_auto_fan(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        fan: i32,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_FAN).await?;
        self.with_ec(move |ec| ec::set_auto_fan(ec, fan)).await?;
        *lock(&self.0.fan) = FanControl::Auto;
        Ok(())
    }

    // ----- Input & lighting ---------------------------------------------

    async fn set_fp_led_level(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        level: String,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_INPUT).await?;
        self.with_ec(move |ec| ec::set_fp_led_level(ec, &level))
            .await
    }

    async fn set_haptic_intensity(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        value: i32,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_INPUT).await?;
        blocking(move || ec::set_haptic_intensity(value)).await?;
        self.update_state(|s| s.haptic_intensity = Some(value as u8));
        Ok(())
    }

    async fn set_click_force(
        &self,
        #[zbus(header)] hdr: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        force: String,
    ) -> Result<(), Error> {
        self.authorize(conn, &hdr, polkit::ACTION_INPUT).await?;
        let f = force.clone();
        blocking(move || ec::set_click_force(&f)).await?;
        self.update_state(|s| s.click_force = Some(force));
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let daemon = Daemon::new();

    // Claim the name first so D-Bus activated clients don't wait on re-applying;
    // EC access is serialized anyway
    let _conn = zbus::connection::Builder::system()?
        .name(BUS_NAME)?
        .serve_at(OBJECT_PATH, daemon.clone())?
        .build()
        .await?;
    log::info!("Serving {BUS_NAME} at {OBJECT_PATH}");

    tokio::spawn({
        let daemon = daemon.clone();
        async move { daemon.reapply().await }
    });

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    tokio::select! {
        _ = term.recv() => {}
        _ = tokio::signal::ctrl_c() => {}
    }

    daemon.restore_auto_fan().await;
    Ok(())
}
