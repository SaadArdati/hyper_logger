# Crash reporting delegate

hyper_logger forwards specific log events to an external crash reporting
service via a delegate interface. This is how you wire up Crashlytics,
Sentry, or any other service.

## CrashReportingDelegate

Receives warning, error, and fatal log events:

```dart
class MyCrashReporter implements CrashReportingDelegate {
  @override
  Future<void> log(String message) async {
    // Called on HyperLogger.warning()
    await FirebaseCrashlytics.instance.log(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    // Called on HyperLogger.error() and HyperLogger.fatal()
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }
}
```

## Attaching the delegate

```dart
void main() {
  HyperLogger.init();
  HyperLogger.attachServices(
    crashReporting: MyCrashReporter(),
  );
}
```

Detach for test teardown:

```dart
HyperLogger.detachServices();
```

Check what's attached:

```dart
if (HyperLogger.crashReporting != null) { /* ... */ }
```

## Which log methods fire the delegate?

| Method | Delegate | Call |
|---|---|---|
| `warning()` | `CrashReportingDelegate` | `log(message)` |
| `error()` | `CrashReportingDelegate` | `recordError(exception, stackTrace)` |
| `fatal()` | `CrashReportingDelegate` | `recordError(exception, stackTrace, fatal: true)` |
| `trace()`, `debug()`, `info()`, `stopwatch()` | None | — |

## Delegate and LogMode

| Mode | Delegate fires? |
|---|---|
| `LogMode.enabled` | Yes |
| `LogMode.silent` | Yes |
| `LogMode.disabled` | No |

This is the key difference between `silent` and `disabled` — silent
suppresses printer output but still forwards to crash reporting.

## Delegate and ScopedLogger.minLevel

`minLevel` filtering suppresses **everything** including delegates.
This differs from `LogMode.silent`:

```dart
final log = HyperLogger.withOptions<Api>(minLevel: LogLevel.error);
log.warning('rate limit');  // Suppressed — no delegate, no output
log.error('failed');        // Both delegate and output fire
```

## Error safety

Delegate calls are wrapped in error boundaries. If your Crashlytics SDK
throws (not initialized, network failure, etc.), the error is swallowed.
Logging never crashes the app.

Both synchronous throws and async Future rejections are caught.

See [example/crash_reporting_example.dart](../example/crash_reporting_example.dart)
for a complete runnable example.
