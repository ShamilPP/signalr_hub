## [2.2.0]

Adds app lifecycle handling, invocation timeouts, and a typed exception hierarchy. All changes are backwards compatible: existing code compiles and behaves as before, and the new behaviour is opt-in.

* **App lifecycle handling and fast resume-probe (upstream [#76](https://github.com/sefidgaran/signalr_client/issues/76), [#74](https://github.com/sefidgaran/signalr_client/issues/74), [#44](https://github.com/sefidgaran/signalr_client/issues/44), [#103](https://github.com/sefidgaran/signalr_client/issues/103)):** mobile operating systems suspend network activity when an app is backgrounded, and the OS or carrier often tears down the TCP connection without telling the client. The socket still looks open while silently dropping every frame, so nothing surfaced until `serverTimeoutInMilliseconds` elapsed — 30 seconds by default — and every `invoke()` hung in the meantime. The new `HubLifecycleManager` watches the app lifecycle and, on resume, pings the server and waits about two seconds for any reply. If nothing arrives it stops the stale connection and restarts immediately instead of waiting out the server timeout. Attach it with `HubLifecycleManager(hub)..attach()`, and call `detach()` when the connection is no longer needed. Set `disconnectOnPause: true` to close the connection while backgrounded instead.
* **`HubConnection.probeConnection()`** checks whether the server is still reachable and returns a `bool`, without changing connection state. `HubLifecycleManager` uses it on resume; it is also useful before sending something important after a period of inactivity.
* **Invocation timeouts (upstream [#42](https://github.com/sefidgaran/signalr_client/issues/42), [#34](https://github.com/sefidgaran/signalr_client/issues/34)):** `invoke()` previously created a `Completer` with no timeout, so if the server never sent a completion message the returned `Future` never completed and the entry leaked in the internal callback map. `invoke()` now accepts `timeout:`, and `HubConnection.invocationTimeout` sets a default for every call. On expiry the call fails with `SignalRTimeoutException` and a `CancelInvocation` message is sent so the server stops working on it. **The default is `Duration.zero` (wait indefinitely), preserving existing behaviour** — set `invocationTimeout` to opt in.
* **Cancellation tokens:** `invoke()` accepts a `cancellationToken:`. Calling `cancel()` completes the call with `SignalRCancelledException` and sends `CancelInvocation` to the server, so a request abandoned when a widget is disposed no longer leaves the server doing work nobody is waiting for.
* **Typed exception hierarchy:** added `SignalRHandshakeException`, `SignalRTimeoutException`, `SignalRAuthException`, `SignalRTransportException`, and `SignalRCancelledException`. Each **extends `SignalRException` and keeps the same `type` enum value as before**, so existing `catch (e)` blocks and `e.type` checks are unaffected. This makes it possible to tell a protocol mismatch from an expired token from a dropped socket — previously all three arrived as one generic `SignalRException`.
* **Negotiation now throws `SignalRAuthException` on HTTP 401 and 403,** carrying the status code, so an expired token can be told apart from a genuine negotiation failure.
* **Dropped connections now report `SignalRTransportException` (upstream [#115](https://github.com/sefidgaran/signalr_client/issues/115)):** when the transport drops, pending invocations and streams are failed with this type instead of a generic `SignalRException`. A stream cannot survive a reconnect — the server keeps no record of it across connections — so callers need to tell "the connection dropped, resubscribe" apart from a server-reported error. Resubscribing is left to the caller because replaying automatically could repeat side effects the server already performed; `HubConnection.stream` documents the `onreconnected` pattern.

## [2.1.1]

* **Fixed isolate freeze when sending large binary payloads:** `WebSocketTransport.send()` formatted the entire outgoing payload into a FINEST log line on every send. Because Dart evaluates string interpolation before the logger checks its level, this ran even when logging was disabled. For `Uint8List` payloads it called `formatArrayBuffer()`, which concatenated with `str +=` -- O(n^2). A 400 KB buffer blocked the isolate for roughly 56 seconds, and a 1.2 MB image (for example, one sent via MessagePack) hung it indefinitely: the UI froze and the future returned by `invoke()` never completed. Thanks to [@yjkt](https://github.com/yjkt) for the report and fix (#3).
* **Outgoing message content is no longer logged when `logMessageContent` is `false`.** The send path passed `true` unconditionally, so outgoing string payloads were written to logs regardless of the configured setting, leaking any tokens or personal data carried in invocation arguments. The send path now mirrors the receive path's `_logMessageContent && data is String` condition.
* **`formatArrayBuffer()` rewritten with `StringBuffer`** (O(n) instead of O(n^2)), so no remaining call site can stall the isolate on a large buffer. Output is byte-identical to the previous implementation.
* **Negotiation errors are now thrown rather than returned as `Future.error` from inside a `try` block.** This satisfies the new `unawaited_return_in_try_block` diagnostic in recent Dart SDKs, which was failing CI. Callers receive the same `SignalRException` as before; the failure is now also logged by the existing negotiation error handler.

## [2.1.0]

* **Client Results Support (upstream issue #118):** A client handler registered with `on()` can now return a value — or a `Future` — and it is sent back to the server as a `CompletionMessage`. This is the SignalR "client results" feature, used when the server calls `InvokeAsync<T>` on a client and awaits the answer. Previously the client logged *"not supported in this version"* and **terminated the connection** whenever the server requested a response. Thanks to [@JamesFieldist](https://github.com/JamesFieldist) for the implementation (#2).
* **`MethodInvocationFunc` now returns `dynamic`** instead of `void`, so handlers may return a result. Existing `void` handlers keep compiling unchanged.
* **Error results:** If a handler throws, or no handler is registered for the requested target, an error `CompletionMessage` is returned to the server so it stops waiting instead of hanging until its own timeout.
* **Serialization fix:** Client-result completions are now written through the active hub protocol. They were previously handed to the transport as raw message objects, which every transport rejects with *"Content type is not handled."* — this made client results fail on any real connection.
* **Multiple handlers:** When several handlers are registered for one target and the server expects a result, all handlers still run, the first one's return value answers the server, and a warning is logged instead of silently discarding the rest.
* **Handler-list safety:** Handlers are invoked over a copy of the list, so a handler calling `on()` / `off()` for its own target no longer risks a concurrent-modification error.
* **CI:** Added a GitHub Actions workflow running `flutter analyze` and `flutter test` on every push and pull request.

## [2.0.2]

* **Documentation Fixes:** Updated README to correctly reference the new `ShamilPP/SignalR_HUB` repository paths, removed outdated version notices, and fixed Dart syntax errors in the documentation examples.

## [2.0.1]

* **Reduced Package Size:** Excluded internal test sandbox (`testapp/`), build artifacts, and coverage data from the published package, significantly reducing download size.
* **Strict Static Analysis Passed:** Fixed 49 strict static analysis warnings generated by `flutter analyze` internally. The package maintains a flawless 160/160 score on pub.dev.

## [2.0.0]

* Rebuilt and modernized fork of `signalr_netcore`.
* Renamed package to `signalr_hub`.
* Fixed Handshake Null-Crash (Issue #110).
* Fixed Web Stop Crash when backend disconnects (Issue #124).
* Fixed Web URL formatting for Query Parameters (Issue #119).
* Stabilized Auto-Reconnect loop to respect Retry Policy delay.
* Added `webSocketChannelFactory` to support self-signed certificates and custom proxies (Issue #113).
* Fixed Invalid HTTP Header formatting for authorization tokens.
* Complete lint warning cleanup and code modernization.

## [1.4.4]

* Adds message headers to the web socket transport

## [1.4.3]  

* Fixed WebSocket authorization issue on Web platform.

## [1.4.2]

* Added support for client-to-server streaming with controllable stream lifecycle via StreamController, enabling client-side abortion of streams. Preserved existing stream() method for backward compatibility.

## [1.4.1]

* Add back web support that was removed previously in #93
  * Websocket on browser doesn't support passing headers, instead the token must be passed via query string in the url

## [1.4.0]

* Fix websocket auth issues

## [1.3.9]

* Improve code quality

## [1.3.8]

* Upgrade sse_channel library to version 0.1.1

## [1.3.7]

* Update dependencies using http: ^1.1.0
  
## [1.3.6]

* Emit events once the HubConnectionState changes

## [1.3.5]

* Upgrade packages and remove warnings
  
## [1.3.4]

* Fix the disconnect exception caused by send message error
  
## [1.3.3]

* Allowing invocation arguments to be null

## [1.3.2]

* Fix broken authorization in SSE (Server Side Events) transport

## [1.3.1]

* Add MessagePack with WEB support.

## [1.3.0]

* Add Msgpack support and added some tests.
* Migrate examples to ASP NET core 6

## [1.2.6]

* Add Timeout option for requests to resolve unexpected Timeout Exceptions  

## [1.2.5]

* Migrate examples to Android embedding v2

## [1.2.4+1]

* Fix formatting issues

## [1.2.4]

* Update readme
* Exposes default MessageHeaders for HttpRequests
* Remove warnings

## [1.2.3+1]

* Update readme

## [1.2.3]

* Fix on error calling onReceive, error: type 'List' is not a subtype of type 'List?'
* Fix an error when CompletionMessage doesn't have error and returns null on result property.

## [1.2.2]

* Bug fix

## [1.2.1+1]

* Fix all flutter formatting issues

## [1.2.1]

* Fix formatting issues

## [1.2.0]

* Null safety migration

## [1.1.1]

* Fix pub.dev evaluation result for native support

## [1.1.0]

* Add support for web
* Bug fixes

## [1.0.1]

* Upgrade packages

## [1.0.0]

* Upgrade to Flutter 2

## [0.1.8+2]

* Dart format files

## [0.1.8+1]

* Move chat client files to example folder
* Add dispose to chat client example view
* Re-format (dart) files

## [0.1.8]

* Align codebase with AspNetCore 3.1 Typescript client codebase, including support for auto-reconnect

## [0.1.7+1]

* Minor changes

## [0.1.7]

* Fix the exception for: Response Content-Type not supported: [application/json; charset=UTF-8]

## [0.1.6]

* Merged pull request "Prepare for Uint8List SDK breaking change"

## [0.1.5]

* Fix complex object serialization to json.

## [0.1.4]

* Prevent null exception when calling HubConnection.stop()

## [0.1.3]

* Change the logging behaviour: The client uses the dart standard [logging](https://pub.dartlang.org/packages/logging) package instead of a proprietary logging behaviour (see readme for an example).
* Fixes a bug within the MessageHeaders class.

## [0.1.2]

* Be more descriptional within the desciption of the pubspec.yaml

## [0.1.1]

* Be more descriptional within the desciption of the pubspec.yaml

## [0.1.0]

* Chat client/server example added.
* Reformat Library code to compile to PUB spec.
* Added some more description to the readme.

## [0.0.1]

* Intitial Version
