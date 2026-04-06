import 'dart:async';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ── Throwing test doubles ───────────────────────────────────────────────────

/// A printer that throws synchronously on every log call.
class _ThrowingPrinter implements LogPrinter {
  int callCount = 0;

  @override
  void log(LogEntry entry) {
    callCount++;
    throw StateError('Printer exploded!');
  }
}

/// A log filter that throws synchronously.
bool _throwingFilter(LogEntry entry) {
  throw StateError('Filter exploded!');
}

/// A crash reporting delegate that throws synchronously.
class _SyncThrowingCrashReporting extends CrashReportingDelegate {
  int callCount = 0;

  @override
  Future<void> log(String message) {
    callCount++;
    throw StateError('CrashReporting.log exploded!');
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    callCount++;
    throw StateError('CrashReporting.recordError exploded!');
  }
}

/// A crash reporting delegate that returns a Future that rejects.
class _AsyncThrowingCrashReporting extends CrashReportingDelegate {
  int callCount = 0;

  @override
  Future<void> log(String message) {
    callCount++;
    return Future.error(StateError('Async CrashReporting.log failed!'));
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    callCount++;
    return Future.error(StateError('Async CrashReporting.recordError failed!'));
  }
}

/// A printer that counts calls without throwing.
class _CountingPrinter implements LogPrinter {
  int callCount = 0;

