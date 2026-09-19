# signalr_hub

[![pub package](https://img.shields.io/pub/v/signalr_hub.svg)](https://pub.dartlang.org/packages/signalr_hub)

A Flutter SignalR Client for [ASP.NET Core](https://docs.microsoft.com/aspnet/core/signalr).  
ASP.NET Core SignalR is an open-source library that simplifies adding real-time web functionality to apps. Real-time web functionality enables server-side code to push content to clients instantly.

Tested with ASP.NET Core 3.1 & ASP .NET Core 6

The client is able to invoke server side hub functions (including streaming functions) and to receive method invocations issued by the server. It also supports the auto-reconnect feature.

The client supports the following transport protocols:

- WebSocket
- Server-Sent Events
- Long Polling

The client supports the following hub protocols:

- Json
- MessagePack

## Examples

Both samples in this repository include the ASP.NET Core hub they connect to, so each one runs end to end.

**[Real-time chat](https://github.com/ShamilPP/SignalR_HUB/tree/main/example)** — a chat application pairing a Flutter client with a minimal ASP.NET Core hub. It covers the everyday path: building and starting a connection, sending messages to the hub, and handling messages the server pushes back.

**[Hub invocation reference](https://github.com/ShamilPP/SignalR_HUB/tree/main/samples/client)** — every hub-invocation shape, exercised in isolation: methods with no parameters, with simple parameters, and with complex parameters; each with and without a return value; invocations in both directions, client-to-server and server-to-client; and streaming requests. Useful when you need to see exactly how one specific call pattern is wired.

## Getting Started

Add `signalr_hub` to your `pubspec.yaml` dependencies:

```yaml

...
dependencies:
  flutter:
    sdk: flutter

  signalr_hub:
...
```

Important Note: This is the official modernized version of `signalr_client` rebuilt for modern Flutter environments. It enforces strict type safety and guarantees auto-reconnect stability.

## Usage

Let's demo some basic usages:

#### 1. Create a hub connection

```dart
// Import the library.
import 'package:signalr_hub/signalr_client.dart';

// The location of the SignalR Server.
final serverUrl = "192.168.10.50:51001";
// Creates the connection by using the HubConnectionBuilder.
final hubConnection = HubConnectionBuilder().withUrl(serverUrl).build();
// When the connection is closed, print out a message to the console.
hubConnection.onclose( (error) => print("Connection Closed"));

```

Logging is supported via the dart [logging package](https://pub.dartlang.org/packages/logging):

```dart
// Import theses libraries.
import 'package:logging/logging.dart';
import 'package:signalr_hub/signalr_client.dart';

// Configer the logging
Logger.root.level = Level.ALL;
// Writes the log messages to the console
Logger.root.onRecord.listen((LogRecord rec) {
  print('${rec.level.name}: ${rec.time}: ${rec.message}');
});

// If you want only to log out the message for the higer level hub protocol:
final hubProtLogger = Logger("SignalR - hub");
// If youn want to also to log out transport messages:
final transportProtLogger = Logger("SignalR - transport");

// The location of the SignalR Server.
final serverUrl = "192.168.10.50:51001";
final connectionOptions = HttpConnectionOptions
final httpOptions = new HttpConnectionOptions(logger: transportProtLogger);
//final httpOptions = new HttpConnectionOptions(logger: transportProtLogger, transport: HttpTransportType.webSockets); // default transport type.
//final httpOptions = new HttpConnectionOptions(logger: transportProtLogger, transport: HttpTransportType.serverSentEvents);
//final httpOptions = new HttpConnectionOptions(logger: transportProtLogger, transport: HttpTransportType.longPolling);

// If you need to authorize the Hub connection than provide a an async callback function that returns
// the token string (see AccessTokenFactory typdef) and assigned it to the accessTokenFactory parameter:
// final httpOptions = new HttpConnectionOptions( .... accessTokenFactory: () async => await getAccessToken() );

// Creates the connection by using the HubConnectionBuilder.
final hubConnection = HubConnectionBuilder().withUrl(serverUrl, options: httpOptions).configureLogging(hubProtLogger).build();
// When the connection is closed, print out a message to the console.
hubConnection.onclose( (error) => print("Connection Closed"));

```

#### 2. Connect to a Hub

Calling following method starts handshaking and connects the client to SignalR server

```c
await hubConnection.start();
```

#### 3. Calling a Hub function

Assuming there is this hub function:

```c
public string MethodOneSimpleParameterSimpleReturnValue(string p1)
{
  Console.WriteLine($"'MethodOneSimpleParameterSimpleReturnValue' invoked. Parameter value: '{p1}");
  return p1;
}
```

The client can invoke the function by using:

```dart

  final result = await hubConnection.invoke("MethodOneSimpleParameterSimpleReturnValue", args: <Object>["ParameterValue"]);
  logger.log(LogLevel.Information, "Result: '$result");

```

#### 4. Calling a client function

Assuming the server calls a function "aClientProvidedFunction":

```c
  await Clients.Caller.SendAsync("aClientProvidedFunction", null);
```

The Client provides the function like this:

```dart

  hubConnection.on("aClientProvidedFunction", _handleAClientProvidedFunction);

  // To unregister the function use:
  // a) to unregister a specific implementation:
  // hubConnection.off("aClientProvidedFunction", method: _handleServerInvokeMethodNoParametersNoReturnValue);
  // b) to unregister all implementations:
  // hubConnection.off("aClientProvidedFunction");
  ...
  void _handleAClientProvidedFunction(List<Object> parameters) {
    logger.log(LogLevel.Information, "Server invoked the method");
  }

```

Client handlers can also return a result back to the server. If the server uses `InvokeAsync` (which expects a response), a handler may return a value or an async `Future`:

```dart
hubConnection.on("aClientProvidedFunctionWithResult", (parameters) async {
  await Future.delayed(Duration(seconds: 1));
  return "This is the result from the client!";
});
```

A few things worth knowing about client results:

- If your handler throws, the exception message is returned to the server as an error result, so the server's `InvokeAsync` fails instead of hanging until its own timeout.
- If the server invokes a method you never registered, an error result is returned for the same reason.
- If you register several handlers for the same method name, all of them still run, but only the first one's return value is sent to the server (a warning is logged). The server can only accept a single result.
- Handlers registered for methods the server calls with `SendAsync` (no response expected) work exactly as before — any value they return is simply ignored.

#### 5. Using Msgpack for serialization

The Hub should be configured to use the msgpack protocol in both the client and server

### Client

```dart
import 'package:signalr_hub/msgpack_hub_protocol.dart';
_hubConnection = HubConnectionBuilder()
          .withUrl(_serverUrl, options: httpOptions)
          /* Configure the Hub with msgpack protocol */
          .withHubProtocol(MessagePackHubProtocol())
          .withAutomaticReconnect()
          .configureLogging(logger)
          .build();
```

### Server

Add the following packge to your ASP NET core project
`Microsoft.AspNetCore.SignalR.Protocols.MessagePack`

```csharp
public void ConfigureServices(IServiceCollection services)
        {
            // Configure the hub to use msgpack protocol
            services.AddSignalR().AddMessagePackProtocol();

        }
```

### A note about the parameter types

All function parameters and return values are serialized/deserialized into/from JSON by using the dart:convert package (json.endcode/json.decode). Make sure that you:

- use only simple parameter types

or

- use objects that implements toJson() since that method is used by the dart:convert package to serialize an object.

Flutter Json 101:

- [flutter.io](https://flutter.io/json/)
- [json.encode](https://api.dartlang.org/stable/2.0.0/dart-convert/JsonCodec/encode.html)
- [json.decode](https://api.dartlang.org/stable/2.0.0/dart-convert/JsonCodec/decode.html)

#### MSGPACK

All function parameters and return values are serialized/deserialized into/from Msgpack by using the [msgpack_dart](https://pub.dev/packages/msgpack_dart) package. Make sure that you:

- use only simple parameter types
  or
- Convert your classes to maps using Json encode/decode and then pass it to msgpack
  or
- Serialize the message into bytes using msgpack_dart using custom encoders and decoders before passing it to signalr

#### [Msgpack - It's like JSON but fast and small.](https://msgpack.org/index.html)

### How to expose a MessageHeaders object so the client can send default headers

Code Example:

```dart
final defaultHeaders = MessageHeaders();
defaultHeaders.setHeaderValue("HEADER_MOCK_1", "HEADER_VALUE_1");
defaultHeaders.setHeaderValue("HEADER_MOCK_2", "HEADER_VALUE_2");

final httpConnectionOptions = new HttpConnectionOptions(
          httpClient: WebSupportingHttpClient(logger,
              httpClientCreateCallback: _httpClientCreateCallback),
          accessTokenFactory: () => Future.value('JWT_TOKEN'),
          logger: logger,
          logMessageContent: true,
          headers: defaultHeaders);

final _hubConnection = HubConnectionBuilder()
          .withUrl(_serverUrl, options: httpConnectionOptions)
          .withAutomaticReconnect(retryDelays: [2000, 5000, 10000, 20000, null])
          .configureLogging(logger)
          .build();
```

Http Request Log:

```text
I/flutter ( 5248): Starting connection with transfer format 'TransferFormat.text'.
I/flutter ( 5248): Sending negotiation request: https://localhost:5000/negotiate?negotiateVersion=1
I/flutter ( 5248): HTTP send: url 'https://localhost:5000/negotiate?negotiateVersion=1', method: 'POST' content: '' content length = '0'
headers: '{ content-type: text/plain;charset=UTF-8 }, { HEADER_MOCK_1: HEADER_VALUE_1 }, { X-Requested-With: FlutterHttpClient }, { HEADER_MOCK_2: HEADER_VALUE_2 }, { Authorization: Bearer JWT_TOKEN }'
```

## Mobile app lifecycle

When a mobile app is backgrounded, the OS or the carrier usually tears down the TCP connection without telling the client. The socket still looks open while silently dropping every frame, so a resumed app appears connected but nothing works — and nothing surfaces until the 30-second server timeout expires.

`HubLifecycleManager` handles this. On resume it pings the server and waits about two seconds for any reply. If nothing comes back, it stops the stale connection and restarts it immediately instead of waiting out the timeout.

```dart
final hub = HubConnectionBuilder().withUrl(serverUrl).build();
final lifecycle = HubLifecycleManager(hub)..attach();

await hub.start();

// When the connection is no longer needed:
lifecycle.detach();
await hub.stop();
```

`detach()` must be called, otherwise the observer stays registered for the life of the app. In a `StatefulWidget`, attach in `initState` and detach in `dispose`.

To release the server's resources while backgrounded instead, at the cost of a full reconnect on resume:

```dart
final lifecycle = HubLifecycleManager(hub, disconnectOnPause: true)..attach();
```

You can also probe the connection yourself. This changes no state; it just reports whether the server is reachable:

```dart
if (await hub.probeConnection()) {
  await hub.invoke('SendMessage', args: [message]);
}
```

## Invocation timeouts and cancellation

By default `invoke()` waits indefinitely for the server's reply. If the server stops responding, the `Future` never completes. Set a timeout to fail instead of hanging:

```dart
// Applies to every invoke on this connection.
hub.invocationTimeout = const Duration(seconds: 30);

// Or per call.
final result = await hub.invoke(
  'GetReport',
  args: [reportId],
  timeout: const Duration(seconds: 10),
);
```

On expiry the call throws `SignalRTimeoutException`, and a `CancelInvocation` message is sent so the server stops working on it.

The default remains `Duration.zero` (wait indefinitely) so upgrading changes nothing until you opt in.

To abandon a request whose result is no longer needed — a screen the user has left, for example — pass a `CancellationToken`:

```dart
class _ReportPageState extends State<ReportPage> {
  final _token = CancellationToken();

  @override
  void initState() {
    super.initState();
    hub.invoke('GetReport', cancellationToken: _token).then(_show);
  }

  @override
  void dispose() {
    _token.cancel(); // tells the server to stop too
    super.dispose();
  }
}
```

The call then throws `SignalRCancelledException`. A token is single-use — create one per invocation.

## Error handling

All exceptions extend `SignalRException`, so existing `catch` blocks keep working. The subclasses let you tell failures apart:

| Exception | Means |
| --- | --- |
| `SignalRHandshakeException` | The server rejected the protocol handshake — usually a protocol mismatch, such as MessagePack not registered server-side. |
| `SignalRAuthException` | Negotiation was rejected with HTTP 401 or 403. Check the token from `accessTokenFactory`; `statusCode` carries the status. |
| `SignalRTimeoutException` | An invocation or the server timeout elapsed. |
| `SignalRTransportException` | The underlying socket failed, or dropped while calls were pending. |
| `SignalRCancelledException` | A `CancellationToken` was canceled. |

```dart
try {
  await hub.invoke('GetReport', timeout: const Duration(seconds: 10));
} on SignalRAuthException {
  await refreshTokenAndRestart();
} on SignalRTimeoutException {
  showRetryBanner();
} on SignalRTransportException {
  // The connection dropped; the retry policy is already reconnecting.
}
```

### Streams and reconnects

A stream does not survive a reconnect: the server keeps no record of it across connections. When the transport drops, the stream ends with a `SignalRTransportException` and must be requested again. This is not done automatically, because replaying a stream could repeat side effects the server already performed.

```dart
StreamSubscription<Object?>? subscription;

void subscribe() {
  subscription = hub.stream('Ticker', []).listen(
    onTick,
    onError: (e) {
      // SignalRTransportException means the connection dropped;
      // onreconnected below will resubscribe.
    },
  );
}

hub.onreconnected(({connectionId}) => subscribe());
subscribe();
```

## Server Configuration (CORS & Proxies)

If you are using a proxy (like NGINX or Apache) or your Flutter web client connects from a different domain, you must enable CORS and configure proxy settings on your ASP.NET Core backend.

```csharp
services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyHeader()
               .AllowAnyMethod()
               .SetIsOriginAllowed((host) => true)
               .AllowCredentials();
    });
});
// And in Configure:
app.UseCors("AllowAll");
```

## Android Release Mode

If you are compiling your app in Release mode for Android and experience connection failures (e.g. timeout or negotiation errors), ensure that you have the `INTERNET` permission in your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for SignalR to connect to the server -->
    <uses-permission android:name="android.permission.INTERNET" />
    ...
</manifest>
```
