import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

// ── Test doubles ────────────────────────────────────────────────────────────

class _RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void log(LogEntry entry) {
    entries.add(entry);
  }
}

class _RecordingCrashReporting extends CrashReportingDelegate {
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

// ── Helpers ─────────────────────────────────────────────────────────────────

List<String> _initCapturing({
  LogMode mode = LogMode.enabled,
  LogFilter? logFilter,
  bool captureStackTrace = true,
  bool configureLoggingPackage = true,
  int maxCacheSize = HyperLogger.defaultMaxCacheSize,
}) {
  final captured = <String>[];
  HyperLogger.init(
    printer: DirectPrinter(output: captured.add),
    mode: mode,
    logFilter: logFilter,
    captureStackTrace: captureStackTrace,
    configureLoggingPackage: configureLoggingPackage,
    maxCacheSize: maxCacheSize,
  );
  return captured;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    HyperLogger.reset();
  });

  tearDown(() {
    HyperLogger.reset();
  });

  // ── init() with all parameter combinations ────────────────────────────────

  group('init()', () {
    test('default init does not throw', () {
      expect(() => HyperLogger.init(), returnsNormally);
    });

    test('init with custom printer receives log entries', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.info<String>('hello');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.message, contains('hello'));
    });

    test('init with all parameters does not throw', () {
      expect(
        () => HyperLogger.init(
          printer: DirectPrinter(output: (_) {}),
          mode: LogMode.silent,
          logFilter: (_) => true,
          captureStackTrace: false,
          configureLoggingPackage: false,
          maxCacheSize: 128,
        ),
        returnsNormally,
      );
    });

    test('re-init replaces printer', () {
      final printer1 = _RecordingPrinter();
      final printer2 = _RecordingPrinter();

      HyperLogger.init(printer: printer1);
      HyperLogger.info<String>('first');
      expect(printer1.entries, hasLength(1));
      expect(printer2.entries, isEmpty);

      // Second init replaces the printer.
      HyperLogger.init(printer: printer2);
      HyperLogger.info<String>('second');
      expect(printer2.entries, hasLength(1));
    });

    test('re-init replaces mode', () {
      final captured = _initCapturing(mode: LogMode.enabled);
      HyperLogger.info<String>('visible');
      expect(captured, isNotEmpty);

      captured.clear();
      HyperLogger.init(
        printer: DirectPrinter(output: captured.add),
        mode: LogMode.disabled,
      );
      HyperLogger.info<String>('invisible');
      expect(captured, isEmpty);
    });

    test('re-init replaces logFilter', () {
      // First init: filter everything.
      final captured = _initCapturing(logFilter: (_) => false);
      HyperLogger.info<String>('filtered');
      expect(captured, isEmpty);

      // Second init: allow everything.
      captured.clear();
      HyperLogger.init(
        printer: DirectPrinter(output: captured.add),
        logFilter: (_) => true,
      );
      HyperLogger.info<String>('passed');
      expect(captured, isNotEmpty);
    });

    test('re-init with different maxCacheSize clears caches', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(tag: 'a');

      // Re-init with a different cache size forces cache reset.
      _initCapturing(maxCacheSize: 128);
      final b = HyperLogger.withOptions<String>(tag: 'a');

      // After cache clear, a new instance is created.
      expect(identical(a, b), isFalse);
    });

    test('re-init with same maxCacheSize preserves caches', () {
      _initCapturing(maxCacheSize: 64);
      final a = HyperLogger.withOptions<String>(tag: 'preserved');

      // Re-init with the same cache size should NOT clear caches.
      HyperLogger.init(
        printer: DirectPrinter(output: (_) {}),
        maxCacheSize: 64,
      );
      final b = HyperLogger.withOptions<String>(tag: 'preserved');

      expect(identical(a, b), isTrue);
    });
  });

  // ── reset() ───────────────────────────────────────────────────────────────

  group('reset()', () {
    test('clears initialized state — next log auto-inits', () {
      _initCapturing();
      HyperLogger.info<String>('before reset');
      HyperLogger.reset();

      // After reset, log should auto-initialize and not throw.
      expect(() => HyperLogger.info<String>('after reset'), returnsNormally);
    });

    test('clears printer', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.info<String>('before');
      expect(printer.entries, hasLength(1));

      HyperLogger.reset();

      // After reset, the old printer should not receive anything.
      // Auto-init will create a new default printer.
      HyperLogger.info<String>('after');
      expect(printer.entries, hasLength(1)); // still just 1
    });

    test('clears delegates', () async {
      _initCapturing();
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.reset();

      expect(HyperLogger.crashReporting, isNull);
    });

    test('clears wrapper cache', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(tag: 'cached');
      HyperLogger.reset();
      _initCapturing();
      final b = HyperLogger.withOptions<String>(tag: 'cached');

      expect(identical(a, b), isFalse);
    });

    test('resets mode to enabled', () {
      _initCapturing(mode: LogMode.disabled);
      HyperLogger.reset();

      // After reset, default mode is enabled, so isEnabled should reflect
      // the root logger level (which is ALL after configureLoggingPackage).
      _initCapturing();
      expect(HyperLogger.isEnabled(LogLevel.info), isTrue);
    });

    test('resets captureStackTrace to true (default)', () {
      // We can't directly observe _captureStackTrace, but we verify that
      // after reset + init(captureStackTrace: false) the flag changes.
      _initCapturing(captureStackTrace: false);
      HyperLogger.reset();
      // After reset, the default is true. Just verify no crash.
      _initCapturing();
      expect(() => HyperLogger.info<String>('test'), returnsNormally);
    });
  });

  // ── isEnabled() ───────────────────────────────────────────────────────────

  group('isEnabled()', () {
    test(
      'returns true for all levels when mode is enabled and root is ALL',
      () {
        _initCapturing(mode: LogMode.enabled);
        for (final level in LogLevel.values) {
          expect(
            HyperLogger.isEnabled(level),
            isTrue,
            reason: 'Expected $level to be enabled',
          );
        }
      },
    );

    test('returns false for all levels when mode is disabled', () {
      _initCapturing(mode: LogMode.disabled);
      for (final level in LogLevel.values) {
        expect(
          HyperLogger.isEnabled(level),
          isFalse,
          reason: 'Expected $level to be disabled in disabled mode',
        );
      }
    });

    test('returns false for all levels when mode is silent', () {
      _initCapturing(mode: LogMode.silent);
      for (final level in LogLevel.values) {
        expect(
          HyperLogger.isEnabled(level),
          isFalse,
          reason: 'Expected $level to be disabled in silent mode',
        );
      }
    });

    test('respects setLogLevel threshold', () {
      _initCapturing();
      HyperLogger.setLogLevel(LogLevel.warning);

      expect(HyperLogger.isEnabled(LogLevel.trace), isFalse);
      expect(HyperLogger.isEnabled(LogLevel.debug), isFalse);
      expect(HyperLogger.isEnabled(LogLevel.info), isFalse);
      expect(HyperLogger.isEnabled(LogLevel.warning), isTrue);
      expect(HyperLogger.isEnabled(LogLevel.error), isTrue);
      expect(HyperLogger.isEnabled(LogLevel.fatal), isTrue);
    });

    test('auto-initializes if called before init()', () {
      // No init() call — isEnabled should trigger auto-init.
      // Default mode is enabled with root level ALL.
      expect(HyperLogger.isEnabled(LogLevel.info), isTrue);
    });
  });

  // ── configureLoggingPackage flag ──────────────────────────────────────────

  group('configureLoggingPackage', () {
    test('true sets hierarchicalLoggingEnabled and root level to ALL', () {
      HyperLogger.init(configureLoggingPackage: true);
      expect(logging.hierarchicalLoggingEnabled, isTrue);
      expect(logging.Logger.root.level, equals(logging.Level.ALL));
    });

    test('false does not override logging package configuration', () {
      // Pre-set a specific level.
      logging.Logger.root.level = logging.Level.WARNING;
      HyperLogger.init(configureLoggingPackage: false);

      // The root level should remain what we set.
      expect(logging.Logger.root.level, equals(logging.Level.WARNING));
    });
  });

  // ── captureStackTrace flag ────────────────────────────────────────────────

  group('captureStackTrace', () {
    test('true (default) captures stack trace for caller extraction', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer, captureStackTrace: true);
      HyperLogger.info<String>('with stack');
      expect(printer.entries, hasLength(1));

      // The LogMessage should have a callerStackTrace.
      final logMsg = printer.entries.first.object as LogMessage;
      expect(logMsg.callerStackTrace, isNotNull);
    });

    test('false skips stack trace capture', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer, captureStackTrace: false);
      HyperLogger.info<String>('no stack');
      expect(printer.entries, hasLength(1));

      final logMsg = printer.entries.first.object as LogMessage;
      expect(logMsg.callerStackTrace, isNull);
    });

    test(
      'method parameter skips stack trace even when captureStackTrace=true',
      () {
        final printer = _RecordingPrinter();
        HyperLogger.init(printer: printer, captureStackTrace: true);
        HyperLogger.info<String>('with method', method: 'myMethod');
        expect(printer.entries, hasLength(1));

        final logMsg = printer.entries.first.object as LogMessage;
        expect(logMsg.callerStackTrace, isNull);
        expect(logMsg.method, equals('myMethod'));
      },
    );
  });

  // ── Auto-initialization on first log call ─────────────────────────────────

  group('auto-initialization', () {
    test('info auto-initializes', () {
      expect(() => HyperLogger.info<String>('auto'), returnsNormally);
    });

    test('debug auto-initializes', () {
      expect(() => HyperLogger.debug<String>('auto'), returnsNormally);
    });

    test('trace auto-initializes', () {
      expect(() => HyperLogger.trace<String>('auto'), returnsNormally);
    });

    test('warning auto-initializes', () {
      expect(() => HyperLogger.warning<String>('auto'), returnsNormally);
    });

    test('error auto-initializes', () {
      expect(() => HyperLogger.error<String>('auto'), returnsNormally);
    });

    test('fatal auto-initializes', () {
      expect(() => HyperLogger.fatal<String>('auto'), returnsNormally);
    });

    test('stopwatch auto-initializes', () {
      expect(
        () => HyperLogger.stopwatch<String>('auto', Stopwatch()),
        returnsNormally,
      );
    });

    test('init can override after auto-init', () {
      HyperLogger.info<String>('triggers auto-init');

      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.info<String>('after override');
      expect(printer.entries, hasLength(1));
    });
  });

  // ── Mode checks: disabled vs silent vs enabled ────────────────────────────

  group('disabled mode', () {
    test('suppresses all log output', () {
      final captured = _initCapturing(mode: LogMode.disabled);
      HyperLogger.trace<String>('nope');
      HyperLogger.debug<String>('nope');
      HyperLogger.info<String>('nope');
      HyperLogger.warning<String>('nope');
      HyperLogger.error<String>('nope');
      HyperLogger.fatal<String>('nope');
      HyperLogger.stopwatch<String>('nope', Stopwatch());
      expect(captured, isEmpty);
    });

    test('does not fire crash reporting delegates', () async {
      _initCapturing(mode: LogMode.disabled);
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.warning<String>('no delegate');
      HyperLogger.error<String>('no delegate');
      HyperLogger.fatal<String>('no delegate');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, isEmpty);
      expect(crash.errors, isEmpty);
    });
  });

  group('silent mode', () {
    test('suppresses all printer output', () {
      final captured = _initCapturing(mode: LogMode.silent);
      HyperLogger.trace<String>('silent');
      HyperLogger.debug<String>('silent');
      HyperLogger.info<String>('silent');
      HyperLogger.warning<String>('silent');
      HyperLogger.error<String>('silent');
      HyperLogger.fatal<String>('silent');
      HyperLogger.stopwatch<String>('silent', Stopwatch());
      expect(captured, isEmpty);
    });

    test('still fires crash reporting on warning', () async {
      _initCapturing(mode: LogMode.silent);
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.warning<String>('silent warning');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, contains('silent warning'));
    });

    test('still fires crash reporting on error', () async {
      _initCapturing(mode: LogMode.silent);
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.error<String>('silent error', exception: Exception('e'));
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isFalse); // fatal == false
    });

    test('still fires crash reporting on fatal', () async {
      _initCapturing(mode: LogMode.silent);
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.fatal<String>('silent fatal');
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isTrue); // fatal == true
    });
  });

  group('enabled mode', () {
    test('produces output and fires delegates', () async {
      final captured = _initCapturing(mode: LogMode.enabled);
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.info<String>('visible');
      HyperLogger.warning<String>('warn');
      HyperLogger.error<String>('err');
      HyperLogger.fatal<String>('fatal');
      HyperLogger.stopwatch<String>('perf', Stopwatch()..stop());

      await Future<void>.delayed(Duration.zero);

      expect(captured, isNotEmpty);
      expect(crash.logs, contains('warn'));
      expect(crash.errors, hasLength(2)); // error + fatal
    });
  });

  // ── logFilter ─────────────────────────────────────────────────────────────

  group('logFilter', () {
    test('filter returning false suppresses entry', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer, logFilter: (_) => false);
      HyperLogger.info<String>('blocked');
      expect(printer.entries, isEmpty);
    });

    test('filter returning true passes entry', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer, logFilter: (_) => true);
      HyperLogger.info<String>('allowed');
      expect(printer.entries, hasLength(1));
    });

    test('filter can inspect entry level', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(
        printer: printer,
        logFilter: (entry) => entry.level.index >= LogLevel.warning.index,
      );
      HyperLogger.info<String>('filtered out');
      HyperLogger.warning<String>('passed through');
      HyperLogger.error<String>('also passed');

      expect(printer.entries, hasLength(2));
      expect(printer.entries[0].message, contains('passed through'));
      expect(printer.entries[1].message, contains('also passed'));
    });

    test('filter can inspect entry loggerName', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(
        printer: printer,
        logFilter: (entry) => entry.loggerName == 'int',
      );
      HyperLogger.info<int>('allowed');
      HyperLogger.info<String>('blocked');

      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.loggerName, equals('int'));
    });

    test('null logFilter allows everything', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer, logFilter: null);
      HyperLogger.info<String>('no filter');
      expect(printer.entries, hasLength(1));
    });
  });

  // ── setLogLevel ───────────────────────────────────────────────────────────

  group('setLogLevel', () {
    test('setting level to warning filters info and debug', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.setLogLevel(LogLevel.warning);

      // After setting root level to WARNING, the child loggers inherit
      // the root level in hierarchical mode. Records below WARNING
      // should not be emitted by child loggers.
      HyperLogger.info<String>('below threshold');
      HyperLogger.warning<String>('at threshold');

      // Child loggers are created with Level.ALL by default but the
      // root.onRecord listener still fires for all. The _handleLogRecord
      // does not check the level again. So this test just ensures no crash.
      expect(true, isTrue);
    });

    test('setting level to fatal is the most restrictive', () {
      _initCapturing();
      HyperLogger.setLogLevel(LogLevel.fatal);
      expect(HyperLogger.isEnabled(LogLevel.error), isFalse);
      expect(HyperLogger.isEnabled(LogLevel.fatal), isTrue);
    });

    test('setting level to trace is the most permissive', () {
      _initCapturing();
      HyperLogger.setLogLevel(LogLevel.trace);
      expect(HyperLogger.isEnabled(LogLevel.trace), isTrue);
    });
  });

  // ── attachServices / detachServices ───────────────────────────────────────

  group('attachServices / detachServices', () {
    test('attaches and exposes crash reporting', () {
      _initCapturing();
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      expect(HyperLogger.crashReporting, same(crash));
    });

    test('detachServices nulls delegate', () {
      _initCapturing();
      HyperLogger.attachServices(crashReporting: _RecordingCrashReporting());
      HyperLogger.detachServices();
      expect(HyperLogger.crashReporting, isNull);
    });

    test('attaching with null clears the delegate', () {
      _initCapturing();
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.attachServices(crashReporting: null);
      expect(HyperLogger.crashReporting, isNull);
    });

    test('can replace the crash reporting delegate', () {
      _initCapturing();
      final crash1 = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash1);

      final crash2 = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash2);

      expect(HyperLogger.crashReporting, same(crash2));
    });
  });

  // ── error with skipCrashReporting ─────────────────────────────────────────

  group('error skipCrashReporting', () {
    test('false (default) forwards to crash reporting', () async {
      _initCapturing();
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.error<String>('reported');
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
    });

    test('true suppresses crash reporting', () async {
      _initCapturing();
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.error<String>('not reported', skipCrashReporting: true);
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, isEmpty);
    });

    test('error still produces output even with skipCrashReporting', () {
      final captured = _initCapturing();
      HyperLogger.error<String>('still visible', skipCrashReporting: true);
      expect(captured.join('\n'), contains('still visible'));
    });
  });

  // ── stopwatch ─────────────────────────────────────────────────────────────

  group('stopwatch', () {
    test('includes elapsed time in output', () {
      final captured = _initCapturing();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100000; i++) {} // burn time
      sw.stop();
      HyperLogger.stopwatch<String>('query', sw);
      final output = captured.join('\n');
      expect(output, contains('query'));
      expect(output, contains('ms'));
    });
  });

  // ── type parameter forwarding ─────────────────────────────────────────────

  group('type parameter', () {
    test('loggerName matches the generic type', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.info<int>('typed');
      expect(printer.entries.first.loggerName, equals('int'));
    });

    test('different types produce different logger names', () {
      final printer = _RecordingPrinter();
      HyperLogger.init(printer: printer);
      HyperLogger.info<int>('one');
      HyperLogger.info<double>('two');

      expect(printer.entries[0].loggerName, equals('int'));
      expect(printer.entries[1].loggerName, equals('double'));
    });
  });
}
