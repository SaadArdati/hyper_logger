import 'package:clock/clock.dart';
import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

class _RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void log(LogEntry entry) => entries.add(entry);

  @override
  void dispose() {}
}

LogMessage? _msg(LogEntry e) {
  final o = e.object;
  return o is LogMessage ? o : null;
}

void main() {
  late _RecordingPrinter printer;

  setUp(() {
    HyperLogger.reset();
    printer = _RecordingPrinter();
    HyperLogger.init(printer: printer);
  });

  tearDown(() => HyperLogger.reset());

  group('ScopedLogger context', () {
    test('default ScopedLogger has empty context', () {
      final logger = ScopedLogger<String>(options: LoggerOptions.defaults);
      expect(logger.context, isEmpty);
    });

    test('constructor copies context (mutating the source does not leak)', () {
      final source = <String, Object?>{'a': 1};
      final logger = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: source,
      );
      source['b'] = 2;
      expect(logger.context, equals({'a': 1}));
    });

    test('context flows through to LogMessage on info()', () {
      final logger = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'requestId': 'REQ-1'},
      );
      logger.info('hello');

      expect(printer.entries, hasLength(1));
      final msg = _msg(printer.entries.single)!;
      expect(msg.context, equals({'requestId': 'REQ-1'}));
    });

    test('empty context does not allocate a wrapper map on the message', () {
      final logger = ScopedLogger<String>(options: LoggerOptions.defaults);
      logger.info('hello');

      final msg = _msg(printer.entries.single)!;
      expect(msg.context, isNull);
    });

    test('mutating context after construction is visible on next log', () {
      final logger = ScopedLogger<String>(options: LoggerOptions.defaults);
      logger.context['userId'] = 'user_1';
      logger.info('after mutation');

      final msg = _msg(printer.entries.single)!;
      expect(msg.context, equals({'userId': 'user_1'}));
    });
  });

  group('ScopedLogger.child()', () {
    test('returns a fresh instance, not the parent', () {
      final parent = ScopedLogger<String>(options: LoggerOptions.defaults);
      final child = parent.child();
      expect(child, isNot(same(parent)));
    });

    test('child inherits parent context', () {
      final parent = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'requestId': 'REQ-1'},
      );
      final child = parent.child();
      expect(child.context, equals({'requestId': 'REQ-1'}));
    });

    test('child merges new context with parent context', () {
      final parent = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'requestId': 'REQ-1'},
      );
      final child = parent.child(context: {'userId': 'U-1'});
      expect(child.context, equals({'requestId': 'REQ-1', 'userId': 'U-1'}));
    });

    test("child overrides parent's keys with the same name", () {
      final parent = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'env': 'staging'},
      );
      final child = parent.child(context: {'env': 'prod'});
      expect(child.context['env'], equals('prod'));
    });

    test('mutating child context does not affect parent', () {
      final parent = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'a': 1},
      );
      final child = parent.child();
      child.context['b'] = 2;

      expect(parent.context, equals({'a': 1}));
      expect(child.context, equals({'a': 1, 'b': 2}));
    });

    test('child shares the same options as parent (tag, level, mode)', () {
      final parent = ScopedLogger<String>(
        options: const LoggerOptions(
          tag: 'svc',
          minLevel: LogLevel.warning,
        ),
      );
      final child = parent.child(context: {'requestId': 'R'});
      expect(child.options, same(parent.options));
    });

    test("child inherits parent's runtime-mutated mode (not options.mode)", () {
      final parent = ScopedLogger<String>(options: LoggerOptions.defaults);
      // Mutate at runtime — options.mode is still LogMode.enabled.
      parent.mode = LogMode.silent;

      final child = parent.child(context: {'requestId': 'R'});
      expect(child.mode, equals(LogMode.silent));

      // And the child must actually respect it: silent should suppress
      // printer output (it still allows crash-reporting delegates, but
      // we have none attached here, so the printer must stay empty).
      child.info('should be silent');
      expect(printer.entries, isEmpty);
    });

    test('mutating child mode does not affect parent', () {
      final parent = ScopedLogger<String>(options: LoggerOptions.defaults);
      final child = parent.child();
      child.mode = LogMode.silent;
      expect(parent.mode, equals(LogMode.enabled));
    });

    test('nested children compose context across all ancestors', () {
      final root = ScopedLogger<String>(
        options: LoggerOptions.defaults,
        context: {'env': 'prod'},
      );
      final mid = root.child(context: {'requestId': 'R'});
      final leaf = mid.child(context: {'userId': 'U'});

      expect(
        leaf.context,
        equals({'env': 'prod', 'requestId': 'R', 'userId': 'U'}),
      );
    });
  });

  group('HyperLogger.child<T>()', () {
    test('returns a ScopedLogger<T> with provided context', () {
      final logger = HyperLogger.child<int>(context: {'requestId': 'R'});
      expect(logger.context, equals({'requestId': 'R'}));
    });

    test('logs flow through with context attached', () {
      final logger = HyperLogger.child<int>(context: {'requestId': 'R'});
      logger.info('hello');

      final msg = _msg(printer.entries.single)!;
      expect(msg.context, equals({'requestId': 'R'}));
    });

    test('does not cache (each call returns a new instance)', () {
      final a = HyperLogger.child<int>(context: {'requestId': 'A'});
      final b = HyperLogger.child<int>(context: {'requestId': 'B'});
      expect(a, isNot(same(b)));
    });

    test('accepts tag and minLevel like withOptions', () {
      final logger = HyperLogger.child<int>(
        tag: 'api',
        minLevel: LogLevel.warning,
        context: {'requestId': 'R'},
      );
      expect(logger.options.tag, equals('api'));
      expect(logger.options.minLevel, equals(LogLevel.warning));

      logger.debug('dropped');
      logger.warning('passes');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.single.message, contains('passes'));
      expect(printer.entries.single.message, contains('[api]'));
    });

    test('accepts a complete LoggerOptions object', () {
      final logger = HyperLogger.child<int>(
        options: const LoggerOptions(tag: 'override', mode: LogMode.silent),
      );
      expect(logger.options.tag, equals('override'));
      expect(logger.mode, equals(LogMode.silent));
    });

    test(
      'mixing options and inline params asserts in debug mode '
      '(silent ignore in release)',
      () {
        // Dart `assert(...)` only fires in debug mode (which is what
        // `dart test` runs by default). The contract: passing both
        // `options` and any inline knob throws so the user catches the
        // bug before shipping.
        expect(
          () => HyperLogger.child<int>(
            options: const LoggerOptions(),
            tag: 'inline-tag',
          ),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => HyperLogger.child<int>(
            options: const LoggerOptions(),
            mode: LogMode.silent,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });

  group('clock.now() flows end-to-end', () {
    test('withClock(...) controls LogEntry.time through HyperLogger.info<T>',
        () {
      final fakeNow = DateTime.utc(2030, 1, 1, 9, 30);
      withClock(Clock.fixed(fakeNow), () {
        HyperLogger.info<String>('hello');
      });
      expect(printer.entries.single.time, equals(fakeNow));
    });
  });

  group('Mixin.child()', () {
    test('with no scopedLogger, falls back to HyperLogger.child<T>', () {
      final host = _PlainHost();
      final logger = host.child(context: {'requestId': 'R'});
      expect(logger.context, equals({'requestId': 'R'}));
    });

    test("with scopedLogger, calls the scoped logger's child()", () {
      final scoped = ScopedLogger<_HostType>(
        options: LoggerOptions.defaults,
        context: {'env': 'prod'},
      );
      final host = _ScopedHost(scoped);
      final child = host.child(context: {'requestId': 'R'});

      expect(child.context, equals({'env': 'prod', 'requestId': 'R'}));
    });

    test('plain host accepts tag/minLevel/mode (parity with static child)',
        () {
      final host = _PlainHost();
      final logger = host.child(
        tag: 'mixin-tag',
        minLevel: LogLevel.warning,
        context: {'requestId': 'R'},
      );
      // Plain host falls back to HyperLogger.child<T>, which respects
      // these inline knobs. Verify by exercising the level filter.
      logger.debug('dropped');
      logger.warning('passes');
      expect(printer.entries, hasLength(1));
      expect(printer.entries.single.message, contains('passes'));
      expect(printer.entries.single.message, contains('[mixin-tag]'));
    });

    test(
      "scoped host: passing inline knobs throws AssertionError in debug",
      () {
        // The host owns its own configuration; the mixin's `child()`
        // can't override it. Round-4 fix: instead of silently ignoring
        // the inline knobs, debug builds assert so the bug is caught
        // at write time. context-only is still allowed.
        final scoped = ScopedLogger<_HostType>(
          options: const LoggerOptions(tag: 'host-tag'),
        );
        final host = _ScopedHost(scoped);

        expect(
          () => host.child(tag: 'IGNORED'),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => host.child(minLevel: LogLevel.error),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => host.child(mode: LogMode.silent),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => host.child(skipCrashReporting: true),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => host.child(options: const LoggerOptions()),
          throwsA(isA<AssertionError>()),
        );

        // context-only call still works and inherits host-tag.
        final logger = host.child(context: {'requestId': 'R'});
        logger.info('hi');
        expect(printer.entries.single.message, contains('[host-tag]'));
      },
    );

    test(
      "scoped host: explicit `mode: LogMode.enabled` is the documented "
      'carve-out (default-value slip-through)',
      () {
        // The mixin assert is value-based, so passing the literal default
        // mode (`LogMode.enabled`) alongside a scoped host does NOT
        // trip the assert — the runtime can't distinguish "explicit
        // default" from "not passed". This test pins the carve-out.
        final scoped = ScopedLogger<_HostType>(
          options: const LoggerOptions(tag: 'host-tag'),
        );
        final host = _ScopedHost(scoped);
        expect(
          () => host.child(mode: LogMode.enabled),
          returnsNormally,
        );
      },
    );
  });

  group('HyperLogger statics with context:', () {
    test('info<T>(context:) attaches context to LogMessage', () {
      HyperLogger.info<String>('hi', context: {'k': 'v'});
      expect(_msg(printer.entries.single)!.context, equals({'k': 'v'}));
    });

    test('error<T>(context:) attaches context', () {
      HyperLogger.error<String>('e', context: {'requestId': 'R'});
      expect(_msg(printer.entries.single)!.context, equals({'requestId': 'R'}));
    });
  });

  group('Cloud printers render context', () {
    test('GcpJsonPrinter merges context fields at the JSON root', () {
      final captured = <String>[];
      final p = GcpJsonPrinter(output: captured.add);
      final msg = LogMessage('hi', String, context: {'requestId': 'R'});
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'hi',
        object: msg,
        loggerName: 'test',
        time: DateTime(2026, 1, 1),
      );
      p.log(entry);
      expect(captured.single, contains('"requestId":"R"'));
    });

    test('AwsJsonPrinter merges context fields at the JSON root', () {
      final captured = <String>[];
      final p = AwsJsonPrinter(output: captured.add);
      final msg = LogMessage('hi', String, context: {'requestId': 'R'});
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'hi',
        object: msg,
        loggerName: 'test',
        time: DateTime(2026, 1, 1),
      );
      p.log(entry);
      expect(captured.single, contains('"requestId":"R"'));
    });
  });
}

class _HostType {}

class _PlainHost with HyperLoggerMixin<_HostType> {}

class _ScopedHost with HyperLoggerMixin<_HostType> {
  final ScopedLoggerApi<_HostType> _scoped;
  _ScopedHost(this._scoped);

  @override
  ScopedLoggerApi<_HostType>? get scopedLogger => _scoped;
}
