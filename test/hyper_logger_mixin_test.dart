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

/// A recording ScopedLoggerApi that logs all calls to verify delegation.
class _RecordingScopedLogger implements ScopedLoggerApi<_TestClass> {
  final List<(String, String, Object?, String?)> calls = [];

  @override
  void trace(String msg, {Object? data, String? method}) {
    calls.add(('trace', msg, data, method));
  }

  @override
  void debug(String msg, {Object? data, String? method}) {
    calls.add(('debug', msg, data, method));
  }

  @override
  void info(String msg, {Object? data, String? method}) {
    calls.add(('info', msg, data, method));
  }

  @override
  void warning(String msg, {Object? data, String? method}) {
    calls.add(('warning', msg, data, method));
  }

  @override
  void error(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool? skipCrashReporting,
  }) {
    calls.add(('error', message, data, method));
  }

  @override
  void fatal(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  }) {
    calls.add(('fatal', message, data, method));
  }

  @override
  void stopwatch(String message, Stopwatch stopwatch, {String? method}) {
    calls.add(('stopwatch', message, null, method));
  }
}

// ── Mixin hosts ─────────────────────────────────────────────────────────────

class _TestClass {}

/// Host without scopedLogger override — delegates to HyperLogger statics.
class _PlainHost with HyperLoggerMixin<_TestClass> {}

/// Host with scopedLogger override — delegates to the scoped logger.
class _ScopedHost with HyperLoggerMixin<_TestClass> {
  final ScopedLoggerApi<_TestClass> _scoped;

  _ScopedHost(this._scoped);

  @override
  ScopedLoggerApi<_TestClass> get scopedLogger => _scoped;
}

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

  // ── Without scopedLogger (fallback to HyperLogger) ────────────────────────

  group('without scopedLogger — delegates to HyperLogger', () {
    test('logTrace delegates to HyperLogger.trace', () {
      final host = _PlainHost();
      host.logTrace('trace msg');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.trace));
      expect(printer.entries.first.message, contains('trace msg'));
    });

    test('logDebug delegates to HyperLogger.debug', () {
      final host = _PlainHost();
      host.logDebug('debug msg');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.debug));
      expect(printer.entries.first.message, contains('debug msg'));
    });

    test('logInfo delegates to HyperLogger.info', () {
      final host = _PlainHost();
      host.logInfo('info msg');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.info));
      expect(printer.entries.first.message, contains('info msg'));
    });

    test('logWarning delegates to HyperLogger.warning', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final host = _PlainHost();
      host.logWarning('warning msg');
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.warning));
      expect(crash.logs, contains('warning msg'));
    });

    test('logError delegates to HyperLogger.error', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final host = _PlainHost();
      final ex = Exception('test');
      host.logError('error msg', exception: ex);
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.error));
      expect(crash.errors, hasLength(1));
    });

    test('logError with skipCrashReporting', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final host = _PlainHost();
      host.logError('skipped', skipCrashReporting: true);
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1));
      expect(crash.errors, isEmpty);
    });

    test('logFatal delegates to HyperLogger.fatal', () async {
      final crash = _RecordingCrashReporting();
      HyperLogger.attachServices(crashReporting: crash);

      final host = _PlainHost();
      host.logFatal('fatal msg', exception: Exception('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.level, equals(LogLevel.fatal));
      expect(crash.errors, hasLength(1));
      expect(crash.errors.first.$3, isTrue); // fatal
    });

    test('logStopwatch delegates to HyperLogger.stopwatch', () {
      final host = _PlainHost();
      final sw = Stopwatch()..start();
      sw.stop();
      host.logStopwatch('perf msg', sw);

      expect(printer.entries, hasLength(1));
    });

    test('uses type parameter for logger name', () {
      final host = _PlainHost();
      host.logInfo('typed');
      expect(printer.entries.first.loggerName, equals('_TestClass'));
    });

    test('passes data parameter through', () {
      final host = _PlainHost();
      host.logInfo('with data', data: {'key': 'value'});

      final logMsg = printer.entries.first.object as LogMessage;
      expect(logMsg.data, equals({'key': 'value'}));
    });

    test('passes method parameter through', () {
      final host = _PlainHost();
      host.logInfo('with method', method: 'doWork');

      final logMsg = printer.entries.first.object as LogMessage;
      expect(logMsg.method, equals('doWork'));
    });
  });

  // ── With scopedLogger ─────────────────────────────────────────────────────

  group('with scopedLogger — delegates to scoped logger', () {
    test('logTrace delegates to scopedLogger.trace', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logTrace('trace msg', data: 42, method: 'm');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('trace'));
      expect(scoped.calls.first.$2, equals('trace msg'));
      expect(scoped.calls.first.$3, equals(42));
      expect(scoped.calls.first.$4, equals('m'));
    });

    test('logDebug delegates to scopedLogger.debug', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logDebug('debug msg');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('debug'));
      expect(scoped.calls.first.$2, equals('debug msg'));
    });

    test('logInfo delegates to scopedLogger.info', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logInfo('info msg');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('info'));
    });

    test('logWarning delegates to scopedLogger.warning', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logWarning('warning msg');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('warning'));
      // Should NOT have gone to HyperLogger statics.
      expect(printer.entries, isEmpty);
    });

    test('logError delegates to scopedLogger.error', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logError('error msg');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('error'));
      expect(printer.entries, isEmpty);
    });

    test('logFatal delegates to scopedLogger.fatal', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logFatal('fatal msg');

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('fatal'));
      expect(printer.entries, isEmpty);
    });

    test('logStopwatch delegates to scopedLogger.stopwatch', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logStopwatch('perf', Stopwatch());

      expect(scoped.calls, hasLength(1));
      expect(scoped.calls.first.$1, equals('stopwatch'));
      expect(printer.entries, isEmpty);
    });

    test('all methods go through scoped logger, not HyperLogger', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);

      host.logTrace('t');
      host.logDebug('d');
      host.logInfo('i');
      host.logWarning('w');
      host.logError('e');
      host.logFatal('f');
      host.logStopwatch('s', Stopwatch());

      expect(scoped.calls, hasLength(7));
      expect(printer.entries, isEmpty); // nothing leaked to HyperLogger
    });
  });

  // ── Null scopedLogger behavior ────────────────────────────────────────────

  group('scopedLogger is null by default', () {
    test('default mixin host has null scopedLogger', () {
      final host = _PlainHost();
      expect(host.scopedLogger, isNull);
    });

    test('overridden scopedLogger is used', () {
      final scoped = _RecordingScopedLogger();
      final host = _ScopedHost(scoped);
      expect(host.scopedLogger, same(scoped));
    });
  });

  // ── With a real ScopedLogger (integration-style) ──────────────────────────

  group('with real ScopedLogger from HyperLogger.withOptions', () {
    test('mixin delegates through ScopedLogger with tag', () {
      final realScoped = HyperLogger.withOptions<_TestClass>(tag: 'mixin-test');

      // Create a host that uses the real ScopedLogger.
      final host = _ScopedHostReal(realScoped);

      host.logInfo('hello from mixin');

      expect(printer.entries, hasLength(1));
      expect(printer.entries.first.message, contains('[mixin-test] hello'));
    });
  });
}

/// Host using a real ScopedLogger (not a mock).
class _ScopedHostReal with HyperLoggerMixin<_TestClass> {
  final ScopedLogger<_TestClass> _scoped;

  _ScopedHostReal(this._scoped);

  @override
  ScopedLoggerApi<_TestClass>? get scopedLogger => _scoped;
}
