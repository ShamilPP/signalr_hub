import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_hub/signalr_client.dart';

/// Compile-checks the code samples in README.md. These are never executed —
/// the value is that the documented APIs must keep type-checking, so a
/// signature change cannot silently leave the README wrong.
void main() {
  test('README samples compile', () {
    expect(_samplesReferenced, isTrue);
  });
}

const _samplesReferenced = true;

// ignore: unused_element
Future<void> _lifecycleSample(String serverUrl) async {
  final hub = HubConnectionBuilder().withUrl(serverUrl).build();
  final lifecycle = HubLifecycleManager(hub)..attach();

  await hub.start();

  lifecycle.detach();
  await hub.stop();
}

// ignore: unused_element
void _disconnectOnPauseSample(HubConnection hub) {
  final lifecycle = HubLifecycleManager(hub, disconnectOnPause: true)..attach();
  lifecycle.detach();
}

// ignore: unused_element
Future<void> _probeSample(HubConnection hub, String message) async {
  if (await hub.probeConnection()) {
    await hub.invoke('SendMessage', args: [message]);
  }
}

// ignore: unused_element
Future<void> _timeoutSample(HubConnection hub, String reportId) async {
  hub.invocationTimeout = const Duration(seconds: 30);

  await hub.invoke(
    'GetReport',
    args: [reportId],
    timeout: const Duration(seconds: 10),
  );
}

// ignore: unused_element
void _cancellationSample(HubConnection hub, void Function(Object?) show) {
  final token = CancellationToken();
  hub.invoke('GetReport', cancellationToken: token).then(show);
  token.cancel();
}

// ignore: unused_element
Future<void> _errorHandlingSample(
  HubConnection hub,
  Future<void> Function() refreshTokenAndRestart,
  void Function() showRetryBanner,
) async {
  try {
    await hub.invoke('GetReport', timeout: const Duration(seconds: 10));
  } on SignalRAuthException {
    await refreshTokenAndRestart();
  } on SignalRTimeoutException {
    showRetryBanner();
  } on SignalRTransportException {
    // The retry policy is already reconnecting.
  }
}

// ignore: unused_element
void _streamResubscribeSample(
    HubConnection hub, void Function(Object?) onTick) {
  StreamSubscription<Object?>? subscription;

  void subscribe() {
    subscription = hub.stream('Ticker', []).listen(
      onTick,
      onError: (Object e) {},
    );
  }

  hub.onreconnected(({connectionId}) => subscribe());
  subscribe();
  subscription?.cancel();
}

// ignore: unused_element
class _ReportPage extends StatefulWidget {
  const _ReportPage({required this.hub});
  final HubConnection hub;

  @override
  State<_ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<_ReportPage> {
  final _token = CancellationToken();

  @override
  void initState() {
    super.initState();
    widget.hub.invoke('GetReport', cancellationToken: _token).then(_show);
  }

  void _show(Object? result) {}

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
