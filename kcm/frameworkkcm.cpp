// SPDX-License-Identifier: GPL-3.0-or-later

#include "frameworkkcm.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>

#include <algorithm>

K_PLUGIN_CLASS_WITH_JSON(FrameworkKcm, "kcm_framework.json")

using namespace Qt::StringLiterals;

namespace {
    const QString s_service = u"io.github.frameworkkcm.Daemon1"_s;
    const QString s_path = u"/io/github/frameworkkcm/Daemon1"_s;
    const QString s_interface = u"io.github.frameworkkcm.Daemon1"_s;

    constexpr int s_liveInterval = 2000;
    // Writes may wait on a polkit password prompt
    constexpr int s_writeTimeout = 5 * 60 * 1000;

    // Recursively turn QDBusArgument/QDBusVariant into plain QVariantMap/List,
    // which is what QML can work with.
    QVariant demarshall(const QVariant &value) {
        if (value.metaType() == QMetaType::fromType<QDBusVariant>()) {
            return demarshall(value.value<QDBusVariant>().variant());
        }
        if (value.metaType() != QMetaType::fromType<QDBusArgument>()) {
            return value;
        }

        const auto arg = value.value<QDBusArgument>();
        switch (arg.currentType()) {
        case QDBusArgument::MapType: {
            QVariantMap map;
            arg.beginMap();
            while (!arg.atEnd()) {
                arg.beginMapEntry();
                const QString key = demarshall(arg.asVariant()).toString();
                map.insert(key, demarshall(arg.asVariant()));
                arg.endMapEntry();
            }
            arg.endMap();
            return map;
        }
        case QDBusArgument::ArrayType: {
            QVariantList list;
            arg.beginArray();
            while (!arg.atEnd()) {
                list.append(demarshall(arg.asVariant()));
            }
            arg.endArray();
            return list;
        }
        case QDBusArgument::StructureType: {
            QVariantList list;
            arg.beginStructure();
            while (!arg.atEnd()) {
                list.append(demarshall(arg.asVariant()));
            }
            arg.endStructure();
            return list;
        }
        default:
            return demarshall(arg.asVariant());
        }
    }

    QVariant replyArg(const QDBusMessage &reply, int index) {
        const auto args = reply.arguments();
        return index < args.size() ? demarshall(args.at(index)) : QVariant();
    }

    // Resets the fields defaults() covers, keeping the rest
    FrameworkSettings withDefaults(FrameworkSettings s) {
        const FrameworkSettings d;
        s.chargeLimit = d.chargeLimit;
        s.chargeRateLimit = d.chargeRateLimit;
        s.chargeRateSoc = d.chargeRateSoc;
        s.fanMode = d.fanMode;
        return s;
    }

    bool isServiceMissing(const QDBusError &error) {
        switch (error.type()) {
        case QDBusError::ServiceUnknown:
        case QDBusError::NoReply:
        case QDBusError::Disconnected:
        case QDBusError::NoServer:
            return true;
        default:
            return error.name().startsWith(u"org.freedesktop.DBus.Error.Spawn"_s);
        }
    }
} // namespace

FrameworkKcm::FrameworkKcm(QObject *parent, const KPluginMetaData &data) : KQuickConfigModule(parent, data) {
    setButtons(Help | Default | Apply);

    m_fixtureMode = qEnvironmentVariableIntValue("FRAMEWORK_KCM_FIXTURE") != 0;
    m_fixtureModel = qEnvironmentVariable("FRAMEWORK_KCM_FIXTURE_MODEL").toLower();
    if (m_fixtureModel == u"12"_s) {
        m_fixtureModel = u"framework-12"_s;
    }
    if (m_fixtureModel == u"12-gen2"_s || m_fixtureModel == u"framework-12-2nd-gen"_s) {
        m_fixtureModel = u"framework-12-gen2"_s;
    }
    if (m_fixtureModel == u"13"_s) {
        m_fixtureModel = u"framework-13"_s;
    }
    if (m_fixtureModel == u"13-pro"_s) {
        m_fixtureModel = u"framework-13-pro"_s;
    }
    const auto fixtureProfiles = fixtureModels();
    if (m_fixtureModel.isEmpty() ||
        std::none_of(fixtureProfiles.cbegin(), fixtureProfiles.cend(), [this](const QVariant &entry) {
            return entry.toMap().value(u"id"_s).toString() == m_fixtureModel;
        })) {
        m_fixtureModel = u"framework-13-pro"_s;
    }
    m_schedules = {QVariantMap{{u"days"_s, QStringList{u"Mon"_s, u"Tue"_s, u"Wed"_s, u"Thu"_s, u"Fri"_s}},
                               {u"time"_s, u"08:00"_s},
                               {u"limit"_s, 80}}};
    loadSchedule();
    if (m_fixtureMode) {
        m_current.chargeLimit = 80;
        m_current.fpLedLevel = u"auto"_s;
        m_saved = m_current;
        loadFixture();
    }

    m_liveTimer.setInterval(s_liveInterval);
    connect(&m_liveTimer, &QTimer::timeout, this, &FrameworkKcm::refreshLive);
}

