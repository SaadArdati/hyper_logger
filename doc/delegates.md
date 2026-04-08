# Crash reporting delegate

When your app is in production, console logs don't help. You need errors
to reach a crash reporting service so you can find out what went wrong
after the fact. hyper_logger forwards specific log events to an external
service via a delegate interface. This is how you wire up Firebase
Crashlytics, Sentry, Datadog, or any other crash reporting tool.

## CrashReportingDelegate

The delegate interface has two methods:

```dart
abstract class CrashReportingDelegate {
  Future<void> log(String message);

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  });
}
```

- `log(message)` is called when `HyperLogger.warning()` fires. Use it
  for breadcrumb-style messages that add context to crash reports.
- `recordError(...)` is called when `HyperLogger.error()` or
  `HyperLogger.fatal()` fires. This is your actual error reporting path.

## Implementing a delegate

Here's a Firebase Crashlytics implementation:

```dart
class MyCrashReporter implements CrashReportingDelegate {
  @override
  Future<void> log(String message) async {
    await FirebaseCrashlytics.instance.log(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }
}
```

For Sentry, the interface would look similar but route to
`Sentry.captureException()` instead.

## Attaching and detaching

```dart
void main() {
  HyperLogger.init();
  HyperLogger.attachServices(
    crashReporting: MyCrashReporter(),
  );
}
```

Detach for test teardown or when switching services:

```dart
HyperLogger.detachServices();
```

Check what's currently attached:

```dart
if (HyperLogger.crashReporting != null) {
  // A delegate is active
}
```

`reset()` also clears the delegate, along with everything else.

## Which log methods fire the delegate?

| Method | Delegate call | `fatal` flag |
|---|---|---|
| `warning()` | `log(message)` | - |
| `error()` | `recordError(exception, stackTrace)` | `false` |
| `fatal()` | `recordError(exception, stackTrace)` | `true` |
| `trace()`, `debug()`, `info()`, `stopwatch()` | None | - |

When no `exception` is provided to `error()` or `fatal()`, the log
message string itself is passed as the error object to `recordError()`.
The original message is always passed as `reason` for context.

## Delegate behavior by mode

| Mode | Delegates fire? | Console output? |
|---|---|---|
| `LogMode.enabled` | Yes | Yes |
| `LogMode.silent` | Yes | No |
| `LogMode.disabled` | No | No |

This is the key difference between `silent` and `disabled`. In a
production Flutter app, you typically use `LogMode.silent`: the console
is quiet, but errors still reach Crashlytics. See
[Configuration: Log modes](configuration.md#log-modes) for a full
explanation.

## Delegate behavior with minLevel

`minLevel` filtering (on [scoped loggers](scoped_loggers.md)) suppresses
**everything** below the threshold, including delegates. This is
different from `LogMode.silent`:

```dart
final log = HyperLogger.withOptions<Api>(minLevel: LogLevel.error);
log.warning('rate limit');  // Suppressed: no delegate, no output
log.error('failed');        // Both delegate and output fire
```

## Skipping crash reporting per-scope or per-call

Sometimes a scope handles its own error recovery and you don't want
those expected errors cluttering your crash dashboard.

Set a default for the entire scope:

```dart
final log = HyperLogger.withOptions<ImageCache>(
  skipCrashReporting: true,
);
log.error('Cache miss', exception: e);
// Output prints, but delegate does NOT fire. This error is expected.
```

Override per-call when one error in an otherwise-quiet scope is worth
reporting:

```dart
log.error('Disk full', exception: e, skipCrashReporting: false);
// This one fires the delegate despite the scope default.
```

`fatal()` always fires the delegate regardless of `skipCrashReporting`.
If something is fatal, you want to know about it.

## Error safety

Your crash reporting SDK might not be initialized yet. It might throw
because of a network failure. It might reject a Future. None of that
matters: delegate calls are wrapped in `fireDelegateSafely()`, which
catches both synchronous throws and async rejections. The error is
silently swallowed.

Logging never crashes your app. Not even if your crash reporter crashes.

## Delegate call timing

Delegate calls happen before printer output in the same method, and
they are fire-and-forget. The returned Future is not awaited, just
error-handled. This means delegate calls never block the logging call
and never slow down your app.

See [example/crash_reporting_example.dart](../example/crash_reporting_example.dart)
for a complete runnable example.
