#include "focustimerservice.hpp"

#include <qdatetime.h>
#include <qdbusargument.h>
#include <qdbusconnectioninterface.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusreply.h>
#include <qdbusservicewatcher.h>
#include <qprocess.h>

#include <algorithm>
#include <cmath>

namespace caelestia::shell::services {

using namespace Qt::StringLiterals;

namespace {

const QString k_dbusService = u"io.github.focustimerhq.FocusTimer"_s;
const QString k_dbusPath = u"/io/github/focustimerhq/FocusTimer"_s;
const QString k_appInterface = u"io.github.focustimerhq.FocusTimer"_s;
const QString k_timerInterface = u"io.github.focustimerhq.FocusTimer.Timer"_s;
const QString k_sessionInterface = u"io.github.focustimerhq.FocusTimer.Session"_s;
const QString k_propsInterface = u"org.freedesktop.DBus.Properties"_s;
constexpr qint64 k_usPerSec = 1000000;

qint64 currentEpochUs() {
    return QDateTime::currentMSecsSinceEpoch() * 1000LL;
}

int usToDurationSecs(const qint64 us) {
    if (us <= 0)
        return 0;
    return static_cast<int>(std::llround(static_cast<double>(us) / k_usPerSec));
}

int usToRemainingSecs(const qint64 us, const int maxSecs) {
    if (us <= 0)
        return 0;
    const int s = static_cast<int>(std::llround(static_cast<double>(us) / k_usPerSec));
    return maxSecs > 0 ? std::min(maxSecs, s) : s;
}

QVariantMap unwrapDbusMap(const QVariant& val) {
    if (val.canConvert<QVariantMap>()) {
        const auto m = val.toMap();
        if (!m.isEmpty())
            return m;
    }
    if (val.canConvert<QDBusArgument>()) {
        QVariantMap out;
        val.value<QDBusArgument>() >> out;
        return out;
    }
    return {};
}

} // namespace

FocusTimerService::FocusTimerService(QObject* parent)
    : QObject(parent)
    , m_watcher(new QDBusServiceWatcher(k_dbusService, QDBusConnection::sessionBus(),
          QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this)) {
    m_tickTimer.setInterval(1200);
    connect(&m_tickTimer, &QTimer::timeout, this, &FocusTimerService::onLocalTick);

    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &FocusTimerService::onServiceRegistered);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &FocusTimerService::onServiceUnregistered);

    connectDbusSignals();

    auto* iface = QDBusConnection::sessionBus().interface();
    if (iface && iface->isServiceRegistered(k_dbusService)) {
        setConnected(true);
        refresh();
    } else {
        ensureBackendService();
    }
}

bool FocusTimerService::connected() const {
    return m_connected;
}

QString FocusTimerService::state() const {
    return m_waitingForInput ? u"pomodoro"_s : m_state;
}

bool FocusTimerService::started() const {
    return m_connected && m_startedTimeUs >= 0 && m_state != u"stopped"_s && m_state != u"null"_s && !m_state.isEmpty();
}

bool FocusTimerService::finished() const {
    return started() && m_finishedTimeUs >= 0;
}

bool FocusTimerService::active() const {
    return m_waitingForInput || (started() && !finished());
}

bool FocusTimerService::paused() const {
    return m_waitingForInput || (started() && !finished() && m_paused);
}

bool FocusTimerService::running() const {
    return started() && !finished() && !m_paused && !m_waitingForInput;
}

bool FocusTimerService::isBreak() const {
    return !m_waitingForInput && (m_state == u"short-break"_s || m_state == u"long-break"_s);
}

int FocusTimerService::durationSecs() const {
    return m_durationSecs;
}

int FocusTimerService::remainingSecs() const {
    return m_remainingSecs;
}

int FocusTimerService::elapsedSecs() const {
    return m_elapsedSecs;
}

qreal FocusTimerService::progress() const {
    if (m_durationSecs <= 0)
        return 0.0;
    const qreal raw = 1.0 - static_cast<qreal>(m_remainingSecs) / static_cast<qreal>(m_durationSecs);
    return std::clamp(raw, 0.0, 1.0);
}

int FocusTimerService::reopenDelaySecs() const {
    return m_reopenDelaySecs;
}