void FrameworkKcm::call(const QString &method, const QVariantList &args, const ReplyHandler &onReply,
                        const ErrorHandler &onError, const int timeout) {
    auto msg = QDBusMessage::createMethodCall(s_service, s_path, s_interface, method);
    msg.setArguments(args);
    msg.setInteractiveAuthorizationAllowed(true);

    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg, timeout), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, onReply, onError](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (w->isError()) {
            const QDBusError error = w->error();
            if (isServiceMissing(error)) {
                setDaemonAvailable(false);
            }
            if (onError) {
                onError(error);
            }
            return;
        }
        setDaemonAvailable(true);
        if (onReply) {
            onReply(w->reply());
        }
    });
}

void FrameworkKcm::load() {
    KQuickConfigModule::load();

    // Reset: drop unsaved edits, then take whatever the hardware reports
    m_current = m_saved;
    settingsEdited();

    if (m_fixtureMode) {
        loadFixture();
        return;
    }

    // Slow (talks to the PD controllers over I2C), and never changes, so only once
    call(u"GetSystemInfo"_s, {}, [this](const QDBusMessage &reply) {
        m_systemInfo = replyArg(reply, 0).toMap();
        Q_EMIT systemInfoChanged();
    });

    call(
        u"GetPower"_s, {},
        [this](const QDBusMessage &reply) {
            m_powerInfo = replyArg(reply, 0).toMap();
            Q_EMIT powerChanged();
        },
        [this](const QDBusError &error) {
            if (!isServiceMissing(error)) {
                setError(error.message());
            }
        });

    loadSettings();
    refreshLive();
}

QVariantList FrameworkKcm::fixtureModels() const {
    return {
        QVariantMap{{u"id"_s, u"framework-12"_s}, {u"name"_s, i18n("Framework Laptop 12")}},
        QVariantMap{{u"id"_s, u"framework-12-gen2"_s}, {u"name"_s, i18n("Framework Laptop 12 (2nd Gen)")}},
        QVariantMap{{u"id"_s, u"framework-13"_s}, {u"name"_s, i18n("Framework Laptop 13")}},
        QVariantMap{{u"id"_s, u"framework-13-pro"_s}, {u"name"_s, i18n("Framework Laptop 13 Pro")}},
    };
}

void FrameworkKcm::setFixtureModel(const QString &model) {
    if (!m_fixtureMode || model == m_fixtureModel) {
        return;
    }
    const auto models = fixtureModels();
    const auto valid = std::any_of(models.cbegin(), models.cend(), [&model](const QVariant &entry) {
        return entry.toMap().value(u"id"_s).toString() == model;
    });
    if (!valid) {
        return;
    }
    m_fixtureModel = model;
    updateFixtureProfile();
}

