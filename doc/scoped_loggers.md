# Scoped loggers

## Creating a scoped logger

```dart
final log = HyperLogger.withOptions<PaymentService>(
  tag: 'payments',
  minLevel: LogLevel.info,
);
```

Or from a pre-built `LoggerOptions` object:

```dart
const opts = LoggerOptions(tag: 'billing', minLevel: LogLevel.warning);
final log = HyperLogger.fromOptions<Billing>(opts);
```

## LoggerOptions

| Option | Type | Default | Effect |
|---|---|---|---|
| `mode` | `LogMode` | `enabled` | `enabled`, `silent`, or `disabled` |
| `minLevel` | `LogLevel?` | `null` | Per-scope level filter |
| `tag` | `String?` | `null` | Prepends `[tag]` to every message |
| `skipCrashReporting` | `bool` | `false` | Default for error calls (overridable per-call) |

## Caching

Scoped loggers are cached by type + options. Repeated calls with the
same arguments return the same instance:

```dart
final a = HyperLogger.withOptions<String>(tag: 'auth');
final b = HyperLogger.withOptions<String>(tag: 'auth');
assert(identical(a, b)); // true
```

Different options produce different instances:

```dart
final a = HyperLogger.withOptions<String>(tag: 'auth');
final b = HyperLogger.withOptions<String>(tag: 'payments');
assert(!identical(a, b)); // true
```

## Runtime mode toggling

`ScopedLogger.mode` is mutable. Since instances are cached, all holders
see the change — useful for feature flags:

```dart
final log = HyperLogger.withOptions<Analytics>(tag: 'analytics');

// Later, based on a remote config flag:
log.mode = LogMode.disabled;  // all analytics logging stops
```

**Be aware**: because instances are cached, changing `mode` on one
reference affects all code using the same scoped logger instance.

## Silent mode and delegates

In `LogMode.silent`, scoped loggers suppress printer output but still
fire the crash reporting delegate:

- `warning()` fires `CrashReportingDelegate.log()`
- `error()` fires `CrashReportingDelegate.recordError()`
- `fatal()` fires `CrashReportingDelegate.recordError(fatal: true)`
- `trace()`, `debug()`, `info()`, `stopwatch()` are fully suppressed

Tags are included in delegate messages:

```dart
final log = HyperLogger.withOptions<Api>(tag: 'api', mode: LogMode.silent);
log.warning('timeout');
// CrashReportingDelegate receives: "[api] timeout"
```

## minLevel filtering

`minLevel` suppresses everything below the threshold, including the delegate:

```dart
final log = HyperLogger.withOptions<NoisyService>(minLevel: LogLevel.error);
log.warning('suppressed');  // no output, no delegate
log.error('visible');       // output + delegate
```

This differs from `LogMode.silent`, which only suppresses output while
letting the crash reporting delegate fire.

## Mocking in tests

`ScopedLoggerApi<T>` is an interface with all log methods:

```dart
class MockLogger implements ScopedLoggerApi<MyService> {
  final calls = <String>[];

  @override
  void info(String msg, {Object? data, String? method}) => calls.add(msg);

  @override
  void trace(String msg, {Object? data, String? method}) => calls.add(msg);

  // ... all methods
}
```

Inject the mock via constructor, or override `scopedLogger` in the mixin.

## Available methods

`ScopedLoggerApi<T>` provides: `trace`, `debug`, `info`, `warning`,
`error`, `fatal`, `stopwatch`.
