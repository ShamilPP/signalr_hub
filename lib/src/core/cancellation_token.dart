/// Cancels a pending [HubConnection.invoke] call.
///
/// Pass a token to `invoke` and call [cancel] to give up waiting. The client
/// sends a `CancelInvocation` message so the server can stop work on its side,
/// and the `Future` returned by `invoke` completes with a
/// [SignalRCancelledException].
///
/// A typical use is abandoning a request when a widget leaves the tree:
///
/// ```dart
/// class _ReportPageState extends State<ReportPage> {
///   final _token = CancellationToken();
///
///   @override
///   void initState() {
///     super.initState();
///     hub.invoke('GetReport', cancellationToken: _token).then(_show);
///   }
///
///   @override
///   void dispose() {
///     _token.cancel();
///     super.dispose();
///   }
/// }
/// ```
///
/// A token is single-use: once canceled it stays canceled, and calling
/// [cancel] again does nothing. Create a new token per invocation.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// Cancels the token and notifies any pending invocation using it.
  ///
  /// Safe to call more than once, and safe to call when no invocation is
  /// using the token. Both are no-ops.
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;

    // Copy first: a listener may remove itself while we iterate.
    final listeners = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Registers [listener] to run when the token is canceled.
  ///
  /// If the token is already canceled, [listener] runs immediately. Returns a
  /// function that unregisters the listener, which callers use to avoid
  /// leaking listeners when a long-lived token outlives the invocation.
  ///
  /// This is internal plumbing for `invoke`; application code should not need
  /// it.
  void Function() addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
