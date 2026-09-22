import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_hub/signalr_client.dart';

void main() {
  test('HttpConnectionOptions equality still works', () {
    final a =
        HttpConnectionOptions(skipNegotiation: true, requestTimeout: 5000);
    final b =
        HttpConnectionOptions(skipNegotiation: true, requestTimeout: 5000);
    final c =
        HttpConnectionOptions(skipNegotiation: false, requestTimeout: 5000);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('copyWith preserves equality semantics', () {
    final a = HttpConnectionOptions(requestTimeout: 1000);
    expect(a.copyWith(requestTimeout: 1000), equals(a));
    expect(a.copyWith(requestTimeout: 2000), isNot(equals(a)));
  });

  test('AvailableTransport equality still works', () {
    const a = AvailableTransport(transport: HttpTransportType.webSockets);
    const b = AvailableTransport(transport: HttpTransportType.webSockets);
    const c = AvailableTransport(transport: HttpTransportType.longPolling);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });

  test('AvailableTransport compares transferFormats', () {
    const a = AvailableTransport(
        transport: HttpTransportType.webSockets,
        transferFormats: [TransferFormat.text]);
    const b = AvailableTransport(
        transport: HttpTransportType.webSockets,
        transferFormats: [TransferFormat.binary]);
    expect(a, isNot(equals(b)));
  });
}
