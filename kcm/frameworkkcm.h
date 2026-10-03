// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#ifdef FRAMEWORK_STANDALONE
#include <QObject>
#else
#include <KQuickConfigModule>
#endif

#include <QDBusError>
#include <QDBusMessage>
#include <QTimer>
#include <QVariant>

#include <functional>

// Settings the user edits; applied through the daemon on save()
struct FrameworkSettings {
    // Defaults; defaults() and representsDefaults use these (see withDefaults())
    int chargeLimit = 100;
    double chargeRateLimit = 1.0;
    int chargeRateSoc = -1; // -1: limit applies at any battery level
    QString fanMode = QStringLiteral("auto"); // auto, duty, rpm
    int fanDuty = 50;
    int fanRpm = 3000;
    QString fpLedLevel;
    int hapticIntensity = -1; // -1: never set, the touchpad can't report it
    QString clickForce;

    bool operator==(const FrameworkSettings &) const = default;
};

#ifdef FRAMEWORK_STANDALONE
class FrameworkKcm : public QObject {
#else
class FrameworkKcm : public KQuickConfigModule {
#endif
    Q_OBJECT

#ifdef FRAMEWORK_STANDALONE
    Q_PROPERTY(bool needsSave READ needsSave NOTIFY needsSaveChanged)
#endif
    Q_PROPERTY(bool daemonAvailable READ daemonAvailable NOTIFY daemonAvailableChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    // Which live readings the visible page needs: "thermal", "ports" or empty
    Q_PROPERTY(QString liveData READ liveData WRITE setLiveData NOTIFY liveDataChanged)

    // Live readings, refreshed every couple of seconds while shown
    Q_PROPERTY(QVariantMap systemInfo READ systemInfo NOTIFY systemInfoChanged)
    Q_PROPERTY(QVariantList sensors READ sensors NOTIFY thermalChanged)
    Q_PROPERTY(QVariantList fans READ fans NOTIFY thermalChanged)
    Q_PROPERTY(QVariantMap throttle READ throttle NOTIFY thermalChanged)
    Q_PROPERTY(QVariantList ports READ ports NOTIFY portsChanged)
    Q_PROPERTY(bool fpLedSupported READ fpLedSupported NOTIFY supportChanged)
    Q_PROPERTY(bool chargeLimitOverridden READ chargeLimitOverridden NOTIFY chargeOverrideChanged)

    // Editable settings
    Q_PROPERTY(int chargeLimit READ chargeLimit WRITE setChargeLimit NOTIFY settingsChanged)
    Q_PROPERTY(double chargeRateLimit READ chargeRateLimit WRITE setChargeRateLimit NOTIFY settingsChanged)
    Q_PROPERTY(int chargeRateSoc READ chargeRateSoc WRITE setChargeRateSoc NOTIFY settingsChanged)
    Q_PROPERTY(QString fanMode READ fanMode WRITE setFanMode NOTIFY settingsChanged)
    Q_PROPERTY(int fanDuty READ fanDuty WRITE setFanDuty NOTIFY settingsChanged)
    Q_PROPERTY(int fanRpm READ fanRpm WRITE setFanRpm NOTIFY settingsChanged)
    Q_PROPERTY(QString fpLedLevel READ fpLedLevel WRITE setFpLedLevel NOTIFY settingsChanged)
    Q_PROPERTY(int hapticIntensity READ hapticIntensity WRITE setHapticIntensity NOTIFY settingsChanged)
    Q_PROPERTY(QString clickForce READ clickForce WRITE setClickForce NOTIFY settingsChanged)

public:
#ifdef FRAMEWORK_STANDALONE
    explicit FrameworkKcm(QObject *parent = nullptr);
    [[nodiscard]] bool needsSave() const { return m_needsSave; }
    Q_INVOKABLE void load();
    Q_INVOKABLE void save();
    Q_INVOKABLE void defaults();
#else
    FrameworkKcm(QObject *parent, const KPluginMetaData &data);

    void load() override;
    void save() override;
    void defaults() override;
#endif

    [[nodiscard]] bool daemonAvailable() const { return m_daemonAvailable; }
    [[nodiscard]] bool busy() const { return m_busy; }
    [[nodiscard]] QString errorMessage() const { return m_errorMessage; }
    [[nodiscard]] QString liveData() const { return m_liveData; }
    void setLiveData(const QString &liveData);

    [[nodiscard]] QVariantMap systemInfo() const { return m_systemInfo; }
    [[nodiscard]] QVariantList sensors() const { return m_sensors; }
    [[nodiscard]] QVariantList fans() const { return m_fans; }
    [[nodiscard]] QVariantMap throttle() const { return m_throttle; }
    [[nodiscard]] QVariantList ports() const { return m_ports; }
    [[nodiscard]] bool fpLedSupported() const { return m_fpLedSupported; }
    [[nodiscard]] bool chargeLimitOverridden() const { return m_chargeLimitOverridden; }

    [[nodiscard]] int chargeLimit() const { return m_current.chargeLimit; }
    [[nodiscard]] double chargeRateLimit() const { return m_current.chargeRateLimit; }
    [[nodiscard]] int chargeRateSoc() const { return m_current.chargeRateSoc; }
    [[nodiscard]] QString fanMode() const { return m_current.fanMode; }
    [[nodiscard]] int fanDuty() const { return m_current.fanDuty; }
    [[nodiscard]] int fanRpm() const { return m_current.fanRpm; }
    [[nodiscard]] QString fpLedLevel() const { return m_current.fpLedLevel; }
    [[nodiscard]] int hapticIntensity() const { return m_current.hapticIntensity; }
    [[nodiscard]] QString clickForce() const { return m_current.clickForce; }

    void setChargeLimit(int value);
    void setChargeRateLimit(double value);
    void setChargeRateSoc(int value);
    void setFanMode(const QString &value);
    void setFanDuty(int value);
    void setFanRpm(int value);
    void setFpLedLevel(const QString &value);
    void setHapticIntensity(int value);
    void setClickForce(const QString &value);

    Q_INVOKABLE void clearError();
    // Charge to 100% until the next boot; applied immediately, not on Apply
    Q_INVOKABLE void overrideChargeLimit();
    Q_INVOKABLE void cancelChargeLimitOverride();

Q_SIGNALS:
#ifdef FRAMEWORK_STANDALONE
    void needsSaveChanged();
#endif
    void daemonAvailableChanged();
    void busyChanged();
    void errorMessageChanged();
    void liveDataChanged();
    void systemInfoChanged();
    void thermalChanged();
    void portsChanged();
    void supportChanged();
    void settingsChanged();
    void chargeOverrideChanged();

private:
    using ReplyHandler = std::function<void(const QDBusMessage &)>;
    using ErrorHandler = std::function<void(const QDBusError &)>;

    void call(const QString &method, const QVariantList &args, const ReplyHandler &onReply,
              const ErrorHandler &onError = {}, int timeout = -1);
    void refreshLive();
    void loadSettings();
    template<typename T>
    void syncSetting(T FrameworkSettings::*field, const T &value);
    void runNextWrite();
    void settingsEdited();
    void setError(const QString &message);
    void setWriteError(const QDBusError &error);
    void updateNeedsSave(bool needsSave);
    void runAction(const QString &method);
    void setBusy(bool busy);
    void setDaemonAvailable(bool available);

    FrameworkSettings m_current;
    FrameworkSettings m_saved;

    struct PendingWrite {
        QString method;
        QVariantList args;

        bool operator==(const PendingWrite &) const = default;
    };
    static PendingWrite fanWrite(const FrameworkSettings &s);
    QList<PendingWrite> m_writeQueue;

#ifdef FRAMEWORK_STANDALONE
    bool m_needsSave = false;
#endif
    bool m_daemonAvailable = true;
    bool m_busy = false;
    bool m_liveInFlight = false;
    QString m_errorMessage;
    QString m_liveData;
    QTimer m_liveTimer;

    QVariantMap m_systemInfo;
    QVariantList m_sensors;
    QVariantList m_fans;
    QVariantMap m_throttle;
    QVariantList m_ports;
    bool m_fpLedSupported = false;
    bool m_chargeLimitOverridden = false;
};
