import 'package:flutter/foundation.dart';

enum ExceptionType {
  dartException,
  jsInteropObject,
  unknown;

  static ExceptionType exceptionType(Object? error) {
    if (error is Exception || error is Error) {
      return ExceptionType.dartException;
    } else if (kIsWeb) {
      return ExceptionType.jsInteropObject;
    } else {
      return ExceptionType.unknown;
    }
  }
}

enum SignalRExceptionType {
  http,
  abort,
  timeout,
  notImplemented,
  invalidPayload,
  signalr,
  unknown;

  bool get isSignalr => this == SignalRExceptionType.signalr;
  bool get isHttp => this == SignalRExceptionType.http;
  bool get isAbort => this == SignalRExceptionType.abort;
  bool get isTimeout => this == SignalRExceptionType.timeout;
  bool get isNotImplemented => this == SignalRExceptionType.notImplemented;
  bool get isInvalidPayload => this == SignalRExceptionType.invalidPayload;
  bool get isUnknown => this == SignalRExceptionType.unknown;
}

class SignalRException implements Exception {
  final String message;
  final Object? original;
  final int? statusCode;
  final StackTrace? stackTrace;
  final SignalRExceptionType type;
  SignalRException(
      {required this.message,
      this.original,
      this.stackTrace,
      this.statusCode,
      this.type = SignalRExceptionType.unknown});

  static SignalRException handler({
    int statusCode = 0,
    required Object? error,
    required String message,
    required SignalRExceptionType type,
    required StackTrace? stackTrace,
  }) {
    final exceptionType = ExceptionType.exceptionType(error);
    switch (exceptionType) {
      case ExceptionType.dartException:
        return SignalRException(
          type: type,
          original: error,
          message: message,
          stackTrace: stackTrace,
          statusCode: statusCode,
        );
      case ExceptionType.jsInteropObject:
        return SignalRException(
          type: type,
          stackTrace: stackTrace,
          statusCode: statusCode,
          original: Exception(error.toString()),
          message: "JAVASCRIPT ERROR TYPE: ${error.runtimeType}",
        );
      case ExceptionType.unknown:
        return SignalRException(
          type: type,
          original: error,
          statusCode: statusCode,
          stackTrace: stackTrace,
          message: "UNKNOWN ERROR TYPE: ${error.runtimeType}",
        );
    }
  }

  static SignalRException? tryHandler({
    int statusCode = 0,
    required Object? error,
    required String message,
    required SignalRExceptionType type,
    required StackTrace? stackTrace,
  }) {
    if (error != null) {
      final exceptionType = ExceptionType.exceptionType(error);
      switch (exceptionType) {
        case ExceptionType.dartException:
          return SignalRException(
            type: type,
            original: error,
            message: message,
            stackTrace: stackTrace,
            statusCode: statusCode,
          );
        case ExceptionType.jsInteropObject:
          return SignalRException(
            type: type,
            stackTrace: stackTrace,
            statusCode: statusCode,
            original: Exception(error.toString()),
            message: "JAVASCRIPT ERROR TYPE: ${error.runtimeType}",
          );
        case ExceptionType.unknown:
          return SignalRException(
            type: type,
            original: error,
            statusCode: statusCode,
            stackTrace: stackTrace,
            message: "UNKNOWN ERROR TYPE: ${error.runtimeType}",
          );
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      "type": type.name,
      "message": message,
      "statusCode": statusCode,
      "original": original.toString(),
      "stackTrace": stackTrace.toString(),
      "runtimeType": original.runtimeType.toString(),
    };
  }

  @override
  String toString() {
    return "TYPE: $type,\nSIGNALR EXCEPTION: $message,\nSTACK TRACE: $stackTrace";
  }
}

/// Thrown when the SignalR handshake fails.
///
/// This means the transport connected but the server rejected the protocol
/// handshake, or the handshake response could not be parsed. The usual cause
/// is a protocol mismatch — for example, the client is configured for
/// MessagePack but the server has not registered that protocol.
///
/// Subclass of [SignalRException] with `type` [SignalRExceptionType.signalr],
/// so existing `catch (e)` blocks that test `e.type` keep working.
class SignalRHandshakeException extends SignalRException {
  SignalRHandshakeException({
    required super.message,
    super.original,
    super.stackTrace,
  }) : super(type: SignalRExceptionType.signalr);
}

/// Thrown when an operation exceeds its allotted time.
///
/// Raised when [HubConnection.invoke] passes its `timeout`, when no message
/// arrives from the server within `serverTimeoutInMilliseconds`, or when a
/// resume probe finds the connection unresponsive.
///
/// Subclass of [SignalRException] with `type` [SignalRExceptionType.timeout].
class SignalRTimeoutException extends SignalRException {
  SignalRTimeoutException({
    required super.message,
    super.original,
    super.stackTrace,
  }) : super(type: SignalRExceptionType.timeout);
}

/// Thrown when the server rejects the connection for authentication reasons.
///
/// Typically an HTTP 401 or 403 during negotiation. Check that the token
/// supplied by `accessTokenFactory` is current and carries the claims the hub
/// requires.
///
/// Subclass of [SignalRException] with `type` [SignalRExceptionType.http];
/// [statusCode] carries the HTTP status.
class SignalRAuthException extends SignalRException {
  SignalRAuthException({
    required super.message,
    super.statusCode,
    super.original,
    super.stackTrace,
  }) : super(type: SignalRExceptionType.http);
}

/// Thrown when the underlying transport fails.
///
/// Covers physical socket failures — the WebSocket closing unexpectedly, a
/// dropped SSE stream, or a long-polling request that cannot complete. Use
/// this to tell network-level failures apart from protocol errors reported by
/// the server.
///
/// Subclass of [SignalRException] with `type` [SignalRExceptionType.signalr].
class SignalRTransportException extends SignalRException {
  SignalRTransportException({
    required super.message,
    super.original,
    super.stackTrace,
  }) : super(type: SignalRExceptionType.signalr);
}

/// Thrown when an invocation is canceled through a [CancellationToken].
///
/// Subclass of [SignalRException] with `type` [SignalRExceptionType.abort].
class SignalRCancelledException extends SignalRException {
  SignalRCancelledException({
    required super.message,
    super.original,
    super.stackTrace,
  }) : super(type: SignalRExceptionType.abort);
}
