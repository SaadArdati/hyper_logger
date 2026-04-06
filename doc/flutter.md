# Flutter Integration

A production-ready guide for using hyper_logger in Flutter apps, covering
error handling, Firebase delegates, zone interception, build modes, and
`debugPrint` integration.

See [example/crash_reporting_example.dart](../example/crash_reporting_example.dart)
for a quick runnable demo of delegate wiring.

## Basic setup

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hyper_logger/hyper_logger.dart';

void main() {
  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s), // Android throttling
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  );

  runApp(const MyApp());
}
```

Using `debugPrint` as the output sink prevents Android from dropping log
lines when output is fast. Setting `LogMode.silent` in release mode
suppresses console output while keeping crash reporting active.

## Catching all errors

Flutter has two error surfaces. You need both:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s),
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  );

  // 1. Synchronous Flutter framework errors (widget build, layout, painting)
  FlutterError.onError = (details) {
    HyperLogger.error<FlutterError>(
      details.exceptionAsString(),
      exception: details.exception,
      stackTrace: details.stack,
      // Avoid double-reporting: we forward manually below
      skipCrashReporting: true,
    );
    // Forward to Crashlytics directly for Flutter-specific metadata
    if (!kDebugMode) {
      HyperLogger.crashReporting
          ?.recordError(details.exception, details.stack, reason: details.context?.toString())
          .ignore();
    }
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

`skipCrashReporting: true` on `FlutterError.onError` prevents
double-reporting. The `error()` call would fire the delegate, AND the
manual `recordError` would fire again. Use one or the other.

## Firebase Crashlytics delegate

```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hyper_logger/hyper_logger.dart';

class CrashlyticsCrashReporting extends CrashReportingDelegate {
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  @override
  Future<void> log(String message) {
    return _crashlytics.log(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    return _crashlytics.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }
}
```

## Attaching the delegate after Firebase init

Delegates should be attached after Firebase is initialized, not before:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Init logger early (console output works immediately)
  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s),
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  );

  // 2. Init Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. Attach delegate (now Firebase is ready)
  HyperLogger.attachServices(
    crashReporting: CrashlyticsCrashReporting(),
  );

  // 4. Set up error handlers (after delegates are attached)
  FlutterError.onError = (details) { /* ... */ };
  PlatformDispatcher.instance.onError = (error, stack) { /* ... */ };

  runApp(const MyApp());
}
```

Logs between steps 1 and 3 go to the console but not to the delegate (it
isn't attached yet). This is fine; initialization logs rarely need crash
reporting.

## Suppressing print() in production

Use `runZoned` with a `ZoneSpecification` to intercept all `print()`
calls, including from third-party packages:

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

This catches `print()` calls from every package in your dependency graph,
not just your own code.

## Platform-aware delegates

Firebase Crashlytics is not available on all platforms. Use conditional
construction:

```dart
import 'dart:io' show Platform;

CrashReportingDelegate? createCrashReporting() {
  if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) {
    return CrashlyticsCrashReporting();
  }
  return null; // No crash reporting on web/linux/windows
}
```

On web, use conditional imports:

```dart
// crash_reporting_factory.dart
export 'crash_reporting_factory_native.dart'
    if (dart.library.js_interop) 'crash_reporting_factory_web.dart';
```

## Build mode configuration

| Mode | Recommended `LogMode` | Delegates | Console |
|---|---|---|---|
| Debug | `enabled` | Optional | Full output |
| Profile | `enabled` | Yes | Full output |
| Release | `silent` | Yes | Suppressed |

```dart
HyperLogger.init(
  mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
  captureStackTrace: !kReleaseMode, // Skip the ~700ns overhead in release
);
```

In release mode with `LogMode.silent`:
- Console output is suppressed (no noise in logcat)
- Crash reporting delegate still fires (errors reach Crashlytics)

## User identification

Sync user ID with crash reporting when auth state changes:

```dart
// When user logs in:
FirebaseCrashlytics.instance.setUserIdentifier(user.id);
FirebaseAnalytics.instance.setUserId(id: user.id);

// When user logs out:
FirebaseCrashlytics.instance.setUserIdentifier('');
FirebaseAnalytics.instance.setUserId(id: null);
```

This isn't part of hyper_logger itself, but it's critical for useful
crash reports.

## Bridging third-party package loggers

Third-party packages with their own logging interfaces can be bridged to
hyper_logger:

```dart
class ThirdPartyLogBridge implements ThirdPartyLogDelegate {
  @override
  void debug(String message, {Object? data}) {
    HyperLogger.debug<ThirdPartyLogBridge>(message, data: data);
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    HyperLogger.error<ThirdPartyLogBridge>(
      message,
      exception: error,
      stackTrace: stackTrace,
    );
  }
}

// In your DI setup:
thirdPartyService.setLogger(ThirdPartyLogBridge());
```

This funnels all third-party logs through hyper_logger, giving you
consistent formatting, level filtering, and crash reporting.

## Complete production main.dart

Putting it all together:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hyper_logger/hyper_logger.dart';

void main() {
  runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Logger: console output immediately
      HyperLogger.init(
        printer: LogPrinterPresets.automatic(
          output: (s) => debugPrint(s),
        ),
        mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
        captureStackTrace: !kReleaseMode,
      );

      // Firebase
      await Firebase.initializeApp();

      // Delegate: attached after Firebase is ready
      HyperLogger.attachServices(
        crashReporting: CrashlyticsCrashReporting(),
      );

      // Error handlers
      FlutterError.onError = (details) {
        HyperLogger.error<FlutterError>(
          details.exceptionAsString(),
          exception: details.exception,
          stackTrace: details.stack,
          skipCrashReporting: true,
        );
        if (!kDebugMode) {
          FirebaseCrashlytics.instance
              .recordFlutterFatalError(details);
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        HyperLogger.error<PlatformDispatcher>(
          'Unhandled async error',
          exception: error,
          stackTrace: stack,
        );
        return true;
      };

      runApp(const MyApp());
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        if (!kReleaseMode) {
          parent.print(zone, message);
        }
      },
    ),
  );
}
```