  @override
  void log(LogEntry entry) {
    callCount++;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    HyperLogger.reset();
  });

  tearDown(() {
    HyperLogger.reset();
  });

  // ── Printer that throws ─────────────────────────────────────────────────

  group('printer that throws', () {
    test('does not crash — error is swallowed by _handleLogRecord', () {
      final throwingPrinter = _ThrowingPrinter();
      HyperLogger.init(printer: throwingPrinter);

      // This should NOT throw, the try-catch in _handleLogRecord swallows it.
      expect(() => HyperLogger.info<String>('boom'), returnsNormally);
      expect(throwingPrinter.callCount, equals(1));
    });

    test('subsequent log calls still work after printer throws', () {
      final throwingPrinter = _ThrowingPrinter();
      HyperLogger.init(printer: throwingPrinter);

      HyperLogger.info<String>('first boom');
      HyperLogger.info<String>('second boom');
      HyperLogger.info<String>('third boom');

      expect(throwingPrinter.callCount, equals(3));
    });

    test('delegates still fire even when printer throws', () async {
      final throwingPrinter = _ThrowingPrinter();
      HyperLogger.init(printer: throwingPrinter);

      // Actually, printer throws in _handleLogRecord which is AFTER the
      // delegate calls in warning/error/fatal. But the delegate calls
      // happen in the log methods, before _log publishes to the logging
      // package. So delegates should have been called already.
      // However, in enabled mode, the flow is:
      // 1. warning() calls _fireDelegate(crashReporting.log)
      // 2. warning() calls _log() which publishes a LogRecord
      // 3. _handleLogRecord receives it and calls printer.log() which throws
      // So delegate fires BEFORE the printer.

      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.warning<String>('warn with bad printer');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, contains('warn with bad printer'));
    });
  });

  // ── LogFilter that throws ─────────────────────────────────────────────────

  group('logFilter that throws', () {
    test('does not crash — error is swallowed by _handleLogRecord', () {
      HyperLogger.init(printer: _CountingPrinter(), logFilter: _throwingFilter);

      // The try-catch in _handleLogRecord wraps the filter call.
      expect(() => HyperLogger.info<String>('filtered'), returnsNormally);
    });

    test('subsequent log calls still work after filter throws', () {
      final printer = _CountingPrinter();
      HyperLogger.init(printer: printer, logFilter: _throwingFilter);

      HyperLogger.info<String>('one');
      HyperLogger.info<String>('two');
      HyperLogger.info<String>('three');

      // All swallowed by try-catch, printer never called because filter
      // throws before the printer.log() line.
      expect(printer.callCount, equals(0));
    });
  });

  // ── Delegate that throws synchronously ────────────────────────────────────

  group('delegate that throws synchronously', () {
    test('crash reporting log() throw is swallowed by _fireDelegate', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _SyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      expect(() => HyperLogger.warning<String>('sync throw'), returnsNormally);
      expect(crash.callCount, equals(1));
    });

    test(
      'crash reporting recordError() throw is swallowed by _fireDelegate on error',
      () {
        HyperLogger.init(printer: DirectPrinter(output: (_) {}));
        final crash = _SyncThrowingCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);

        expect(
          () => HyperLogger.error<String>('sync throw error'),
          returnsNormally,
        );
        expect(crash.callCount, equals(1));
      },
    );

    test(
      'crash reporting recordError() throw is swallowed by _fireDelegate on fatal',
      () {
        HyperLogger.init(printer: DirectPrinter(output: (_) {}));
        final crash = _SyncThrowingCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);

        expect(
          () => HyperLogger.fatal<String>('sync throw fatal'),
          returnsNormally,
        );
        expect(crash.callCount, equals(1));
      },
    );
  });

  // ── Delegate that returns a Future that rejects ───────────────────────────

  group('delegate that returns a rejecting Future', () {
    test('crash reporting log() async failure is caught by catchError', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _AsyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      // The _fireDelegate wraps with catchError, so the rejected future
      // should not surface as an unhandled exception.
      expect(
        () => HyperLogger.warning<String>('async reject'),
        returnsNormally,
      );
      expect(crash.callCount, equals(1));
    });

    test('crash reporting recordError() async failure is caught', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _AsyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      expect(
        () => HyperLogger.error<String>('async reject error'),
        returnsNormally,
      );
    });

    test('crash reporting recordError() async failure is caught on fatal', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _AsyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      expect(
        () => HyperLogger.fatal<String>('async reject fatal'),
        returnsNormally,
      );
    });
  });

  // ── Multiple rapid failures don't cascade ─────────────────────────────────

  group('multiple rapid failures', () {
    test('100 rapid calls with throwing printer do not cascade', () {
      final throwingPrinter = _ThrowingPrinter();
      HyperLogger.init(printer: throwingPrinter);

      for (var i = 0; i < 100; i++) {
        expect(() => HyperLogger.info<String>('rapid $i'), returnsNormally);
      }
      expect(throwingPrinter.callCount, equals(100));
    });

    test('100 rapid calls with throwing filter do not cascade', () {
      HyperLogger.init(printer: _CountingPrinter(), logFilter: _throwingFilter);

      for (var i = 0; i < 100; i++) {
        expect(() => HyperLogger.info<String>('rapid $i'), returnsNormally);
      }
    });

    test('mixed throwing delegates in rapid succession', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _SyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      for (var i = 0; i < 50; i++) {
        expect(() => HyperLogger.warning<String>('w$i'), returnsNormally);
        expect(() => HyperLogger.error<String>('e$i'), returnsNormally);
        expect(() => HyperLogger.fatal<String>('f$i'), returnsNormally);
        expect(
          () => HyperLogger.stopwatch<String>('s$i', Stopwatch()),
          returnsNormally,
        );
      }

      // All calls should have been attempted.
      expect(crash.callCount, equals(150)); // 50 warning + 50 error + 50 fatal
    });

    test('async rejecting delegates in rapid succession do not leak', () async {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      final crash = _AsyncThrowingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      for (var i = 0; i < 50; i++) {
        HyperLogger.warning<String>('w$i');
        HyperLogger.error<String>('e$i');
        HyperLogger.fatal<String>('f$i');
      }

      // Give all futures a chance to reject (and be caught).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // If we got here without an unhandled async error, the test passes.
      expect(crash.callCount, equals(150));
    });
  });

  // ── No delegate attached — null safety ────────────────────────────────────

  group('no delegates attached', () {
    test('warning without crash reporting does not throw', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      expect(
        () => HyperLogger.warning<String>('no crash reporting'),
        returnsNormally,
      );
    });

    test('error without crash reporting does not throw', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      expect(
        () => HyperLogger.error<String>('no crash reporting'),
        returnsNormally,
      );
    });

    test('fatal without crash reporting does not throw', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      expect(
        () => HyperLogger.fatal<String>('no crash reporting'),
        returnsNormally,
      );
    });

    test('stopwatch without analytics does not throw', () {
      HyperLogger.init(printer: DirectPrinter(output: (_) {}));
      expect(
        () => HyperLogger.stopwatch<String>('no analytics', Stopwatch()),
        returnsNormally,
      );
    });
  });
}

// ── Helper for the printer throw + delegate test ────────────────────────────

class _FakeCrashReporting extends CrashReportingDelegate {
  final List<String> logs = [];
  final List<(Object, StackTrace?, bool, String?)> errors = [];

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add((error, stackTrace, fatal, reason));
  }
}