bool FocusTimerService::announceAboutToEnd() const {
    return m_announceAboutToEnd;
}

bool FocusTimerService::nativeScreenOverlay() const {
    return m_nativeScreenOverlay;
}

bool FocusTimerService::waitingForInput() const {
    return m_waitingForInput;
}

void FocusTimerService::start() {
    setWaitingForInput(false);
    if (!m_connected) {
        m_startOnConnect = true;
        m_backendLaunchAttempted = false;
        ensureBackendService();
        return;
    }
    if (m_state == u"stopped"_s || m_state == u"null"_s || m_state.isEmpty() || m_durationUs <= 0 || finished()) {
        advance();
    } else if (started() && m_paused) {
        callTimerMethod(u"Resume"_s);
    } else {
        auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, u"Start"_s);
        auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
            w->deleteLater();
            queryTimerState();
            if (!started())
                advance();
        });
    }
}

void FocusTimerService::stop() {
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = false;
    setWaitingForInput(false);
    callTimerMethod(u"Stop"_s);
}

void FocusTimerService::pause() {
    callTimerMethod(u"Pause"_s);
}

void FocusTimerService::resume() {
    setWaitingForInput(false);
    callTimerMethod(u"Resume"_s);
}

void FocusTimerService::toggle() {
    if (!m_connected) {
        m_startOnConnect = true;
        m_backendLaunchAttempted = false;
        ensureBackendService();
        return;
    }
    if (m_waitingForInput) {
        startNextAfterBreak();
        return;
    }
    if (finished() || !started())
        start();
    else if (m_paused)
        resume();
    else
        pause();
}

void FocusTimerService::skip() {
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = true;
    setWaitingForInput(false);
    callTimerMethod(u"Skip"_s);
}

void FocusTimerService::reset() {
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = false;
    setWaitingForInput(false);
    callTimerMethod(u"Reset"_s);
}

void FocusTimerService::advance() {
    if (!m_connected)
        return;
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = true;
    setWaitingForInput(false);
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_sessionInterface, u"Advance"_s);
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        refresh();
    });
}

void FocusTimerService::startNextAfterBreak() {
    if (!m_waitingForInput)
        return;
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = true;
    setWaitingForInput(false);
    if (!m_connected)
        return;
    if (m_state == u"long-break"_s || m_state == u"stopped"_s || m_state == u"null"_s) {
        // After the 4th cycle (long break or completed session), reset the session back to
        // Pomodoro #1 and start it automatically so cycles loop indefinitely until stopped.
        resetAndStartPomodoro();
    } else if (m_state == u"pomodoro"_s && !finished()) {
        if (started() && m_paused)
            callTimerMethod(u"Resume"_s);
        else if (!started())
            callTimerMethod(u"Start"_s);
    } else {
        advanceToState(u"pomodoro"_s, true, true);
    }
}

void FocusTimerService::extendSecs(const qint64 secs) {
    callTimerMethodInt64(u"Extend"_s, secs * k_usPerSec);
}

void FocusTimerService::showWindow(const QString& view) {
    if (!m_connected)
        return;
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_appInterface, u"ShowWindow"_s);
    msg << view;
    QDBusConnection::sessionBus().asyncCall(msg);
}

void FocusTimerService::showPreferences(const QString& view) {
    if (!m_connected)
        return;
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_appInterface, u"ShowPreferences"_s);
    msg << view;
    QDBusConnection::sessionBus().asyncCall(msg);
}

void FocusTimerService::disableNativeOverlay() {
    // Turn off Focus Timer's built-in GTK fallback overlay window (the one with the Exit button)
    // so Caelestia's native layer-shell break overlay handles break screens smoothly instead.
    QProcess::startDetached(u"flatpak"_s,
        { u"run"_s, u"--command=gsettings"_s, k_dbusService, u"set"_s, k_dbusService, u"screen-overlay"_s,
            u"false"_s });
}

void FocusTimerService::refresh() {
    if (!m_connected)
        return;
    queryTimerState();
    querySettings();
}

