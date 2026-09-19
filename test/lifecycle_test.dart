import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:signalr_hub/signalr_client.dart';

/// A fake IConnection whose responsiveness can be switched off to simulate a
/// socket that stays open but no longer carries traffic.
class ProbeableConnection extends IConnection {
  Completer<void> _startCompleter = Completer<void>();
  final List<Object?> sentMessages = [];
  int stopCount = 0;
  int startCount = 0;

  /// When true, the server answers a client ping with a ping of its own.
  bool respondToPing = true;

  @override
  Future<void> start({TransferFormat? transferFormat}) {
    startCount++;
    return _startCompleter.future;
  }

  void completeStart() {
    if (!_startCompleter.isCompleted) _startCompleter.complete();
  }

  /// Prepares the fake for a fresh start() after a stop().
  void resetForRestart() => _startCompleter = Completer<void>();

  @override
  Future<void> send(Object? data) {
    sentMessages.add(data);
    // A ping from the client draws a ping back, the way a live server behaves.
    if (respondToPing && data is String && data.contains('"type":6')) {
      scheduleMicrotask(() => onreceive?.call('{"type":6}'));
    }
    return Future.value();
  }

  @override
  Future<void>? stop({Object? error}) {
    stopCount++;
    onclose?.call(error: error is Exception ? error : null);
    return Future.value();
  }

  void receive(Object data) => onreceive?.call(data);
}

void main() {
  // The lifecycle manager talks to WidgetsBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProbeableConnection connection;
  late Logger logger;

  setUp(() {
    connection = ProbeableConnection();
    logger = Logger.detached('test')..level = Level.OFF;
  });

  Future<HubConnection> connectedHub() async {
    final hub = HubConnection.create(connection, logger, JsonHubProtocol());
    final startFuture = hub.start();
    connection.completeStart();
    await Future<void>.delayed(Duration.zero);
    connection.receive('{}');
    await startFuture;
    return hub;
  }

  group('probeConnection', () {
    test('returns true when the server answers', () async {
      final hub = await connectedHub();

      final alive =
          await hub.probeConnection(timeout: const Duration(seconds: 1));

      expect(alive, isTrue);
    });

    test('returns false when the server is silent', () async {
      final hub = await connectedHub();
      connection.respondToPing = false;

      final alive =
          await hub.probeConnection(timeout: const Duration(milliseconds: 300));

      expect(alive, isFalse);
    });

    test('returns false when not connected', () async {
      final hub = HubConnection.create(connection, logger, JsonHubProtocol());

      expect(hub.state, HubConnectionState.disconnected);
      expect(await hub.probeConnection(), isFalse);
    });

    test('resolves quickly rather than waiting out the server timeout',
        () async {
      final hub = await connectedHub();
      connection.respondToPing = false;

      final watch = Stopwatch()..start();
      await hub.probeConnection(timeout: const Duration(milliseconds: 200));
      watch.stop();

      // The point of the probe: far below serverTimeoutInMilliseconds (30s).
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('does not change the connection state on failure', () async {
      final hub = await connectedHub();
      connection.respondToPing = false;

      await hub.probeConnection(timeout: const Duration(milliseconds: 200));

      expect(hub.state, HubConnectionState.connected);
      expect(connection.stopCount, 0);
    });
  });

  group('HubLifecycleManager', () {
    test('attach and detach are idempotent', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub);

      expect(manager.isAttached, isFalse);
      manager.attach();
      manager.attach();
      expect(manager.isAttached, isTrue);
      manager.detach();
      manager.detach();
      expect(manager.isAttached, isFalse);
    });

    test('a live connection survives resume untouched', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub,
          probeTimeout: const Duration(milliseconds: 300))
        ..attach();
      addTearDown(manager.detach);

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(hub.state, HubConnectionState.connected);
      expect(connection.stopCount, 0,
          reason: 'a responsive connection must not be torn down');
    });

    test('a dead connection is restarted on resume', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub,
          probeTimeout: const Duration(milliseconds: 200))
        ..attach();
      addTearDown(manager.detach);

      // The OS silently dropped the socket while backgrounded.
      connection.respondToPing = false;
      connection.resetForRestart();

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Let the probe fail, then the restart begin.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(connection.stopCount, greaterThan(0),
          reason: 'the stale socket should be torn down');
      expect(connection.startCount, greaterThan(1),
          reason: 'a fresh connection should be started');
    });

    test('inactive is ignored', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub)..attach();
      addTearDown(manager.detach);

      connection.respondToPing = false;
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(connection.stopCount, 0,
          reason: 'inactive is transient and must not trigger a probe');
    });

    test('disconnectOnPause stops the connection when backgrounded', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub, disconnectOnPause: true)
        ..attach();
      addTearDown(manager.detach);

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(connection.stopCount, greaterThan(0));
    });

    test('disconnectOnPause reconnects on resume', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub, disconnectOnPause: true)
        ..attach();
      addTearDown(manager.detach);

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      connection.resetForRestart();
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(connection.startCount, greaterThan(1));
    });

    test('does not probe a connection that is already disconnected', () async {
      final hub = await connectedHub();
      final manager = HubLifecycleManager(hub)..attach();
      addTearDown(manager.detach);

      await hub.stop();
      final stopsAfterExplicitStop = connection.stopCount;

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(connection.stopCount, stopsAfterExplicitStop,
          reason: 'a disconnected hub has its own recovery path');
    });
  });

  group('streams on disconnect', () {
    test('a stream ends with SignalRTransportException when the socket drops',
        () async {
      final hub = await connectedHub();

      Object? receivedError;
      final done = Completer<void>();
      hub.stream('Ticker', []).listen(
        (_) {},
        onError: (Object e) {
          receivedError = e;
          if (!done.isCompleted) done.complete();
        },
      );

      await Future<void>.delayed(Duration.zero);
      // The transport drops without the server completing the stream.
      connection.stop();
      await done.future.timeout(const Duration(seconds: 1));

      // Callers need to tell this apart from a server-reported stream error
      // so they know to resubscribe rather than surface a failure.
      expect(receivedError, isA<SignalRTransportException>());
    });

    test('a pending invoke fails with SignalRTransportException on drop',
        () async {
      final hub = await connectedHub();

      final future = hub.invoke('Slow');
      await Future<void>.delayed(Duration.zero);
      connection.stop();

      await expectLater(future, throwsA(isA<SignalRTransportException>()));
    });
  });
}