void FrameworkKcm::updateFixtureProfile() {
    const bool model12 = m_fixtureModel == u"framework-12"_s;
    const bool model12Gen2 = m_fixtureModel == u"framework-12-gen2"_s;
    const bool model13 = m_fixtureModel == u"framework-13"_s;
    const bool model13Pro = m_fixtureModel == u"framework-13-pro"_s;

    m_supportsKeyboardBacklight = !model12;
    m_fpLedSupported = model13 || model13Pro;
    m_supportsInputDeck = true;
    m_supportsTabletMode = model12 || model12Gen2;
    m_supportsTouchscreen = model12 || model12Gen2 || model13Pro;

    QString product;
    if (model12) {
        product = i18n("Framework Laptop 12");
    } else if (model12Gen2) {
        product = i18n("Framework Laptop 12 (2nd Gen)");
    } else if (model13) {
        product = i18n("Framework Laptop 13");
    } else {
        product = i18n("Framework Laptop 13 Pro");
    }

    m_systemInfo = {{u"product"_s, product},
                    {u"platform"_s, m_fixtureModel},
                    {u"isFramework"_s, true},
                    {u"biosVersion"_s, u"Fixture BIOS 1.0"_s},
                    {u"biosDate"_s, u"2026-01-01"_s},
                    {u"ecVersion"_s, u"Fixture EC 1.0"_s},
                    {u"ecRoVersion"_s, u"Fixture RO 1.0"_s},
                    {u"ecRwVersion"_s, u"Fixture RW 1.0"_s},
                    {u"ecCurrentImage"_s, u"rw"_s},
                    {u"pdVersions"_s, QVariantList{}},
                    {u"micEnabled"_s, true},
                    {u"cameraEnabled"_s, true},
                    {u"privacyKnown"_s, true},
                    {u"daemonVersion"_s, u"fixture"_s}};
    m_powerInfo = {{u"acPresent"_s, true},    {u"batteryPresent"_s, true},
                   {u"percentage"_s, 67},     {u"charging"_s, true},
                   {u"discharging"_s, false}, {u"critical"_s, false},
                   {u"cycleCount"_s, 42},     {u"manufacturer"_s, u"Fixture Battery"_s}};
    m_sensors = {
        QVariantMap{
            {u"index"_s, 0}, {u"location"_s, u"cpu"_s}, {u"name"_s, u"CPU"_s}, {u"temp"_s, 48}, {u"status"_s, u"ok"_s}},
        QVariantMap{{u"index"_s, 1},
                    {u"location"_s, u"battery"_s},
                    {u"name"_s, u"Battery"_s},
                    {u"temp"_s, 31},
                    {u"status"_s, u"ok"_s}}};
    m_fans = {
        QVariantMap{{u"position"_s, u"apu"_s}, {u"name"_s, u"CPU fan"_s}, {u"rpm"_s, 1800}, {u"stalled"_s, false}}};
    m_throttle = {{u"known"_s, true}, {u"hard"_s, false}, {u"soft"_s, false}};
    m_ports = {QVariantMap{{u"position"_s, u"right-back"_s},
                           {u"ok"_s, true},
                           {u"role"_s, u"sink"_s},
                           {u"chargingType"_s, u"pd"_s},
                           {u"maxPower"_s, 65000000},
                           {u"voltageNow"_s, 20000}},
               QVariantMap{{u"position"_s, u"right-front"_s}, {u"ok"_s, true}, {u"role"_s, u"disconnected"_s}},
               QVariantMap{{u"position"_s, u"left-front"_s}, {u"ok"_s, true}, {u"role"_s, u"disconnected"_s}},
               QVariantMap{{u"position"_s, u"left-back"_s}, {u"ok"_s, true}, {u"role"_s, u"disconnected"_s}}};
    Q_EMIT fixtureChanged();
    Q_EMIT supportChanged();
    Q_EMIT systemInfoChanged();
    Q_EMIT powerChanged();
    Q_EMIT thermalChanged();
    Q_EMIT portsChanged();
}

void FrameworkKcm::loadFixture() {
    updateFixtureProfile();
    settingsEdited();
}

// Take a value read from the daemon, keeping the user's unsaved edit if there is one
template<typename T>
void FrameworkKcm::syncSetting(T FrameworkSettings::*field, const T &value) {
    if (m_current.*field == m_saved.*field) {
        m_current.*field = value;
    }
    m_saved.*field = value;
}