void FocusTimerService::connectDbusSignals() {
    auto bus = QDBusConnection::sessionBus();
    // Use empty service name so Qt D-Bus matches by unique object path + interface even when
    // Focus Timer is launched after the shell has already started.
    bus.connect(QString(), k_dbusPath, k_timerInterface, u"Changed"_s, this, SLOT(onTimerChanged()));
    bus.connect(QString(), k_dbusPath, k_timerInterface, u"Tick"_s, this, SLOT(onTimerTick(qint64)));
    bus.connect(QString(), k_dbusPath, k_sessionInterface, u"Changed"_s, this, SLOT(onSessionChanged()));
    bus.connect(QString(), k_dbusPath, k_sessionInterface, u"ConfirmAdvancement"_s, this,
        SLOT(onConfirmAdvancement(QDBusMessage)));
    bus.connect(QString(), k_dbusPath, k_propsInterface, u"PropertiesChanged"_s, this,
        SLOT(onPropertiesChanged(QDBusMessage)));
}

void FocusTimerService::ensureBackendService() {
    if (m_connected || m_backendLaunchAttempted)
        return;
    m_backendLaunchAttempted = true;
    QProcess::startDetached(
        u"flatpak"_s, { u"run"_s, k_dbusService, u"--gapplication-service"_s });
}

void FocusTimerService::onServiceRegistered(const QString& service) {
    if (service != k_dbusService)
        return;
    m_nativeOverlayDisabledOnce = false;
    m_backendLaunchAttempted = false;
    setConnected(true);
    refresh();
    if (m_startOnConnect) {
        m_startOnConnect = false;
        QTimer::singleShot(150, this, &FocusTimerService::start);
    }
}

void FocusTimerService::onServiceUnregistered(const QString& service) {
    if (service != k_dbusService)
        return;
    m_tickTimer.stop();
    m_nativeOverlayDisabledOnce = false;
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = false;
    m_queryInFlight = false;
    m_queryPending = false;
    m_startedTimeUs = -1;
    m_pausedTimeUs = -1;
    m_finishedTimeUs = -1;
    m_offsetUs = 0;
    setWaitingForInput(false);
    setConnected(false);
    setPaused(false);
    setState(u"stopped"_s);
    setRemainingSecs(m_durationSecs);
    setElapsedSecs(0);
}

void FocusTimerService::onTimerChanged() {
    queryTimerState();
}

void FocusTimerService::onTimerTick(const qint64 timestamp) {
    if (!active() || m_startedTimeUs <= 0) {
        queryTimerState();
        return;
    }
    if (running()) {
        m_tickTimer.start();
        recalculateRemainingFromTimestamps(timestamp);
        if (m_remainingSecs <= 0)
            queryTimerState();
    }
}

void FocusTimerService::onSessionChanged() {
    queryTimerState();
}

void FocusTimerService::onConfirmAdvancement(const QDBusMessage& /*message*/) {
    if (!isBreak())
        emit confirmRequested();
    queryTimerState();
}

void FocusTimerService::onPropertiesChanged(const QDBusMessage& message) {
    const auto args = message.arguments();
    if (args.size() < 2)
        return;
    const QString interface = args.at(0).toString();
    if (interface == k_timerInterface) {
        // Always fetch an atomic GetAll snapshot rather than applying partial PropertiesChanged maps,
        // so State, StartedTime, PausedTime, and FinishedTime are never mixed across phase transitions.
        queryTimerState();
    } else if (interface == k_appInterface) {
        const QVariantMap changed = unwrapDbusMap(args.at(1));
        if (changed.contains(u"Settings"_s))
            querySettings();
    }
}

void FocusTimerService::onLocalTick() {
    if (!running())
        return;
    if (m_startedTimeUs > 0) {
        recalculateRemainingFromTimestamps(0);
        if (m_remainingSecs <= 0)
            queryTimerState();
    } else {
        queryTimerState();
    }
}

void FocusTimerService::queryTimerState() {
    if (!m_connected)
        return;
    if (m_queryInFlight) {
        m_queryPending = true;
        return;
    }
    m_queryInFlight = true;
    m_queryPending = false;
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_propsInterface, u"GetAll"_s);
    msg << k_timerInterface;
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        m_queryInFlight = false;
        const QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isValid())
            applyTimerProps(reply.value());
        if (m_queryPending) {
            m_queryPending = false;
            queryTimerState();
        }
    });
}

