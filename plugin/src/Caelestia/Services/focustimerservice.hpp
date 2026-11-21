#pragma once

#include <qdbusconnection.h>
#include <qdbusmessage.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

class QDBusServiceWatcher;

namespace caelestia::shell::services {

// D-Bus bridge to io.github.focustimerhq.FocusTimer (formerly GNOME Pomodoro) so Caelestia's
// desktop widget, notch indicator, pre-end prompt, and layer-shell break overlay stay synced with
// the running Flatpak/native app without spawning CLI processes on every tick.
class FocusTimerService : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool active READ active NOTIFY stateChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool isBreak READ isBreak NOTIFY stateChanged)
    Q_PROPERTY(int durationSecs READ durationSecs NOTIFY durationSecsChanged)
    Q_PROPERTY(int remainingSecs READ remainingSecs NOTIFY remainingSecsChanged)
    Q_PROPERTY(int elapsedSecs READ elapsedSecs NOTIFY elapsedSecsChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY remainingSecsChanged)
    Q_PROPERTY(int reopenDelaySecs READ reopenDelaySecs NOTIFY reopenDelaySecsChanged)
    Q_PROPERTY(bool announceAboutToEnd READ announceAboutToEnd NOTIFY announceAboutToEndChanged)
    Q_PROPERTY(bool nativeScreenOverlay READ nativeScreenOverlay NOTIFY nativeScreenOverlayChanged)
    Q_PROPERTY(bool waitingForInput READ waitingForInput NOTIFY waitingForInputChanged)

public:
    explicit FocusTimerService(QObject* parent = nullptr);

    [[nodiscard]] bool connected() const;
    [[nodiscard]] QString state() const;
    [[nodiscard]] bool started() const;
    [[nodiscard]] bool finished() const;
    [[nodiscard]] bool active() const;
    [[nodiscard]] bool paused() const;
    [[nodiscard]] bool running() const;
    [[nodiscard]] bool isBreak() const;
    [[nodiscard]] int durationSecs() const;
    [[nodiscard]] int remainingSecs() const;
    [[nodiscard]] int elapsedSecs() const;
    [[nodiscard]] qreal progress() const;
    [[nodiscard]] int reopenDelaySecs() const;
    [[nodiscard]] bool announceAboutToEnd() const;
    [[nodiscard]] bool nativeScreenOverlay() const;
    [[nodiscard]] bool waitingForInput() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void skip();
    Q_INVOKABLE void reset();
    Q_INVOKABLE void advance();
    Q_INVOKABLE void startNextAfterBreak();
    Q_INVOKABLE void extendSecs(qint64 secs);
    Q_INVOKABLE void showWindow(const QString& view = QString());
    Q_INVOKABLE void showPreferences(const QString& view = QString());
    Q_INVOKABLE void disableNativeOverlay();
    Q_INVOKABLE void refresh();

signals:
    void connectedChanged();
    void stateChanged();
    void pausedChanged();
    void runningChanged();
    void durationSecsChanged();
    void remainingSecsChanged();
    void elapsedSecsChanged();
    void reopenDelaySecsChanged();
    void announceAboutToEndChanged();
    void nativeScreenOverlayChanged();
    void waitingForInputChanged();
    void confirmRequested();

private slots:
    void onServiceRegistered(const QString& service);
    void onServiceUnregistered(const QString& service);
    void onTimerChanged();
    void onTimerTick(qint64 timestamp);
    void onSessionChanged();
    void onConfirmAdvancement(const QDBusMessage& message);
    void onPropertiesChanged(const QDBusMessage& message);
    void onLocalTick();

private:
    bool m_connected = false;
    QString m_state = QStringLiteral("stopped");
    bool m_paused = false;
    int m_pomodoroDurationSecs = 1500;
    int m_durationSecs = 1500;
    int m_remainingSecs = 1500;
    int m_elapsedSecs = 0;
    qint64 m_durationUs = 1500LL * 1000000LL;
    qint64 m_offsetUs = 0;
    qint64 m_startedTimeUs = -1;
    qint64 m_pausedTimeUs = -1;
    qint64 m_finishedTimeUs = -1;
    int m_reopenDelaySecs = 30;
    bool m_announceAboutToEnd = true;
    bool m_nativeScreenOverlay = false;
    bool m_nativeOverlayDisabledOnce = false;
    bool m_waitingForInput = false;
    bool m_wasInRunningBreak = false;
    bool m_wasInRunningPomodoro = false;
    bool m_pauseForInputInFlight = false;
    bool m_skipRequestedByUser = false;
    bool m_startOnConnect = false;
    bool m_backendLaunchAttempted = false;
    bool m_queryInFlight = false;
    bool m_queryPending = false;

    QDBusServiceWatcher* m_watcher = nullptr;
    QTimer m_tickTimer;

    void connectDbusSignals();
    void ensureBackendService();
    void queryTimerState();
    void querySettings();
    void callTimerMethod(const QString& method);
    void callTimerMethodInt64(const QString& method, qint64 arg);
    void advanceToState(const QString& targetState, bool startAfter = false, bool resetOnFailure = false);
    void resetAndStartPomodoro();
    void applyTimerProps(const QVariantMap& props);
    void recalculateRemainingFromTimestamps(qint64 timestampUs = 0);
    void updateTickTimer();

    void setConnected(bool value);
    void setState(const QString& value);
    void setPaused(bool value);
    void setWaitingForInput(bool value);
    void setDurationSecs(int secs);
    void setRemainingSecs(int secs);
    void setElapsedSecs(int secs);
};

} // namespace caelestia::shell::services