void FrameworkKcm::loadSettings() {
    if (m_fixtureMode) {
        return;
    }
    const auto onError = [this](const QDBusError &error) {
        if (!isServiceMissing(error)) {
            setError(error.message());
        }
    };

    call(
        u"GetChargeSettings"_s, {},
        [this](const QDBusMessage &reply) {
            const auto map = replyArg(reply, 0).toMap();
            const bool overridden = map.value(u"overrideActive"_s).toBool();
            if (m_chargeLimitOverridden != overridden) {
                m_chargeLimitOverridden = overridden;
                Q_EMIT chargeOverrideChanged();
            }
            syncSetting(&FrameworkSettings::chargeLimit, map.value(u"maxLimit"_s).toInt());
            syncSetting(&FrameworkSettings::chargeRateLimit, map.value(u"rateLimit"_s, 1.0).toDouble());
            syncSetting(&FrameworkSettings::chargeRateSoc, qRound(map.value(u"rateLimitSoc"_s, -1.0).toDouble()));
            settingsEdited();
        },
        onError);

    call(
        u"GetFanControl"_s, {},
        [this](const QDBusMessage &reply) {
            const auto map = replyArg(reply, 0).toMap();
            const QString mode = map.value(u"mode"_s).toString();
            const int value = map.value(u"value"_s).toInt();
            syncSetting(&FrameworkSettings::fanMode, mode);
            if (mode == u"duty"_s) {
                syncSetting(&FrameworkSettings::fanDuty, value);
            } else if (mode == u"rpm"_s) {
                syncSetting(&FrameworkSettings::fanRpm, value);
            }
            settingsEdited();
        },
        onError);

    call(
        u"GetInput"_s, {},
        [this](const QDBusMessage &reply) {
            const auto map = replyArg(reply, 0).toMap();
            m_fpLedSupported = map.value(u"fpLedSupported"_s).toBool();
            Q_EMIT supportChanged();
            syncSetting(&FrameworkSettings::fpLedLevel, map.value(u"fpLedLevel"_s).toString());
            syncSetting(&FrameworkSettings::hapticIntensity, map.value(u"hapticIntensity"_s).toInt());
            syncSetting(&FrameworkSettings::clickForce, map.value(u"clickForce"_s).toString());
            settingsEdited();
        },
        onError);
}

void FrameworkKcm::setLiveData(const QString &liveData) {
    if (m_liveData == liveData) {
        return;
    }
    m_liveData = liveData;
    Q_EMIT liveDataChanged();

    if (m_fixtureMode) {
        m_liveTimer.stop();
        return;
    }

    if (m_liveData.isEmpty()) {
        m_liveTimer.stop();
    } else {
        refreshLive();
        m_liveTimer.start();
    }
}

void FrameworkKcm::refreshLive() {
    if (m_fixtureMode) {
        return;
    }
    // Don't pile up requests if the EC is slow
    if (m_liveInFlight || m_liveData.isEmpty()) {
        return;
    }
    m_liveInFlight = true;

    const auto done = [this](const QDBusError &) { m_liveInFlight = false; };

    if (m_liveData == u"thermal"_s) {
        call(
            u"GetThermal"_s, {},
            [this](const QDBusMessage &reply) {
                m_liveInFlight = false;
                const auto sensors = replyArg(reply, 0).toList();
                const auto fans = replyArg(reply, 1).toList();
                const auto throttle = replyArg(reply, 2).toMap();
                // Reassigning a Repeater's model rebuilds all delegates, so only on change
                if (sensors != m_sensors || fans != m_fans || throttle != m_throttle) {
                    m_sensors = sensors;
                    m_fans = fans;
                    m_throttle = throttle;
                    Q_EMIT thermalChanged();
                }
            },
            done);
    } else if (m_liveData == u"ports"_s) {
        call(
            u"GetPorts"_s, {},
            [this](const QDBusMessage &reply) {
                m_liveInFlight = false;
                const auto ports = replyArg(reply, 0).toList();
                if (ports != m_ports) {
                    m_ports = ports;
                    Q_EMIT portsChanged();
                }
            },
            done);
    }
}

FrameworkKcm::PendingWrite FrameworkKcm::fanWrite(const FrameworkSettings &s) {
    if (s.fanMode == u"duty"_s) {
        return {u"SetFanDuty"_s, {-1, s.fanDuty}};
    }
    if (s.fanMode == u"rpm"_s) {
        return {u"SetFanRpm"_s, {-1, s.fanRpm}};
    }
    return {u"SetAutoFan"_s, {-1}};
}