void FocusTimerService::querySettings() {
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_propsInterface, u"Get"_s);
    msg << k_appInterface << u"Settings"_s;
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        const QDBusPendingReply<QVariant> reply = *w;
        if (!reply.isValid())
            return;

        const auto settings = unwrapDbusMap(reply.value());
        if (settings.contains(u"pomodoro-duration"_s)) {
            const int pomoSecs = static_cast<int>(std::llround(settings.value(u"pomodoro-duration"_s).toDouble()));
            if (pomoSecs > 0) {
                m_pomodoroDurationSecs = pomoSecs;
                if (!started() || m_waitingForInput || m_durationUs <= 0) {
                    setDurationSecs(pomoSecs);
                    setRemainingSecs(pomoSecs);
                }
            }
        }
        if (settings.contains(u"screen-overlay-reopen-delay"_s)) {
            const int delay = std::max(3, settings.value(u"screen-overlay-reopen-delay"_s).toInt());
            if (m_reopenDelaySecs != delay) {
                m_reopenDelaySecs = delay;
                emit reopenDelaySecsChanged();
            }
        }
        if (settings.contains(u"announce-about-to-end"_s)) {
            const bool announce = settings.value(u"announce-about-to-end"_s).toBool();
            if (m_announceAboutToEnd != announce) {
                m_announceAboutToEnd = announce;
                emit announceAboutToEndChanged();
            }
        }
        if (settings.contains(u"screen-overlay"_s)) {
            const bool overlay = settings.value(u"screen-overlay"_s).toBool();
            if (m_nativeScreenOverlay != overlay) {
                m_nativeScreenOverlay = overlay;
                emit nativeScreenOverlayChanged();
            }
            if (overlay && !m_nativeOverlayDisabledOnce) {
                m_nativeOverlayDisabledOnce = true;
                disableNativeOverlay();
            }
        }
    });
}

void FocusTimerService::callTimerMethod(const QString& method) {
    if (!m_connected)
        return;
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, method);
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        queryTimerState();
    });
}

void FocusTimerService::callTimerMethodInt64(const QString& method, const qint64 arg) {
    if (!m_connected)
        return;
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, method);
    msg << arg;
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        queryTimerState();
    });
}

void FocusTimerService::advanceToState(
    const QString& targetState, const bool startAfter, const bool resetOnFailure) {
    if (!m_connected)
        return;
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = true;
    setWaitingForInput(false);
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_sessionInterface, u"AdvanceToState"_s);
    msg << targetState;
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, startAfter, resetOnFailure](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        if (startAfter) {
            auto startMsg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, u"Start"_s);
            auto* startWatcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(startMsg), this);
            connect(startWatcher, &QDBusPendingCallWatcher::finished, this, [this, resetOnFailure](QDBusPendingCallWatcher* sw) {
                sw->deleteLater();
                auto getMsg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_propsInterface, u"GetAll"_s);
                getMsg << k_timerInterface;
                auto* getWatcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(getMsg), this);
                connect(getWatcher, &QDBusPendingCallWatcher::finished, this, [this, resetOnFailure](QDBusPendingCallWatcher* gw) {
                    gw->deleteLater();
                    const QDBusPendingReply<QVariantMap> reply = *gw;
                    if (reply.isValid())
                        applyTimerProps(reply.value());
                    if (resetOnFailure && !running())
                        resetAndStartPomodoro();
                });
            });
        } else {
            refresh();
        }
    });
}

void FocusTimerService::resetAndStartPomodoro() {
    if (!m_connected)
        return;
    m_wasInRunningBreak = false;
    m_wasInRunningPomodoro = false;
    m_skipRequestedByUser = true;
    setWaitingForInput(false);
    auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, u"Reset"_s);
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        advanceToState(u"pomodoro"_s, true, false);
    });
}

