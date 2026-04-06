# HyperLoggerMixin

A convenience mixin that gives any class instance-level logging methods
with automatic type parameter forwarding.

## Basic usage

```dart
class AuthService with HyperLoggerMixin<AuthService> {
  void login(String email) {
    logInfo('Login attempt', data: {'email': email});
    // Output: 💡 [AuthService.login] Login attempt
  }
}
```

Without any configuration, the mixin delegates to `HyperLogger` static
methods, forwarding the `<T>` type parameter automatically.

## With a scoped logger

Override `scopedLogger` to use scoped options (tags, level filters, mode):

```dart
class PaymentService with HyperLoggerMixin<PaymentService> {
  @override
  final scopedLogger = HyperLogger.withOptions<PaymentService>(
    tag: 'payments',
    minLevel: LogLevel.info,
  );

  void process() {
    logInfo('Processing payment');
    // Output: 💡 [PaymentService.process] [payments] Processing payment

    logDebug('Connecting to gateway');
    // Suppressed — debug < info (minLevel)
  }
}
```

When `scopedLogger` is provided, all `logX` methods delegate to it
instead of the global `HyperLogger`. This gives you per-class tags,
level filtering, mode control, and `skipCrashReporting` defaults.

See [example/mixin_example.dart](../example/mixin_example.dart) for a
full runnable example.

## Available methods

| Method | Delegates to |
|---|---|
| `logTrace(msg, {data, method})` | `trace()` |
| `logDebug(msg, {data, method})` | `debug()` |
| `logInfo(msg, {data, method})` | `info()` |
| `logWarning(msg, {data, method})` | `warning()` |
| `logError(msg, {exception, stackTrace, data, method, skipCrashReporting})` | `error()` |
| `logFatal(msg, {exception, stackTrace, data, method})` | `fatal()` |
| `logStopwatch(msg, stopwatch, {method})` | `stopwatch()` |

## Injecting for tests

Make `scopedLogger` settable so tests can inject a mock:

```dart
class MyService with HyperLoggerMixin<MyService> {
  @override
  final ScopedLoggerApi<MyService>? scopedLogger;

  MyService({this.scopedLogger});
}

// In tests:
final mock = MockLogger();
final service = MyService(scopedLogger: mock);
service.doWork();
expect(mock.infoCalls, contains('work started'));
```

## When to use the mixin vs static calls vs scoped loggers

| Approach | Best for |
|---|---|
| `HyperLogger.info<T>(...)` | One-off calls, scripts, top-level functions |
| `HyperLoggerMixin<T>` | Classes that log frequently — avoids repeating `<T>` |
| `ScopedLogger` directly | Feature modules that need tags, level filters, or mode toggling |
| Mixin + `scopedLogger` | Classes that log frequently AND need scoped config |

## Fallback behavior

If `scopedLogger` returns `null` (the default), every `logX` call falls
back to the corresponding `HyperLogger` static method. This means:

- The global `mode`, `logFilter`, and `printer` apply
- Delegates fire as configured globally
- `captureStackTrace` setting is respected

If `scopedLogger` is provided:

- The scoped logger's `mode`, `minLevel`, and `tag` apply
- Delegates fire through the scoped logger's dispatch
- The global mode is still respected (most restrictive wins for global mode;
  scoped mode is independent)