void FrameworkKcm::save() {
    KQuickConfigModule::save();
    if (m_fixtureMode) {
        m_saved = m_current;
        settingsEdited();
        return;
    }

    const auto &c = m_current;
    const auto &s = m_saved;
    m_writeQueue.clear();

    if (c.chargeLimit != s.chargeLimit) {
        m_writeQueue.append({u"SetChargeLimit"_s, {c.chargeLimit}});
    }
    if (c.chargeRateLimit != s.chargeRateLimit || c.chargeRateSoc != s.chargeRateSoc) {
        m_writeQueue.append({u"SetChargeRateLimit"_s, {c.chargeRateLimit, static_cast<double>(c.chargeRateSoc)}});
    }
    if (const auto fan = fanWrite(c); fan != fanWrite(s)) {
        m_writeQueue.append(fan);
    }
    if (c.fpLedLevel != s.fpLedLevel && !c.fpLedLevel.isEmpty()) {
        m_writeQueue.append({u"SetFpLedLevel"_s, {c.fpLedLevel}});
    }
    if (c.hapticIntensity != s.hapticIntensity && c.hapticIntensity >= 0) {
        m_writeQueue.append({u"SetHapticIntensity"_s, {c.hapticIntensity}});
    }
    if (c.clickForce != s.clickForce && !c.clickForce.isEmpty()) {
        m_writeQueue.append({u"SetClickForce"_s, {c.clickForce}});
    }

    clearError();
    runNextWrite();
}

// One at a time, so polkit asks for the password once instead of per request
void FrameworkKcm::runNextWrite() {
    if (m_writeQueue.isEmpty()) {
        setBusy(false);
        // Everything was written; reload merges in what the hardware now reports
        m_saved = m_current;
        loadSettings();
        return;
    }

    setBusy(true);
    const PendingWrite write = m_writeQueue.takeFirst();
    call(
        write.method, write.args, [this](const QDBusMessage &) { runNextWrite(); },
        [this](const QDBusError &error) {
            m_writeQueue.clear();
            setBusy(false);
            setWriteError(error);
            // Keep the unsaved edits so the user can retry
            setNeedsSave(true);
        },
        s_writeTimeout);
}

void FrameworkKcm::overrideChargeLimit() { runAction(u"OverrideChargeLimit"_s); }

void FrameworkKcm::cancelChargeLimitOverride() { runAction(u"CancelChargeLimitOverride"_s); }

void FrameworkKcm::runAction(const QString &method) {
    clearError();
    if (m_fixtureMode) {
        m_chargeLimitOverridden = method == u"OverrideChargeLimit"_s;
        Q_EMIT chargeOverrideChanged();
        return;
    }
    setBusy(true);
    call(
        method, {},
        [this](const QDBusMessage &) {
            setBusy(false);
            loadSettings();
        },
        [this](const QDBusError &error) {
            setBusy(false);
            setWriteError(error);
        },
        s_writeTimeout);
}

void FrameworkKcm::setWriteError(const QDBusError &error) {
    if (error.name() == u"io.github.frameworkkcm.Error.NotAuthorized"_s) {
        setError(i18n("You are not authorized to change this setting."));
    } else if (isServiceMissing(error)) {
        setError(i18n("The Framework hardware service is not running."));
    } else {
        setError(error.message());
    }
}

void FrameworkKcm::defaults() {
    KQuickConfigModule::defaults();

    m_current = withDefaults(m_current);
    settingsEdited();
}

void FrameworkKcm::settingsEdited() {
    Q_EMIT settingsChanged();
    setNeedsSave(m_current != m_saved);
    setRepresentsDefaults(m_current == withDefaults(m_current));
}

#define SETTER(Name, member, Type)                                                                                     \
    void FrameworkKcm::set##Name(Type value) {                                                                         \
        if (m_current.member == value) {                                                                               \
            return;                                                                                                    \
        }                                                                                                              \
        m_current.member = value;                                                                                      \
        settingsEdited();                                                                                              \
    }

SETTER(ChargeLimit, chargeLimit, int)
SETTER(ChargeRateLimit, chargeRateLimit, double)
SETTER(ChargeRateSoc, chargeRateSoc, int)
SETTER(FanMode, fanMode, const QString &)
SETTER(FanDuty, fanDuty, int)
SETTER(FanRpm, fanRpm, int)
SETTER(FpLedLevel, fpLedLevel, const QString &)
SETTER(HapticIntensity, hapticIntensity, int)
SETTER(ClickForce, clickForce, const QString &)

#undef SETTER

void FrameworkKcm::clearError() { setError(QString()); }

void FrameworkKcm::loadSchedule() {
    const auto path =
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + u"/framework-kcm/schedule.json"_s;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        return;
    }
    const auto object = document.object();
    QVariantList loaded;
    for (const auto &value: object.value(u"schedules"_s).toArray()) {
        const auto entry = value.toObject();
        QStringList days;
        for (const auto &day: entry.value(u"days"_s).toArray()) {
            days.append(day.toString());
        }
        loaded.append(QVariantMap{{u"days"_s, days},
                                  {u"time"_s, entry.value(u"time"_s).toString()},
                                  {u"limit"_s, entry.value(u"limit"_s).toInt(80)}});
    }
    if (!loaded.isEmpty()) {
        m_schedules = loaded;
    }
    m_scheduleEnabled = object.value(u"enabled"_s).toBool();
}