void FocusTimerService::applyTimerProps(const QVariantMap& props) {
    const bool prevActive = active();
    const bool prevRunning = running();
    const bool prevPaused = paused();
    const bool prevIsBreak = isBreak();

    if (props.contains(u"Duration"_s)) {
        const qint64 durUs = props.value(u"Duration"_s).toLongLong();
        m_durationUs = durUs;
        if (durUs > 0)
            setDurationSecs(usToDurationSecs(durUs));
        else if (m_pomodoroDurationSecs > 0)
            setDurationSecs(m_pomodoroDurationSecs);
    }
    if (props.contains(u"Offset"_s))
        m_offsetUs = props.value(u"Offset"_s).toLongLong();
    if (props.contains(u"StartedTime"_s))
        m_startedTimeUs = props.value(u"StartedTime"_s).toLongLong();
    if (props.contains(u"FinishedTime"_s))
        m_finishedTimeUs = props.value(u"FinishedTime"_s).toLongLong();
    if (props.contains(u"State"_s))
        setState(props.value(u"State"_s).toString());
    if (m_state == u"pomodoro"_s && m_durationUs > 0)
        m_pomodoroDurationSecs = usToDurationSecs(m_durationUs);
    if (props.contains(u"PausedTime"_s)) {
        const qint64 pausedUs = props.value(u"PausedTime"_s).toLongLong();
        if (m_pauseForInputInFlight && pausedUs < 0) {
            m_pausedTimeUs = m_startedTimeUs > 0 ? m_startedTimeUs : currentEpochUs();
            setPaused(true);
        } else {
            m_pausedTimeUs = pausedUs;
            setPaused(m_pausedTimeUs >= 0);
        }
    }

    // Evaluate break completion atomically from the full GetAll snapshot:
    // Regardless of whether Focus Timer ends a break by setting FinishedTime > StartedTime,
    // advancing to "pomodoro" (started or unstarted), or transitioning to "stopped",
    // hold in waitingForInput so the Break Overlay hides, the Notch shows "Get ready",
    // and any mouse/keyboard input starts the next Pomodoro.
    const bool breakPhase = (m_state == u"short-break"_s || m_state == u"long-break"_s);
    const bool breakRunning = breakPhase && m_startedTimeUs > 0 && m_finishedTimeUs < 0;
    const bool breakFinishedInPlace = breakPhase
        && m_startedTimeUs > 0
        && m_finishedTimeUs > 0
        && m_finishedTimeUs > m_startedTimeUs;
    const bool breakExitedNaturally = m_wasInRunningBreak && !breakRunning && !m_skipRequestedByUser;
    const bool pomodoroRunning = m_state == u"pomodoro"_s && m_startedTimeUs > 0 && m_finishedTimeUs < 0;
    const bool pomodoroCompletedSession = m_wasInRunningPomodoro && !pomodoroRunning && !breakPhase
        && m_finishedTimeUs > 0 && !m_skipRequestedByUser;

    if (breakRunning) {
        m_wasInRunningBreak = true;
        m_wasInRunningPomodoro = false;
        m_skipRequestedByUser = false;
        setWaitingForInput(false);
    } else if ((breakFinishedInPlace && !m_skipRequestedByUser) || breakExitedNaturally || pomodoroCompletedSession) {
        m_wasInRunningBreak = false;
        m_wasInRunningPomodoro = false;
        setWaitingForInput(true);
        if (m_state == u"pomodoro"_s && m_startedTimeUs > 0 && m_pausedTimeUs < 0 && m_finishedTimeUs < 0
            && !m_pauseForInputInFlight) {
            // Focus Timer auto-started the next Pomodoro; hold it paused until user input arrives.
            m_pauseForInputInFlight = true;
            m_pausedTimeUs = m_startedTimeUs;
            m_paused = true;
            auto msg = QDBusMessage::createMethodCall(k_dbusService, k_dbusPath, k_timerInterface, u"Pause"_s);
            auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
                w->deleteLater();
                m_pauseForInputInFlight = false;
                queryTimerState();
            });
        }
    } else if (pomodoroRunning && m_pausedTimeUs < 0 && !m_waitingForInput) {
        m_wasInRunningPomodoro = true;
        m_skipRequestedByUser = false;
    } else if ((m_state == u"stopped"_s || m_state == u"null"_s) && !m_waitingForInput) {
        m_wasInRunningPomodoro = false;
        m_skipRequestedByUser = false;
    }

    recalculateRemainingFromTimestamps(0);

    if (active() != prevActive || isBreak() != prevIsBreak)
        emit stateChanged();
    if (paused() != prevPaused)
        emit pausedChanged();
    if (running() != prevRunning)
        emit runningChanged();

    updateTickTimer();
}

