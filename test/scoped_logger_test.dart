import 'package:hyper_logger/hyper_logger.dart';
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

// ── Dummy types for generic parameter testing ───────────────────────────────

class _MyService {}

class _OtherService {}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late _RecordingPrinter printer;

  setUp(() {
    HyperLogger.reset();
    printer = _RecordingPrinter();
    HyperLogger.init(printer: printer);
  });

  tearDown(() {
    HyperLogger.reset();
  });

  // ── Mode: disabled ────────────────────────────────────────────────────────

  group('mode disabled', () {
    test('suppresses all log levels', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.disabled),
      );

      scoped.trace('t');
      scoped.debug('d');
      scoped.info('i');
      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');
      scoped.stopwatch('s', Stopwatch());

      expect(printer.entries, isEmpty);
    });

    test('does not fire crash reporting delegates', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.disabled),
      );

      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, isEmpty);
      expect(crash.errors, isEmpty);
    });
  });

  // ── Mode: silent ──────────────────────────────────────────────────────────

  group('mode silent', () {
    test('suppresses all printer output', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.trace('t');
      scoped.debug('d');
      scoped.info('i');
      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');
      scoped.stopwatch('s', Stopwatch());

      expect(printer.entries, isEmpty);
    });

    test('fires crash reporting on warning via delegate dispatch', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.warning('silent warn');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, contains('silent warn'));
    });

    test('fires crash reporting on error via delegate dispatch', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.error('silent err', exception: Exception('e'));
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isFalse); // not fatal
    });

    test('fires crash reporting on fatal via delegate dispatch', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.fatal('silent fatal', exception: Exception('f'));
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isTrue); // fatal
    });

    test(
      'silent mode error with skipCrashReporting does not fire crash reporting',
      () async {
        final crash = _RecordingCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);

        final scoped = ScopedLogger<String>(
          options: const LoggerOptions(
            mode: LogMode.silent,
            skipCrashReporting: true,
          ),
        );

        scoped.error('skipped');
        await Future<void>.delayed(Duration.zero);

        expect(crash.errors, isEmpty);
      },
    );

    test('trace is fully suppressed in silent mode (no delegate)', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.trace('silent trace');
      expect(printer.entries, isEmpty);
    });

    test('debug is fully suppressed in silent mode (no delegate)', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.debug('silent debug');
      expect(printer.entries, isEmpty);
    });

    test('info is fully suppressed in silent mode (no delegate)', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.info('silent info');
      expect(printer.entries, isEmpty);
    });
  });

  // ── Mode: enabled ─────────────────────────────────────────────────────────

  group('mode enabled', () {
    test('all log levels produce output', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.enabled),
      );

      scoped.trace('t');
      scoped.debug('d');
      scoped.info('i');
      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');

      // 6 log calls should produce 6 entries
      expect(printer.entries, hasLength(6));
    });

    test('stopwatch produces output', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.enabled),
      );

      final sw = Stopwatch()..start();
      sw.stop();
      scoped.stopwatch('perf', sw);

      expect(printer.entries, hasLength(1));
    });
  });

  // ── Mutable mode toggling ─────────────────────────────────────────────────

  group('mutable mode toggling', () {
    test('mode is initialized from options', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );
      expect(scoped.mode, equals(LogMode.silent));
    });

    test('mode can be changed at runtime', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.enabled),
      );

      scoped.info('before toggle');
      expect(printer.entries, hasLength(1));

      scoped.mode = LogMode.disabled;
      scoped.info('after disable');
      expect(printer.entries, hasLength(1)); // still 1

      scoped.mode = LogMode.enabled;
      scoped.info('re-enabled');
      expect(printer.entries, hasLength(2));
    });

    test('toggling to silent suppresses output but fires delegates', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.enabled),
      );

      scoped.warning('visible');
      expect(printer.entries, hasLength(1));

      scoped.mode = LogMode.silent;
      scoped.warning('invisible but delegated');
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1)); // no new printer output
      expect(crash.logs, hasLength(2)); // both warnings hit delegate
    });

    test('toggling from disabled to enabled starts producing output', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.disabled),
      );

      scoped.info('suppressed');
      expect(printer.entries, isEmpty);

      scoped.mode = LogMode.enabled;
      scoped.info('visible');
      expect(printer.entries, hasLength(1));
    });
  });

  // ── Tag prefixing ─────────────────────────────────────────────────────────

  group('tag prefixing', () {
    test('tag is prepended as [tag] to all messages', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: 'auth'),
      );

      scoped.info('login');
      scoped.debug('token');
      scoped.warning('expired');
      scoped.error('failed');
      scoped.fatal('crash');
      scoped.trace('deep');

      for (final entry in printer.entries) {
        expect(entry.message, contains('[auth]'));
      }
    });

    test('null tag does not prepend anything', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: null),
      );

      scoped.info('plain');
      expect(printer.entries.first.message, isNot(contains('[')));
    });

    test('empty string tag is still prepended', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: ''),
      );

      scoped.info('empty tag');
      expect(printer.entries.first.message, contains('[]'));
    });

    test('tag is applied to stopwatch messages', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: 'perf'),
      );

      scoped.stopwatch('query', Stopwatch()..stop());

      expect(printer.entries.first.message, contains('[perf]'));
    });

    test('tag is applied in silent mode delegate calls', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: 'billing', mode: LogMode.silent),
      );

      scoped.warning('overdue');
      scoped.error('payment failed');
      scoped.fatal('system down');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs.first, contains('[billing]'));
      expect(crash.errors[0].$4, contains('[billing]'));
      expect(crash.errors[1].$4, contains('[billing]'));
    });
  });

  // ── minLevel filtering ────────────────────────────────────────────────────

  group('minLevel filtering', () {
    test('minLevel: trace allows everything', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.trace),
      );

      scoped.trace('t');
      scoped.debug('d');
      scoped.info('i');
      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');

      expect(printer.entries, hasLength(6));
    });

    test('minLevel: debug filters trace', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.debug),
      );

      scoped.trace('filtered');
      scoped.debug('visible');
      scoped.info('visible');

      expect(printer.entries, hasLength(2));
    });

    test('minLevel: info filters trace and debug', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.info),
      );

      scoped.trace('filtered');
      scoped.debug('filtered');
      scoped.info('visible');
      scoped.warning('visible');

      expect(printer.entries, hasLength(2));
    });

    test('minLevel: warning filters trace, debug, info', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.warning),
      );

      scoped.trace('filtered');
      scoped.debug('filtered');
      scoped.info('filtered');
      scoped.warning('visible');
      scoped.error('visible');
      scoped.fatal('visible');

      expect(printer.entries, hasLength(3));
    });

    test('minLevel: error filters everything below error', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.error),
      );

      scoped.trace('filtered');
      scoped.debug('filtered');
      scoped.info('filtered');
      scoped.warning('filtered');
      scoped.error('visible');
      scoped.fatal('visible');

      expect(printer.entries, hasLength(2));
    });

    test('minLevel: fatal only allows fatal', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.fatal),
      );

      scoped.trace('filtered');
      scoped.debug('filtered');
      scoped.info('filtered');
      scoped.warning('filtered');
      scoped.error('filtered');
      scoped.fatal('visible');

      expect(printer.entries, hasLength(1));
    });

    test('minLevel null means no per-wrapper filtering', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: null),
      );

      scoped.trace('t');
      scoped.debug('d');
      scoped.info('i');
      scoped.warning('w');
      scoped.error('e');
      scoped.fatal('f');

      expect(printer.entries, hasLength(6));
    });

    test('minLevel also suppresses delegates for filtered levels', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.fatal),
      );

      scoped.warning('suppressed');
      scoped.error('suppressed');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, isEmpty);
      expect(crash.errors, isEmpty);
    });

    test('minLevel filters stopwatch (logs at info level)', () {
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(minLevel: LogLevel.warning),
      );

      scoped.stopwatch('suppressed', Stopwatch());
      expect(printer.entries, isEmpty);
    });
  });

  // ── skipCrashReporting ────────────────────────────────────────────────────

  group('skipCrashReporting', () {
    test('default is false — error fires crash reporting', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(skipCrashReporting: false),
      );

      scoped.error('reported');
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
    });

    test('true suppresses crash reporting on error', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(skipCrashReporting: true),
      );

      scoped.error('not reported');
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, isEmpty);
    });

    test('per-call override: false on options, true on call', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(skipCrashReporting: false),
      );

      scoped.error('skipped at call site', skipCrashReporting: true);
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, isEmpty);
    });

    test('per-call override: true on options, false on call', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(skipCrashReporting: true),
      );

      scoped.error('reported anyway', skipCrashReporting: false);
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
    });

    test('skipCrashReporting does not affect fatal (always reports)', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      // Note: fatal() in ScopedLogger does NOT have a skipCrashReporting
      // parameter. It always reports.
      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(skipCrashReporting: true),
      );

      scoped.fatal('always reports');
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isTrue); // fatal
    });
  });

  // ── Cache behavior ────────────────────────────────────────────────────────

  group('cache', () {
    test('same options and type return same instance', () {
      final a = HyperLogger.withOptions<String>(tag: 'x');
      final b = HyperLogger.withOptions<String>(tag: 'x');
      expect(identical(a, b), isTrue);
    });

    test('different options return different instances', () {
      final a = HyperLogger.withOptions<String>(tag: 'a');
      final b = HyperLogger.withOptions<String>(tag: 'b');
      expect(identical(a, b), isFalse);
    });

    test('different types return different instances', () {
      final a = HyperLogger.withOptions<_MyService>(tag: 'x');
      final b = HyperLogger.withOptions<_OtherService>(tag: 'x');
      expect(identical(a, b), isFalse);
    });

    test('fromOptions uses the same cache as withOptions', () {
      final a = HyperLogger.withOptions<String>(
        tag: 'shared',
        mode: LogMode.enabled,
      );
      final b = HyperLogger.fromOptions<String>(
        const LoggerOptions(tag: 'shared', mode: LogMode.enabled),
      );
      expect(identical(a, b), isTrue);
    });

    test('different mode produces different cache entry', () {
      final a = HyperLogger.withOptions<String>(mode: LogMode.enabled);
      final b = HyperLogger.withOptions<String>(mode: LogMode.silent);
      expect(identical(a, b), isFalse);
    });

    test('different minLevel produces different cache entry', () {
      final a = HyperLogger.withOptions<String>(minLevel: LogLevel.info);
      final b = HyperLogger.withOptions<String>(minLevel: LogLevel.warning);
      expect(identical(a, b), isFalse);
    });

    test('different skipCrashReporting produces different cache entry', () {
      final a = HyperLogger.withOptions<String>(skipCrashReporting: true);
      final b = HyperLogger.withOptions<String>(skipCrashReporting: false);
      expect(identical(a, b), isFalse);
    });
  });

  // ── trace() and fatal() ───────────────────────────────────────────────────

  group('trace and fatal', () {
    test('trace produces output at FINEST level', () {
      final scoped = ScopedLogger<String>(options: const LoggerOptions());

      scoped.trace('very fine');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.trace));
    });

    test('trace with data and method', () {
      final scoped = ScopedLogger<String>(options: const LoggerOptions());

      scoped.trace('with extras', data: {'key': 1}, method: 'myMethod');
      expect(printer.entries, hasLength(1));
    });

    test('fatal produces output at SHOUT level', () {
      final scoped = ScopedLogger<String>(options: const LoggerOptions());

      scoped.fatal('critical');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.fatal));
    });

    test('fatal with exception and stack trace', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(options: const LoggerOptions());

      final ex = Exception('critical failure');
      final st = StackTrace.current;
      scoped.fatal('system down', exception: ex, stackTrace: st);
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1));
      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$1, equals(ex));
      expect(crash.errors.first.$2, equals(st));
      expect(crash.errors.first.$3, isTrue); // fatal
    });
  });

  // ── Silent mode delegate dispatch for specific levels ─────────────────────

  group('silent mode delegate dispatch (detailed)', () {
    test('warning in silent mode sends tagged message to crash log', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(tag: 'net', mode: LogMode.silent),
      );

      scoped.warning('timeout');
      await Future<void>.delayed(Duration.zero);

      expect(crash.logs, hasLength(1));
      expect(crash.logs.first, equals('[net] timeout'));
    });

    test(
      'error in silent mode sends to recordError with tagged reason',
      () async {
        final crash = _RecordingCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);

        final scoped = ScopedLogger<String>(
          options: const LoggerOptions(tag: 'db', mode: LogMode.silent),
        );

        final ex = Exception('connection lost');
        final st = StackTrace.current;
        scoped.error('query failed', exception: ex, stackTrace: st);
        await Future<void>.delayed(Duration.zero);

        expect(crash.errors, hasLength(1));
        expect(crash.errors.first.$1, equals(ex));
        expect(crash.errors.first.$2, equals(st));
        expect(crash.errors.first.$3, isFalse);
        expect(crash.errors.first.$4, equals('[db] query failed'));
      },
    );

    test(
      'error in silent mode uses tagged message as error when no exception',
      () async {
        final crash = _RecordingCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);

        final scoped = ScopedLogger<String>(
          options: const LoggerOptions(tag: 'svc', mode: LogMode.silent),
        );

        scoped.error('generic error');
        await Future<void>.delayed(Duration.zero);

        expect(crash.errors.first.$1, equals('[svc] generic error'));
      },
    );

    test('fatal in silent mode sends to recordError with fatal=true', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final scoped = ScopedLogger<String>(
        options: const LoggerOptions(mode: LogMode.silent),
      );

      scoped.fatal('catastrophe', exception: Exception('oom'));
      await Future<void>.delayed(Duration.zero);

      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isTrue);
    });
  });
}
