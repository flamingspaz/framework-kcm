// SPDX-License-Identifier: GPL-3.0-or-later
//! Settings the hardware can't report back (write-only HID reports, charge
//! current limit). We remember what was last set so the UI can show it and
//! so we can re-apply it when the daemon starts.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    /// Charge rate limit in C (1.0 = no limit)
    pub charge_rate_limit: Option<f64>,
    /// Battery state of charge above which the rate limit applies
    pub charge_rate_soc: Option<f64>,
    /// Touchpad haptic intensity (0, 25, 50, 75, 100)
    pub haptic_intensity: Option<u8>,
    /// Touchpad click force ("low", "medium", "high")
    pub click_force: Option<String>,
    /// Charge limit temporarily raised to 100% until the next boot
    pub charge_limit_override: Option<ChargeLimitOverride>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChargeLimitOverride {
    /// Limit to go back to
    pub restore_max: u8,
    /// Boot the override was made in; restored once this changes
    pub boot_id: String,
}

pub fn boot_id() -> String {
    std::fs::read_to_string("/proc/sys/kernel/random/boot_id")
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

fn path() -> PathBuf {
    // systemd sets this from StateDirectory=
    let dir = std::env::var_os("STATE_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/lib/frameworkd"));
    dir.join("state.json")
}

impl State {
    pub fn load() -> Self {
        match std::fs::read_to_string(path()) {
            Ok(s) => serde_json::from_str(&s).unwrap_or_else(|e| {
                log::warn!("Ignoring invalid state file: {e}");
                State::default()
            }),
            Err(_) => State::default(),
        }
    }

    pub fn save(&self) {
        let path = path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = path.with_extension("json.tmp");
        let res = serde_json::to_string_pretty(self)
            .map_err(std::io::Error::other)
            .and_then(|s| std::fs::write(&tmp, s))
            .and_then(|_| std::fs::rename(&tmp, &path));
        if let Err(e) = res {
            log::warn!("Failed to save state to {}: {e}", path.display());
        }
    }
}
