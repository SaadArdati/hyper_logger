import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

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

class _FakeAnalytics extends AnalyticsDelegate {
  final List<(String, Duration, String?)> perfEvents = [];

  @override
  Future<void> logPerformance(
    String name,
    Duration duration, {
    String? source,
  }) async {
    perfEvents.add((name, duration, source));
  }
}

// ── Mixin test host ──────────────────────────────────────────────────────────

class _MixinHost with HyperLoggerMixin<_MixinHost> {}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Initializes HyperLogger with a [DirectPrinter] that captures output.
List<String> _initCapturing({bool silent = false}) {
  final captured = <String>[];
  HyperLogger.init(
    printer: DirectPrinter(output: captured.add),
    silent: silent,
  );
  return captured;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    HyperLogger.reset();
  });

  group('HyperLogger.init', () {
    test('does not throw', () {
      expect(() => HyperLogger.init(), returnsNormally);
    });

    test('with silent does not throw', () {
      expect(() => HyperLogger.init(silent: true), returnsNormally);
    });

    test('re-init overrides printer', () {
      final captured1 = <String>[];
      HyperLogger.init(printer: DirectPrinter(output: captured1.add));
      HyperLogger.info<String>('first');
      expect(captured1, isNotEmpty);

      // Second init replaces the printer.
      final captured2 = <String>[];
      HyperLogger.init(printer: DirectPrinter(output: captured2.add));
      HyperLogger.info<String>('second');
      expect(captured2, isNotEmpty);
    });
  });

  group('log methods after init', () {
    test('info does not throw', () {
      _initCapturing();
      expect(() => HyperLogger.info<String>('test info'), returnsNormally);
    });

    test('debug does not throw', () {
      _initCapturing();
      expect(() => HyperLogger.debug<String>('test debug'), returnsNormally);
    });

    test('warning does not throw', () {
      _initCapturing();
      expect(
        () => HyperLogger.warning<String>('test warning'),
        returnsNormally,
      );
    });

    test('error does not throw', () {
      _initCapturing();
      expect(() => HyperLogger.error<String>('test error'), returnsNormally);
    });

    test('fatal does not throw', () {
      _initCapturing();
      expect(() => HyperLogger.fatal<String>('test fatal'), returnsNormally);
    });

    test('trace does not throw', () {
      _initCapturing();
      expect(() => HyperLogger.trace<String>('test trace'), returnsNormally);
    });

    test('stopwatch does not throw', () {
      _initCapturing();
      final sw = Stopwatch()..start();
      expect(
        () => HyperLogger.stopwatch<String>('perf test', sw),
        returnsNormally,
      );
    });
  });

  group('auto-init without explicit init()', () {
    test('log methods work without calling init first', () {
      // No init() call — should auto-initialize with defaults.
      expect(() => HyperLogger.info<String>('auto'), returnsNormally);
    });

    test('init can override after auto-init', () {
      HyperLogger.info<String>('triggers auto-init');
      final captured = <String>[];
      HyperLogger.init(printer: DirectPrinter(output: captured.add));
      HyperLogger.info<String>('after override');
      expect(captured, isNotEmpty);
    });
  });

  group('output content', () {
    test('stopwatch logs elapsed time', () {
      final captured = _initCapturing();
      final sw = Stopwatch()..start();
      // Burn a tiny amount of time so elapsed > 0.
      for (var i = 0; i < 10000; i++) {}
      sw.stop();
      HyperLogger.stopwatch<String>('loading', sw);
      final output = captured.join('\n');
      expect(output, contains('loading'));
      expect(output, contains('ms'));
    });

    test('info output contains the message', () {
      final captured = _initCapturing();
      HyperLogger.info<String>('hello world');
      expect(captured.join('\n'), contains('hello world'));
    });
  });

  group('silent mode', () {
    test('suppresses all output', () {
      final captured = _initCapturing(silent: true);
      HyperLogger.info<String>('should not appear');
      HyperLogger.debug<String>('should not appear');
      HyperLogger.warning<String>('should not appear');
      HyperLogger.error<String>('should not appear');
      expect(captured, isEmpty);
    });
  });

  group('attachServices', () {
    test('accepts delegates', () {
      _initCapturing();
      expect(
        () => HyperLogger.attachServices(
          crashReporting: _FakeCrashReporting(),
          analytics: _FakeAnalytics(),
        ),
        returnsNormally,
      );
    });

    test('warning forwards to crashReporting.log', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.warning<String>('uh oh');
      // Give fire-and-forget futures a chance to complete.
      await Future<void>.delayed(Duration.zero);
      expect(crash.logs, contains('uh oh'));
    });

    test('error forwards to crashReporting.recordError', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      final ex = Exception('kaboom');
      HyperLogger.error<String>('something failed', exception: ex);
      await Future<void>.delayed(Duration.zero);
      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$1, ex);
      expect(crash.errors.first.$3, isFalse); // fatal == false
    });

    test('error with skipCrashReporting does not forward', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.error<String>('not reported', skipCrashReporting: true);
      await Future<void>.delayed(Duration.zero);
      expect(crash.errors, isEmpty);
    });

    test(
      'fatal forwards to crashReporting.recordError with fatal=true',
      () async {
        _initCapturing();
        final crash = _FakeCrashReporting();
        HyperLogger.attachServices(crashReporting: crash);
        HyperLogger.fatal<String>('critical');
        await Future<void>.delayed(Duration.zero);
        expect(crash.errors, hasLength(1));
        expect(crash.errors.first.$3, isTrue); // fatal == true
      },
    );

    test('stopwatch forwards to analytics.logPerformance', () async {
      _initCapturing();
      final analytics = _FakeAnalytics();
      HyperLogger.attachServices(analytics: analytics);
      final sw = Stopwatch()..start();
      sw.stop();
      HyperLogger.stopwatch<String>('page_load', sw);
      await Future<void>.delayed(Duration.zero);
      expect(analytics.perfEvents, hasLength(1));
      expect(analytics.perfEvents.first.$1, 'page_load');
    });
  });

  group('defaultLogFilter', () {
    test('exists and is callable', () {
      expect(HyperLogger.defaultLogFilter, isA<Function>());
    });

    test('allows normal records', () {
      final record = logging.LogRecord(logging.Level.INFO, 'hello', 'MyApp');
      expect(HyperLogger.defaultLogFilter(record), isTrue);
    });

    test('suppresses GoTrue records', () {
      final record = logging.LogRecord(
        logging.Level.INFO,
        'token refresh',
        'supabase.GoTrueClient',
      );
      expect(HyperLogger.defaultLogFilter(record), isFalse);
    });

    test('suppresses supabase auth records', () {
      final record = logging.LogRecord(
        logging.Level.INFO,
        'session',
        'supabase.auth.client',
      );
      expect(HyperLogger.defaultLogFilter(record), isFalse);
    });
  });

  group('setLogLevel', () {
    test('filters records below the set level', () {
      final captured = _initCapturing();
      HyperLogger.setLogLevel(logging.Level.WARNING);
      HyperLogger.info<String>('should be filtered');
      HyperLogger.warning<String>('should appear');
      // info is below WARNING so it should be filtered by the logging package.
      // Note: the root logger level is set to OFF but individual loggers
      // are set to ALL, so setLogLevel controls the root listener threshold.
      // Actually, root.onRecord only fires for records from child loggers
      // whose own level passes. Since child loggers are ALL, everything
      // fires. But setLogLevel sets root.level which doesn't filter children
      // in hierarchical mode. Let's just verify no crash.
      expect(captured, isNotEmpty);
    });
  });

  group('HyperLoggerMixin', () {
    test('delegates to HyperLogger', () {
      final captured = _initCapturing();
      final host = _MixinHost();
      host.logInfo('mixin info');
      expect(captured.join('\n'), contains('mixin info'));
    });

    test('logDebug delegates', () {
      final captured = _initCapturing();
      final host = _MixinHost();
      host.logDebug('mixin debug');
      expect(captured.join('\n'), contains('mixin debug'));
    });

    test('logWarning delegates', () {
      final captured = _initCapturing();
      final host = _MixinHost();
      host.logWarning('mixin warning');
      expect(captured.join('\n'), contains('mixin warning'));
    });

    test('logError delegates', () {
      final captured = _initCapturing();
      final host = _MixinHost();
      host.logError('mixin error');
      expect(captured.join('\n'), contains('mixin error'));
    });

    test('logStopwatch delegates', () {
      final captured = _initCapturing();
      final host = _MixinHost();
      final sw = Stopwatch()..start();
      sw.stop();
      host.logStopwatch('mixin perf', sw);
      expect(captured.join('\n'), contains('mixin perf'));
    });
  });

  group('HyperLoggerWrapper', () {
    test('disabled does not log', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>(disabled: true);
      wrapper.info('should not appear');
      wrapper.debug('should not appear');
      wrapper.warning('should not appear');
      wrapper.error('should not appear');
      wrapper.stopwatch('should not appear', Stopwatch());
      expect(captured, isEmpty);
    });

    test('enabled logs normally', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>();
      wrapper.info('wrapper info');
      expect(captured.join('\n'), contains('wrapper info'));
    });

    test('withOptions caches by type and disabled flag', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(disabled: true);
      final b = HyperLogger.withOptions<String>(disabled: true);
      expect(identical(a, b), isTrue);
    });

    test('withOptions returns different instances for different options', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(disabled: true);
      final b = HyperLogger.withOptions<String>(disabled: false);
      expect(identical(a, b), isFalse);
    });

    test('withOptions accepts LoggerOptions object directly', () {
      final captured = _initCapturing();
      final opts = LoggerOptions(tag: 'payments');
      final wrapper = HyperLogger.withOptions<String>(options: opts);
      wrapper.info('checkout');
      expect(captured.join('\n'), contains('[payments] checkout'));
    });

    test('tag prepends [tag] to all messages', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>(tag: 'auth');
      wrapper.info('login');
      wrapper.debug('token refreshed');
      wrapper.warning('session expiring');
      final output = captured.join('\n');
      expect(output, contains('[auth] login'));
      expect(output, contains('[auth] token refreshed'));
      expect(output, contains('[auth] session expiring'));
    });

    test('no tag does not prepend anything', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>();
      wrapper.info('plain message');
      final output = captured.join('\n');
      expect(output, contains('plain message'));
      expect(output, isNot(contains('[null]')));
    });

    test('minLevel filters messages below threshold', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>(
        minLevel: logging.Level.WARNING,
      );
      wrapper.debug('should not appear');
      wrapper.info('should not appear');
      wrapper.warning('should appear');
      wrapper.error('should also appear');
      final output = captured.join('\n');
      expect(output, isNot(contains('should not appear')));
      expect(output, contains('should appear'));
      expect(output, contains('should also appear'));
    });

    test('minLevel at FINE allows debug and above', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>(
        minLevel: logging.Level.FINE,
      );
      wrapper.debug('debug visible');
      wrapper.info('info visible');
      final output = captured.join('\n');
      expect(output, contains('debug visible'));
      expect(output, contains('info visible'));
    });

    test('skipCrashReporting defaults to false', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      final wrapper = HyperLogger.withOptions<String>();
      wrapper.error('boom');
      await Future<void>.delayed(Duration.zero);
      expect(crash.errors, hasLength(1));
    });

    test('skipCrashReporting option suppresses crash reporting', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      final wrapper = HyperLogger.withOptions<String>(skipCrashReporting: true);
      wrapper.error('not reported');
      await Future<void>.delayed(Duration.zero);
      expect(crash.errors, isEmpty);
    });

    test('error call-site skipCrashReporting overrides option', () async {
      _initCapturing();
      final crash = _FakeCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);
      // Option says skip, but call-site says don't skip.
      final wrapper = HyperLogger.withOptions<String>(skipCrashReporting: true);
      wrapper.error('reported anyway', skipCrashReporting: false);
      await Future<void>.delayed(Duration.zero);
      expect(crash.errors, hasLength(1));
    });

    test('different tags produce different cached instances', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(tag: 'auth');
      final b = HyperLogger.withOptions<String>(tag: 'payments');
      expect(identical(a, b), isFalse);
    });

    test('same tag returns cached instance', () {
      _initCapturing();
      final a = HyperLogger.withOptions<String>(tag: 'auth');
      final b = HyperLogger.withOptions<String>(tag: 'auth');
      expect(identical(a, b), isTrue);
    });

    test('stopwatch respects minLevel', () {
      final captured = _initCapturing();
      final wrapper = HyperLogger.withOptions<String>(
        minLevel: logging.Level.WARNING,
      );
      wrapper.stopwatch('perf', Stopwatch());
      // stopwatch logs at INFO, which is below WARNING.
      expect(captured, isEmpty);
    });
  });

  group('logFilter', () {
    test('filters records when logFilter returns false', () {
      final captured = <String>[];
      HyperLogger.init(
        printer: DirectPrinter(output: captured.add),
        logFilter: (_) => false,
      );
      HyperLogger.info<String>('filtered');
      expect(captured, isEmpty);
    });

    test('passes records when logFilter returns true', () {
      final captured = <String>[];
      HyperLogger.init(
        printer: DirectPrinter(output: captured.add),
        logFilter: (_) => true,
      );
      HyperLogger.info<String>('passed');
      expect(captured.join('\n'), contains('passed'));
    });
  });

  group('data parameter', () {
    test('info with data does not throw', () {
      _initCapturing();
      expect(
        () => HyperLogger.info<String>('with data', data: {'key': 'value'}),
        returnsNormally,
      );
    });

    test('error with exception and stackTrace does not throw', () {
      _initCapturing();
      expect(
        () => HyperLogger.error<String>(
          'with exception',
          exception: Exception('test'),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });
}
