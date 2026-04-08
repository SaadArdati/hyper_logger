# Flutter integration

This guide covers using hyper_logger in a Flutter app: error handling,
build modes, `debugPrint` integration, and zone interception.

For Firebase Crashlytics setup, see [Firebase integration](firebase.md).

## Basic setup

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hyper_logger/hyper_logger.dart';

void main() {
  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s),
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  );

  runApp(const MyApp());
}
```

Two things worth noting here:

**`debugPrint` as the output sink.** On Android, the system logger
(`logcat`) has a line-rate limit. If your app logs quickly, lines get
silently dropped. Flutter's `debugPrint` throttles output to stay within
that limit. Passing it as the `output` callback prevents log loss.

This is different from `ThrottledPrinter`. `debugPrint` throttles the
*delivery* of lines to the platform logger so Android doesn't drop them.
`ThrottledPrinter` throttles the *number of log entries* that reach the
printer at all, dropping excess entries when your code logs too fast. In
a Flutter app, you might use both: `ThrottledPrinter` to cap how many
entries are processed per second, and `debugPrint` as the output sink to
make sure the ones that do get through aren't lost by Android. See
[Custom printers: ThrottledPrinter](custom_printers.md#throttledprinter).

**`LogMode.silent` in release mode.** Your users don't see the console,
so printing there wastes resources. But `silent` still forwards warnings
and errors to your crash reporting delegate. See
[Configuration: Log modes](configuration.md#log-modes) for the full
explanation.

## Catching all errors

Flutter has two separate error surfaces:

1. **Synchronous Flutter framework errors**: widget build failures,
   layout exceptions, painting errors. These go through
   `FlutterError.onError`. By default, Flutter renders these as the
   red error screen in debug mode (the "RenderFlex overflowed" screen
   you've probably seen) and silently logs them in release mode.
2. **Asynchronous errors**: uncaught exceptions in Futures, event
   handlers, isolate callbacks. These go through
   `PlatformDispatcher.instance.onError`.

You may want to override one or both of these, depending on your needs.
If you're happy with Flutter's default error rendering for framework
errors and just want async coverage, skip `FlutterError.onError`. If
you want all errors funneled through hyper_logger for consistent
formatting and crash reporting, override both:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s),
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  );

  // 1. Synchronous Flutter framework errors
  FlutterError.onError = (details) {
    HyperLogger.error<FlutterError>(
      details.exceptionAsString(),
      exception: details.exception,
      stackTrace: details.stack,
    );
  };

  // 2. Async errors (uncaught exceptions in futures, event handlers)
  PlatformDispatcher.instance.onError = (error, stack) {
    HyperLogger.error<PlatformDispatcher>(
      'Unhandled async error',
      exception: error,
      stackTrace: stack,
    );
    return true; // Prevents the error from propagating
  };

  runApp(const MyApp());
}
```

## Suppressing `print()` in production

Third-party packages in your dependency graph might use raw `print()`
calls. In production, these are noise. Use `runZoned` with a
`ZoneSpecification` to intercept all `print()` calls:

```dart
void main() {
  runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      HyperLogger.init(/* ... */);
      // ... rest of init
      runApp(const MyApp());
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        if (!kReleaseMode) {
          parent.print(zone, message);
        }
        // In release mode: silently dropped
      },
    ),
  );
}
```

This catches `print()` calls from every package in your dependency
graph, not just your own code.

Alternatively, instead of dropping them, you can funnel stray `print()`
calls through hyper_logger so they get the same formatting, filtering,
and crash reporting as the rest of your logs:

```dart
zoneSpecification: ZoneSpecification(
  print: (self, parent, zone, message) {
    HyperLogger.debug<Zone>(message);
  },
),
```

This way nothing is silently lost. Third-party `print()` calls show up
as debug-level entries in your log output, and you can filter them with
`logFilter` or `minLevel` if they're noisy.

## Build mode configuration

| Mode | Recommended `LogMode` | Delegates | Console |
|---|---|---|---|
| Debug | `enabled` | No | Full output |
| Profile | `enabled` | Yes | Full output |
| Release | `silent` | Yes | Suppressed |

```dart
HyperLogger.init(
  mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  captureStackTrace: !kReleaseMode,
);
```

In release mode with `LogMode.silent`: console output is suppressed (no
noise in logcat), but the crash reporting delegate still fires (errors
reach your crash reporting service).

Disabling `captureStackTrace` in release is recommended for two reasons.
First, it saves the ~700ns overhead per log call. Second, in release
builds, Dart obfuscates and minifies stack traces, so the frames
hyper_logger captures are unreadable anyway. `T.toString()` also returns
minified class names in `dart2js` builds, so type prefixes like
`[AuthService.login]` become garbled. Your crash reporting service
handles symbolication on its own using your app's debug symbols. Let it
do that job instead.
