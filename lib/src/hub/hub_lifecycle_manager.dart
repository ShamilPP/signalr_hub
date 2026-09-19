import 'dart:async';

import 'package:flutter/widgets.dart';

import 'hub_connection.dart';
import 'hub_connection_state.dart';

/// Keeps a [HubConnection] healthy across app background and resume.
///
/// Mobile operating systems suspend network activity when an app is
/// backgrounded. The TCP connection is often torn down by the OS or the
/// carrier without the client being told, so the socket still looks open while
/// silently dropping every frame. Nothing surfaces until the server timeout
/// elapses — 30 seconds by default — and in the meantime every `invoke` hangs.
///
/// This manager watches the app lifecycle and, on resume, probes the
/// connection by sending a ping and waiting a short while for any traffic from
/// the server. If nothing arrives, the stale connection is stopped and
/// restarted immediately rather than waiting out the server timeout.
///
/// Attach it once, after the connection is built:
///
/// ```dart
/// final hub = HubConnectionBuilder().withUrl(url).build();
/// final lifecycle = HubLifecycleManager(hub)..attach();
/// await hub.start();
///
/// // When the connection is no longer needed:
/// lifecycle.detach();
/// await hub.stop();
/// ```
///
/// [detach] must be called to remove the observer, otherwise the manager
/// keeps receiving lifecycle events for the life of the app.
class HubLifecycleManager with WidgetsBindingObserver {
  /// The connection this manager watches.
  final HubConnection hubConnection;

  /// How long the resume probe waits for a sign of life from the server.
  ///
  /// Kept short deliberately: the point is to detect a dead socket faster than
  /// `serverTimeoutInMilliseconds` would.
  final Duration probeTimeout;

  /// Whether to close the connection when the app is backgrounded.
  ///
  /// Defaults to `false`, which keeps the connection open and relies on the
  /// resume probe. Set to `true` to release the server's resources while
  /// backgrounded, at the cost of a full reconnect on resume.
  final bool disconnectOnPause;

  bool _attached = false;
  bool _probing = false;
  bool _wasConnectedBeforePause = false;

  HubLifecycleManager(
    this.hubConnection, {
    this.probeTimeout = const Duration(seconds: 2),
    this.disconnectOnPause = false,
  });

  /// Whether this manager is currently observing app lifecycle changes.
  bool get isAttached => _attached;

  /// Starts observing app lifecycle changes.
  ///
  /// Calling this more than once has no additional effect.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops observing app lifecycle changes.
  ///
  /// Safe to call when not attached. Call this before dropping the connection
  /// so the observer is not left registered.
  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _handlePause();
        break;
      case AppLifecycleState.resumed:
        unawaited(_handleResume());
        break;
      case AppLifecycleState.inactive:
        // Transient — a notification shade or an incoming call. The connection
        // is usually still alive, so this is not worth acting on.
        break;
    }
  }

  void _handlePause() {
    _wasConnectedBeforePause =
        hubConnection.state == HubConnectionState.connected;

    if (disconnectOnPause && _wasConnectedBeforePause) {
      unawaited(hubConnection.stop());
    }
  }

  Future<void> _handleResume() async {
    // Overlapping probes would send redundant pings and could stop a
    // connection another probe is already restarting.
    if (_probing) {
      return;
    }
    _probing = true;
    try {
      if (disconnectOnPause) {
        // We closed the connection on pause, so bring it back rather than
        // probing a connection that is known to be gone.
        if (_wasConnectedBeforePause &&
            hubConnection.state == HubConnectionState.disconnected) {
          await _restart();
        }
        return;
      }

      // Only a connection that believes it is healthy can be deceiving us.
      // Any other state has its own recovery path already running.
      if (hubConnection.state != HubConnectionState.connected) {
        return;
      }

      final alive = await hubConnection.probeConnection(timeout: probeTimeout);
      if (alive) {
        return;
      }

      // The socket is open but not carrying traffic. Tear it down so the
      // reconnect policy can take over immediately.
      await hubConnection.stop();
      await _restart();
    } finally {
      _probing = false;
    }
  }

  Future<void> _restart() async {
    try {
      await hubConnection.start();
    } catch (_) {
      // start() reports failures through onclose and the reconnect policy.
      // Rethrowing here would surface as an unhandled async error from a
      // lifecycle callback that nobody is awaiting.
    }
  }
}
