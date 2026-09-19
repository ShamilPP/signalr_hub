import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:signalr_hub/signalr_client.dart';

/// A fake IConnection that never answers invocations unless told to.
class SilentConnection extends IConnection {
  final Completer<void> _startCompleter = Completer<void>();
  final List<Object?> sentMessages = [];
  bool stopCalled = false;

  @override
  Future<void> start({TransferFormat? transferFormat}) {
    return _startCompleter.future;
  }

  void completeStart() => _startCompleter.complete();

  @override
  Future<void> send(Object? data) {
    sentMessages.add(data);
    return Future.value();
  }

  @override
  Future<void>? stop({Object? error}) {
    stopCalled = true;
    onclose?.call(error: error is Exception ? error : null);
    return Future.value();
  }

  void receive(Object data) => onreceive?.call(data);

  /// Decoded JSON of every message sent, excluding the handshake.
  List<Map<String, dynamic>> get sentHubMessages {
    final result = <Map<String, dynamic>>[];
    for (final raw in sentMessages) {
      if (raw is! String) continue;
      for (final part in raw.split('')) {
        if (part.isEmpty) continue;
        final decoded = json.decode(part);
        if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
          result.add(decoded);
        }
      }
    }
    return result;
  }
}

void main() {
  late SilentConnection connection;
  late Logger logger;

  setUp(() {
    connection = SilentConnection();
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

  group('invoke timeout', () {
    test('completes normally when the server responds in time', () async {
      final hub = await connectedHub();

      final future =
          hub.invoke('Echo', args: ['hi'], timeout: const Duration(seconds: 5));

      await Future<void>.delayed(Duration.zero);
      connection.receive('{"type":3,"invocationId":"0","result":"hi"}');

      expect(await future, 'hi');
    });

    test('throws SignalRTimeoutException when the server stays silent',
        () async {
      final hub = await connectedHub();

      final future =
          hub.invoke('Hang', timeout: const Duration(milliseconds: 100));

      await expectLater(
        future,
        throwsA(isA<SignalRTimeoutException>()),
      );
    });

    test('a timed-out invocation keeps the timeout exception type', () async {
      final hub = await connectedHub();

      try {
        await hub.invoke('Hang', timeout: const Duration(milliseconds: 50));
        fail('expected a timeout');
      } on SignalRTimeoutException catch (e) {
        // Existing code branches on `type`, so the enum must still be right.
        expect(e.type, SignalRExceptionType.timeout);
        expect(e.type.isTimeout, isTrue);
      }
    });

    test('sends CancelInvocation to the server on timeout', () async {
      final hub = await connectedHub();

      await hub
          .invoke('Hang', timeout: const Duration(milliseconds: 50))
          .catchError((Object _) => null);

      // Let the unawaited cancel send flush.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final cancels = connection.sentHubMessages
          .where((m) => m['type'] == MessageType.cancelInvocation.index);
      expect(cancels, hasLength(1));
      expect(cancels.first['invocationId'], '0');
    });

    test('waits indefinitely by default', () async {
      final hub = await connectedHub();

      var settled = false;
      unawaited(hub.invoke('Hang').then(
            (_) => settled = true,
            onError: (Object _) => settled = true,
          ));

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(settled, isFalse,
          reason: 'default invocationTimeout is zero (wait forever)');
    });

    test('invocationTimeout applies when no per-call timeout is given',
        () async {
      final hub = await connectedHub();
      hub.invocationTimeout = const Duration(milliseconds: 50);

      await expectLater(
        hub.invoke('Hang'),
        throwsA(isA<SignalRTimeoutException>()),
      );
    });

    test('a per-call timeout overrides invocationTimeout', () async {
      final hub = await connectedHub();
      hub.invocationTimeout = const Duration(milliseconds: 50);

      final future = hub.invoke('Echo', timeout: Duration.zero);

      var settled = false;
      unawaited(future.then(
        (_) => settled = true,
        onError: (Object _) => settled = true,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(settled, isFalse, reason: 'Duration.zero means wait forever');
    });
  });

  group('invoke cancellation', () {
    test('throws SignalRCancelledException when the token is canceled',
        () async {
      final hub = await connectedHub();
      final token = CancellationToken();

      final future = hub.invoke('Hang', cancellationToken: token);
      token.cancel();

      await expectLater(future, throwsA(isA<SignalRCancelledException>()));
    });

    test('sends CancelInvocation to the server on cancel', () async {
      final hub = await connectedHub();
      final token = CancellationToken();

      final future = hub.invoke('Hang', cancellationToken: token);
      token.cancel();
      await future.catchError((Object _) => null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final cancels = connection.sentHubMessages
          .where((m) => m['type'] == MessageType.cancelInvocation.index);
      expect(cancels, hasLength(1));
    });

    test('a token canceled before invoking fails the call immediately',
        () async {
      final hub = await connectedHub();
      final token = CancellationToken()..cancel();

      await expectLater(
        hub.invoke('Hang', cancellationToken: token),
        throwsA(isA<SignalRCancelledException>()),
      );
    });

    test('canceling after the server responded does not overwrite the result',
        () async {
      final hub = await connectedHub();
      final token = CancellationToken();

      final future = hub.invoke('Echo', cancellationToken: token);
      await Future<void>.delayed(Duration.zero);
      connection.receive('{"type":3,"invocationId":"0","result":42}');

      expect(await future, 42);

      // Late cancel must be a no-op rather than an unhandled error.
      token.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('CancellationToken', () {
    test('reports its state', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('cancel is idempotent and fires listeners once', () {
      final token = CancellationToken();
      var calls = 0;
      token.addListener(() => calls++);

      token.cancel();
      token.cancel();

      expect(calls, 1);
    });

    test('a listener added after cancel runs immediately', () {
      final token = CancellationToken()..cancel();
      var called = false;
      token.addListener(() => called = true);
      expect(called, isTrue);
    });

    test('the returned function unregisters the listener', () {
      final token = CancellationToken();
      var called = false;
      final remove = token.addListener(() => called = true);

      remove();
      token.cancel();

      expect(called, isFalse);
    });
  });
}
