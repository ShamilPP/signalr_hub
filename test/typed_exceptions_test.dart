import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_hub/signalr_client.dart';

void main() {
  group('typed exceptions are SignalRException', () {
    // Code written against 2.x catches SignalRException and branches on
    // `type`. Every new subclass must keep working there.
    final cases = <String, SignalRException>{
      'handshake': SignalRHandshakeException(message: 'bad handshake'),
      'timeout': SignalRTimeoutException(message: 'too slow'),
      'auth': SignalRAuthException(message: 'denied', statusCode: 401),
      'transport': SignalRTransportException(message: 'socket died'),
      'cancelled': SignalRCancelledException(message: 'caller gave up'),
    };

    cases.forEach((name, exception) {
      test('$name is catchable as SignalRException', () {
        expect(exception, isA<SignalRException>());
        expect(exception, isA<Exception>());
      });

      test('$name keeps its message', () {
        expect(exception.message, isNotEmpty);
      });

      test('$name serializes for diagnostics', () {
        final json = exception.toJson();
        expect(json['type'], exception.type.name);
        expect(json['message'], exception.message);
      });
    });
  });

  group('exception types map to the existing enum', () {
    test('handshake reports the signalr type', () {
      expect(SignalRHandshakeException(message: 'x').type,
          SignalRExceptionType.signalr);
    });

    test('timeout reports the timeout type', () {
      final e = SignalRTimeoutException(message: 'x');
      expect(e.type, SignalRExceptionType.timeout);
      expect(e.type.isTimeout, isTrue);
    });

    test('auth reports the http type and keeps the status code', () {
      final e = SignalRAuthException(message: 'x', statusCode: 403);
      expect(e.type, SignalRExceptionType.http);
      expect(e.type.isHttp, isTrue);
      expect(e.statusCode, 403);
    });

    test('transport reports the signalr type', () {
      expect(SignalRTransportException(message: 'x').type,
          SignalRExceptionType.signalr);
    });

    test('cancelled reports the abort type', () {
      final e = SignalRCancelledException(message: 'x');
      expect(e.type, SignalRExceptionType.abort);
      expect(e.type.isAbort, isTrue);
    });
  });

  group('subclasses are distinguishable', () {
    test('a timeout is not mistaken for an auth failure', () {
      final Object e = SignalRTimeoutException(message: 'x');
      expect(e, isA<SignalRTimeoutException>());
      expect(e, isNot(isA<SignalRAuthException>()));
    });

    test('a plain SignalRException is not a subclass', () {
      final e = SignalRException(message: 'x');
      expect(e, isNot(isA<SignalRTimeoutException>()));
      expect(e, isNot(isA<SignalRTransportException>()));
    });

    test('original is preserved for wrapped causes', () {
      final cause = FormatException('bad json');
      final e = SignalRHandshakeException(message: 'x', original: cause);
      expect(e.original, same(cause));
    });
  });
}