void FocusTimerService::recalculateRemainingFromTimestamps(const qint64 timestampUs) {
    if (m_waitingForInput) {
        const int targetSecs = m_pomodoroDurationSecs > 0 ? m_pomodoroDurationSecs : m_durationSecs;
        setDurationSecs(targetSecs);
        setRemainingSecs(targetSecs);
        setElapsedSecs(0);
        return;
    }
    if (!started() || m_durationUs <= 0) {
        const int targetSecs = m_durationUs > 0 ? usToDurationSecs(m_durationUs) : m_pomodoroDurationSecs;
        setDurationSecs(targetSecs);
        setRemainingSecs(targetSecs);
        setElapsedSecs(0);
        return;
    }

    // Exact match with ft_timer_state_calculate_elapsed in focus-timer:
    // clamp timestamp to PausedTime and FinishedTime when defined, then subtract StartedTime and Offset.
    qint64 nowUs = timestampUs > 0 ? timestampUs : currentEpochUs();
    if (m_pausedTimeUs >= 0)
        nowUs = std::min(nowUs, m_pausedTimeUs);
    if (m_finishedTimeUs >= 0)
        nowUs = std::min(nowUs, m_finishedTimeUs);

    const qint64 elapsedUs = std::clamp<qint64>(nowUs - m_startedTimeUs - m_offsetUs, 0, m_durationUs);
    const qint64 remUs = m_durationUs - elapsedUs;
    const int remSecs = usToRemainingSecs(remUs, m_durationSecs);
    setRemainingSecs(remSecs);
    setElapsedSecs(std::max(0, m_durationSecs - remSecs));
}

void FocusTimerService::updateTickTimer() {
    // Only run the local fallback timer while actively counting down (never while paused or stopped!)
    if (m_connected && running() && !m_waitingForInput) {
        if (!m_tickTimer.isActive())
            m_tickTimer.start();
    } else {
        m_tickTimer.stop();
    }
}

void FocusTimerService::setConnected(const bool value) {
    if (m_connected == value)
        return;
    m_connected = value;
    emit connectedChanged();
    emit stateChanged();
    emit runningChanged();
    updateTickTimer();
}

void FocusTimerService::setState(const QString& value) {
    const QString normalized = value.isEmpty() ? u"stopped"_s : value;
    if (m_state == normalized)
        return;
    m_state = normalized;
    emit stateChanged();
    emit runningChanged();
    updateTickTimer();
}

void FocusTimerService::setPaused(const bool value) {
    if (m_paused == value)
        return;
    const bool wasPaused = m_paused;
    m_paused = value;
    if (!m_pauseForInputInFlight && wasPaused && !m_paused && m_waitingForInput
        && m_state == u"pomodoro"_s && started() && !finished()) {
        setWaitingForInput(false);
    }
    emit pausedChanged();
    emit runningChanged();
    updateTickTimer();
}

void FocusTimerService::setWaitingForInput(const bool value) {
    if (!value)
        m_pauseForInputInFlight = false;
    if (m_waitingForInput == value)
        return;
    m_waitingForInput = value;
    if (value && m_pomodoroDurationSecs > 0) {
        setDurationSecs(m_pomodoroDurationSecs);
        setRemainingSecs(m_pomodoroDurationSecs);
        setElapsedSecs(0);
    }
    emit waitingForInputChanged();
    emit stateChanged();
    emit pausedChanged();
    emit runningChanged();
    updateTickTimer();
}

void FocusTimerService::setDurationSecs(const int secs) {
    if (m_durationSecs == secs)
        return;
    m_durationSecs = secs;
    emit durationSecsChanged();
    emit remainingSecsChanged();
}

void FocusTimerService::setRemainingSecs(const int secs) {
    const int clamped = std::max(0, secs);
    if (m_remainingSecs == clamped)
        return;
    m_remainingSecs = clamped;
    emit remainingSecsChanged();
}

void FocusTimerService::setElapsedSecs(const int secs) {
    const int clamped = std::max(0, secs);
    if (m_elapsedSecs == clamped)
        return;
    m_elapsedSecs = clamped;
    emit elapsedSecsChanged();
}

} // namespace caelestia::shell::services
