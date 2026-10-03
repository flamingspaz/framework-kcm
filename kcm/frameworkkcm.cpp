// SPDX-License-Identifier: GPL-3.0-or-later

#include "frameworkkcm.h"

#ifndef FRAMEWORK_STANDALONE
#include <KLocalizedString>
#endif

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>


using namespace Qt::StringLiterals;

namespace {
    QString localized(const char *text) {
#ifdef FRAMEWORK_STANDALONE
        return QCoreApplication::translate("FrameworkSettings", text);
#else
        return i18n(text);
#endif
    }

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

#ifdef FRAMEWORK_STANDALONE
FrameworkKcm::FrameworkKcm(QObject *parent) : QObject(parent) {
#else
FrameworkKcm::FrameworkKcm(QObject *parent, const KPluginMetaData &data) : KQuickConfigModule(parent, data) {
#endif
#ifndef FRAMEWORK_STANDALONE
    setButtons(Help | Default | Apply);
#endif

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
#ifndef FRAMEWORK_STANDALONE
    KQuickConfigModule::load();
#endif

    // Reset: drop unsaved edits, then take whatever the hardware reports
    m_current = m_saved;
    settingsEdited();

    // Slow (talks to the PD controllers over I2C), and never changes, so only once
    call(u"GetSystemInfo"_s, {}, [this](const QDBusMessage &reply) {
        m_systemInfo = replyArg(reply, 0).toMap();
        Q_EMIT systemInfoChanged();
    });

    loadSettings();
    refreshLive();
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

    if (m_liveData.isEmpty()) {
        m_liveTimer.stop();
    } else {
        refreshLive();
        m_liveTimer.start();
    }
}

void FrameworkKcm::refreshLive() {
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
#ifndef FRAMEWORK_STANDALONE
    KQuickConfigModule::save();
#endif

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
        updateNeedsSave(false);
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
            updateNeedsSave(true);
        },
        s_writeTimeout);
}

void FrameworkKcm::overrideChargeLimit() { runAction(u"OverrideChargeLimit"_s); }

void FrameworkKcm::cancelChargeLimitOverride() { runAction(u"CancelChargeLimitOverride"_s); }

void FrameworkKcm::runAction(const QString &method) {
    clearError();
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
        setError(localized("You are not authorized to change this setting."));
    } else if (isServiceMissing(error)) {
        setError(localized("The Framework hardware service is not running."));
    } else {
        setError(error.message());
    }
}

void FrameworkKcm::defaults() {
#ifndef FRAMEWORK_STANDALONE
    KQuickConfigModule::defaults();
#endif

    m_current = withDefaults(m_current);
    settingsEdited();
}

void FrameworkKcm::settingsEdited() {
    Q_EMIT settingsChanged();
    updateNeedsSave(m_current != m_saved);
#ifndef FRAMEWORK_STANDALONE
    setRepresentsDefaults(m_current == withDefaults(m_current));
#endif
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

void FrameworkKcm::updateNeedsSave(bool needsSave) {
#ifdef FRAMEWORK_STANDALONE
    if (m_needsSave != needsSave) {
        m_needsSave = needsSave;
        Q_EMIT needsSaveChanged();
    }
#else
    setNeedsSave(needsSave);
#endif
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