bool FrameworkKcm::configureSchedule(const bool enabled, const QVariantList &schedules) {
    clearError();
    const QRegularExpression timePattern(u"^([01]\\d|2[0-3]):[0-5]\\d$"_s);
    const QSet<QString> validDays{u"Mon"_s, u"Tue"_s, u"Wed"_s, u"Thu"_s, u"Fri"_s, u"Sat"_s, u"Sun"_s};
    QSet<QString> scheduleKeys;
    QVariantList normalized;
    if (enabled && schedules.isEmpty()) {
        setError(i18n("Add at least one schedule."));
        return false;
    }
    for (const auto &item: schedules) {
        const auto entry = item.toMap();
        QStringList days = entry.value(u"days"_s).toStringList();
        const auto time = entry.value(u"time"_s).toString();
        if (enabled && (days.isEmpty() || !timePattern.match(time).hasMatch())) {
            setError(i18n("Each schedule needs at least one day and a valid time in HH:MM format."));
            return false;
        }
        if (enabled) {
            QSet<QString> entryDays;
            for (const auto &day: days) {
                if (!validDays.contains(day) || entryDays.contains(day)) {
                    setError(i18n("Each schedule must use unique weekdays."));
                    return false;
                }
                entryDays.insert(day);
                const auto key = day + u"|"_s + time;
                if (scheduleKeys.contains(key)) {
                    setError(i18n("The same weekday and time cannot be scheduled more than once."));
                    return false;
                }
                scheduleKeys.insert(key);
            }
        }
        normalized.append(QVariantMap{
            {u"days"_s, days}, {u"time"_s, time}, {u"limit"_s, std::clamp(entry.value(u"limit"_s).toInt(), 25, 100)}});
    }

    if (!m_fixtureMode && !applyScheduleUnits(enabled, normalized)) {
        return false;
    }
    if (!m_fixtureMode) {
        const auto path =
            QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + u"/framework-kcm/schedule.json"_s;
        QSaveFile file(path);
        if (!QDir().mkpath(QFileInfo(path).absolutePath()) || !file.open(QIODevice::WriteOnly)) {
            setError(i18n("Could not save the charge schedule configuration."));
            return false;
        }
        QJsonArray entries;
        for (const auto &item: normalized) {
            const auto entry = item.toMap();
            QJsonArray days;
            for (const auto &day: entry.value(u"days"_s).toStringList()) {
                days.append(day);
            }
            entries.append(QJsonObject{{u"days"_s, days},
                                       {u"time"_s, entry.value(u"time"_s).toString()},
                                       {u"limit"_s, entry.value(u"limit"_s).toInt()}});
        }
        const QJsonObject object{{u"enabled"_s, enabled}, {u"schedules"_s, entries}};
        file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
        if (!file.commit()) {
            setError(i18n("Could not save the charge schedule configuration."));
            return false;
        }
    }
    m_scheduleEnabled = enabled;
    m_schedules = normalized;
    Q_EMIT scheduleChanged();
    return true;
}

