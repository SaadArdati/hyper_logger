# Firebase Crashlytics integration

This guide covers wiring hyper_logger to Firebase Crashlytics as your
crash reporting delegate. For general Flutter setup (error handling,
build modes, `debugPrint`), see [Flutter integration](flutter.md).

## Implementing the delegate

```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hyper_logger/hyper_logger.dart';

class CrashlyticsCrashReporting implements CrashReportingDelegate {
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

You can't call Crashlytics APIs before `Firebase.initializeApp()`
completes. The logger can be initialized early (console output works
immediately), but the delegate should be attached after Firebase is
ready:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Init logger early
  HyperLogger.init(
    printer: LogPrinterPresets.automatic(
      output: (s) => debugPrint(s),
    ),
    mode: kReleaseMode ? LogMode.silent : LogMode.enabled,
    captureStackTrace: !kReleaseMode,
  );

  // 2. Init Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. Attach delegate (skip in debug)
  if (!kDebugMode) {
    HyperLogger.attachServices(
      crashReporting: CrashlyticsCrashReporting(),
    );
  }

  // 4. Set up error handlers
  FlutterError.onError = (details) { /* ... */ };
  PlatformDispatcher.instance.onError = (error, stack) { /* ... */ };

  runApp(const MyApp());
}
```

Logs between steps 1 and 3 go to the console but not to the delegate.
This is fine. Initialization logs rarely need crash reporting.

In debug mode, the delegate isn't attached at all. You get full console
output without any crash reporting noise.

## FlutterError and Crashlytics

There are two ways to handle `FlutterError.onError` with Crashlytics,
and which one you choose depends on how much metadata you need.

**The simple approach:** let hyper_logger's delegate handle everything.

```dart
FlutterError.onError = (details) {
  HyperLogger.error<FlutterError>(
    details.exceptionAsString(),
    exception: details.exception,
    stackTrace: details.stack,
  );
};
```

This works. The delegate fires, Crashlytics receives the exception and
stack trace. But hyper_logger's `CrashReportingDelegate` interface is
generic. It can only pass the exception, stack trace, fatal flag, and a
reason string. `FlutterErrorDetails` contains more than that: which
widget was building, which RenderObject was being laid out, the full
error context chain. The generic interface can't convey these.

**The metadata-preserving approach:** log through hyper_logger for
console output, but call Crashlytics directly with the full
`FlutterErrorDetails`:

```dart
FlutterError.onError = (details) {
  HyperLogger.error<FlutterError>(
    details.exceptionAsString(),
    exception: details.exception,
    stackTrace: details.stack,
    skipCrashReporting: true, // Avoid double-reporting
  );
  if (!kDebugMode) {
    FirebaseCrashlytics.instance
        .recordFlutterFatalError(details);
  }
};
```

`skipCrashReporting: true` prevents the delegate from firing, so
Crashlytics only receives the report through the manual call with full
Flutter metadata. This produces richer crash reports but couples your
error handler to Crashlytics directly.

Async errors don't have this trade-off. `PlatformDispatcher` errors are
just an exception and a stack trace, which the generic delegate handles
without any loss:

```dart
PlatformDispatcher.instance.onError = (error, stack) {
  HyperLogger.error<PlatformDispatcher>(
    'Unhandled async error',
    exception: error,
    stackTrace: stack,
  );
  return true;
};
```

## Complete production main.dart

Putting it all together with error handling, zone interception, and
Crashlytics:

```dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

      // Delegate: skip in debug, attach after Firebase is ready
      if (!kDebugMode) {
        HyperLogger.attachServices(
          crashReporting: CrashlyticsCrashReporting(),
        );
      }

      // Flutter framework errors: manual Crashlytics call for full metadata
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

      // Async errors: generic delegate handles these fine
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

See [example/crash_reporting_example.dart](../example/crash_reporting_example.dart)
for a simpler runnable demo.