bool FrameworkKcm::applyScheduleUnits(const bool enabled, const QVariantList &schedules) {
    const auto configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + u"/systemd/user"_s;
    if (!QDir().mkpath(configDir)) {
        setError(i18n("Could not create the user systemd configuration directory."));
        return false;
    }
    const auto runSystemctl = [this](const QStringList &arguments, const bool required) {
        QProcess process;
        process.start(u"systemctl"_s, QStringList{u"--user"_s} + arguments);
        if (!process.waitForStarted(5000) || !process.waitForFinished(15000)) {
            process.kill();
            process.waitForFinished();
            if (required) {
                setError(i18n("The user systemd manager did not respond."));
                return false;
            }
            return true;
        }
        if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
            if (required) {
                const auto detail = QString::fromLocal8Bit(process.readAllStandardError()).trimmed();
                setError(detail.isEmpty() ? i18n("Could not update the user systemd schedule.") : detail);
                return false;
            }
        }
        return true;
    };
    QString tool;
    if (enabled) {
        for (const auto &name: {u"framework_tool"_s, u"framework-tool"_s, u"framework-system"_s}) {
            tool = QStandardPaths::findExecutable(name);
            if (!tool.isEmpty()) {
                break;
            }
        }
        if (tool.isEmpty()) {
            setError(i18n("framework_tool was not found. Install framework-system to use charge schedules."));
            return false;
        }
    }
    if (QFile::exists(configDir + u"/framework-charge-limit.timer"_s)) {
        runSystemctl({u"disable"_s, u"--now"_s, u"framework-charge-limit.timer"_s}, false);
    }
    for (int index = 0; index < 100; ++index) {
        const auto timerPath = configDir + u"/framework-charge-limit-%1.timer"_s.arg(index);
        if (QFile::exists(timerPath)) {
            runSystemctl({u"disable"_s, u"--now"_s, u"framework-charge-limit-%1.timer"_s.arg(index)}, false);
        }
    }
    if (!enabled) {
        for (int index = 0; index < 100; ++index) {
            QFile::remove(configDir + u"/framework-charge-limit-%1.service"_s.arg(index));
            QFile::remove(configDir + u"/framework-charge-limit-%1.timer"_s.arg(index));
        }
        QFile::remove(configDir + u"/framework-charge-limit.service"_s);
        QFile::remove(configDir + u"/framework-charge-limit.timer"_s);
        return runSystemctl({u"daemon-reload"_s}, true);
    }

    auto escapedTool = tool;
    escapedTool.replace(u" "_s, u"\\x20"_s);
    for (qsizetype index = 0; index < schedules.size(); ++index) {
        const auto entry = schedules.at(index).toMap();
        const auto servicePath = configDir + u"/framework-charge-limit-%1.service"_s.arg(index);
        const auto timerPath = configDir + u"/framework-charge-limit-%1.timer"_s.arg(index);
        QSaveFile service(servicePath);
        QSaveFile timer(timerPath);
        if (!service.open(QIODevice::WriteOnly) || !timer.open(QIODevice::WriteOnly)) {
            setError(i18n("Could not write the user systemd schedule."));
            return false;
        }
        const auto serviceText =
            u"[Unit]\nDescription=Apply Framework battery charge limit\n\n[Service]\nType=oneshot\nExecStart=%1 --charge-limit %2\n"_s
                .arg(escapedTool, QString::number(entry.value(u"limit"_s).toInt()));
        auto timerText = u"[Unit]\nDescription=Framework battery charge limit schedule\n\n[Timer]\n"_s;
        for (const auto &day: entry.value(u"days"_s).toStringList()) {
            timerText += u"OnCalendar=%1 *-*-* %2:00\n"_s.arg(day, entry.value(u"time"_s).toString());
        }
        timerText += u"Persistent=true\n\n[Install]\nWantedBy=timers.target\n"_s;
        service.write(serviceText.toUtf8());
        timer.write(timerText.toUtf8());
        if (!service.commit() || !timer.commit()) {
            setError(i18n("Could not write the user systemd schedule."));
            return false;
        }
    }
    for (int index = schedules.size(); index < 100; ++index) {
        QFile::remove(configDir + u"/framework-charge-limit-%1.service"_s.arg(index));
        QFile::remove(configDir + u"/framework-charge-limit-%1.timer"_s.arg(index));
    }
    QFile::remove(configDir + u"/framework-charge-limit.service"_s);
    QFile::remove(configDir + u"/framework-charge-limit.timer"_s);
    if (!runSystemctl({u"daemon-reload"_s}, true)) {
        return false;
    }
    for (qsizetype index = 0; index < schedules.size(); ++index) {
        if (!runSystemctl({u"enable"_s, u"--now"_s, u"framework-charge-limit-%1.timer"_s.arg(index)}, true)) {
            return false;
        }
    }
    return true;
}

void FrameworkKcm::setError(const QString &message) {
    if (m_errorMessage != message) {
        m_errorMessage = message;
        Q_EMIT errorMessageChanged();
    }
}

void FrameworkKcm::setBusy(bool busy) {
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

void FrameworkKcm::setDaemonAvailable(bool available) {
    if (m_daemonAvailable != available) {
        m_daemonAvailable = available;
        Q_EMIT daemonAvailableChanged();
    }
}

#include "frameworkkcm.moc"
