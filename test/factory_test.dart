import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ── Dummy types for generic parameter testing ───────────────────────────────

class _ServiceA {}

class _ServiceB {}

class _ServiceC {}

// ── Test doubles ────────────────────────────────────────────────────────────

class _RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void log(LogEntry entry) {
    entries.add(entry);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    HyperLogger.reset();
    HyperLogger.init(printer: _RecordingPrinter());
  });

  tearDown(() {
    HyperLogger.reset();
  });

  // ── withOptions ───────────────────────────────────────────────────────────

  group('withOptions', () {
    test('creates ScopedLogger with default options', () {
      final scoped = HyperLogger.withOptions<_ServiceA>();

      expect(scoped, isA<ScopedLogger<_ServiceA>>());
      expect(scoped.options.mode, equals(LogMode.enabled));
      expect(scoped.options.minLevel, isNull);
      expect(scoped.options.tag, isNull);
      expect(scoped.options.skipCrashReporting, isFalse);
    });

    test('creates ScopedLogger with custom mode', () {
      final scoped = HyperLogger.withOptions<_ServiceA>(mode: LogMode.silent);

      expect(scoped.options.mode, equals(LogMode.silent));
      expect(scoped.mode, equals(LogMode.silent));
    });

    test('creates ScopedLogger with custom minLevel', () {
      final scoped = HyperLogger.withOptions<_ServiceA>(
        minLevel: LogLevel.warning,
      );

      expect(scoped.options.minLevel, equals(LogLevel.warning));
    });

    test('creates ScopedLogger with custom tag', () {
      final scoped = HyperLogger.withOptions<_ServiceA>(tag: 'auth');

      expect(scoped.options.tag, equals('auth'));
    });

    test('creates ScopedLogger with skipCrashReporting', () {
      final scoped = HyperLogger.withOptions<_ServiceA>(
        skipCrashReporting: true,
      );

      expect(scoped.options.skipCrashReporting, isTrue);
    });

    test('creates ScopedLogger with all custom options', () {
      final scoped = HyperLogger.withOptions<_ServiceA>(
        mode: LogMode.disabled,
        minLevel: LogLevel.error,
        tag: 'billing',
        skipCrashReporting: true,
      );

      expect(scoped.options.mode, equals(LogMode.disabled));
      expect(scoped.options.minLevel, equals(LogLevel.error));
      expect(scoped.options.tag, equals('billing'));
      expect(scoped.options.skipCrashReporting, isTrue);
    });
  });

  // ── fromOptions ───────────────────────────────────────────────────────────

  group('fromOptions', () {
    test('uses the provided LoggerOptions object', () {
      const opts = LoggerOptions(
        mode: LogMode.silent,
        minLevel: LogLevel.info,
        tag: 'custom',
        skipCrashReporting: true,
      );

      final scoped = HyperLogger.fromOptions<_ServiceA>(opts);

      expect(scoped.options, equals(opts));
      expect(scoped.options.mode, equals(LogMode.silent));
      expect(scoped.options.minLevel, equals(LogLevel.info));
      expect(scoped.options.tag, equals('custom'));
      expect(scoped.options.skipCrashReporting, isTrue);
    });

    test('uses default LoggerOptions', () {
      final scoped = HyperLogger.fromOptions<_ServiceA>(LoggerOptions.defaults);

      expect(scoped.options, equals(const LoggerOptions()));
    });
  });

  // ── Cache key generation ──────────────────────────────────────────────────

  group('LoggerOptions.cacheKey', () {
    test('includes type name', () {
      const opts = LoggerOptions();
      final key = opts.cacheKey('MyType');
      expect(key, startsWith('MyType|'));
    });

    test('includes mode', () {
      const opts = LoggerOptions(mode: LogMode.disabled);
      final key = opts.cacheKey('T');
      expect(key, contains('m=disabled'));
    });

    test('includes minLevel when set', () {
      const opts = LoggerOptions(minLevel: LogLevel.warning);
      final key = opts.cacheKey('T');
      expect(key, contains('l=warning'));
    });

    test('includes null for missing minLevel', () {
      const opts = LoggerOptions();
      final key = opts.cacheKey('T');
      expect(key, contains('l=null'));
    });

    test('includes tag when set', () {
      const opts = LoggerOptions(tag: 'auth');
      final key = opts.cacheKey('T');
      expect(key, contains('t=auth'));
    });

    test('includes null for missing tag', () {
      const opts = LoggerOptions();
      final key = opts.cacheKey('T');
      expect(key, contains('t=null'));
    });

    test('includes skipCrashReporting', () {
      const opts = LoggerOptions(skipCrashReporting: true);
      final key = opts.cacheKey('T');
      expect(key, contains('s=true'));
    });

    test('different type names produce different keys', () {
      const opts = LoggerOptions();
      expect(opts.cacheKey('A'), isNot(equals(opts.cacheKey('B'))));
    });

    test('same options different types are different keys', () {
      const opts = LoggerOptions(tag: 'x');
      expect(
        opts.cacheKey('ServiceA'),
        isNot(equals(opts.cacheKey('ServiceB'))),
      );
    });

    test('different options same type are different keys', () {
      const a = LoggerOptions(tag: 'auth');
      const b = LoggerOptions(tag: 'billing');
      expect(a.cacheKey('T'), isNot(equals(b.cacheKey('T'))));
    });

    test('identical options same type produce identical keys', () {
      const a = LoggerOptions(tag: 'auth', mode: LogMode.silent);
      const b = LoggerOptions(tag: 'auth', mode: LogMode.silent);
      expect(a.cacheKey('Service'), equals(b.cacheKey('Service')));
    });
  });

  // ── Cache: same args return same instance ─────────────────────────────────

  group('same args return same instance', () {
    test('withOptions with identical params returns cached instance', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'x');
      final b = HyperLogger.withOptions<_ServiceA>(tag: 'x');
      expect(identical(a, b), isTrue);
    });

    test('fromOptions with equal objects returns cached instance', () {
      const optsA = LoggerOptions(tag: 'y');
      const optsB = LoggerOptions(tag: 'y');
      // Verify the options are equal but not identical (const may make
      // them identical, but the cache still works via key matching).
      final a = HyperLogger.fromOptions<_ServiceA>(optsA);
      final b = HyperLogger.fromOptions<_ServiceA>(optsB);
      expect(identical(a, b), isTrue);
    });

    test('withOptions and fromOptions share the same cache', () {
      final a = HyperLogger.withOptions<_ServiceA>(
        tag: 'shared',
        mode: LogMode.enabled,
        skipCrashReporting: false,
      );
      final b = HyperLogger.fromOptions<_ServiceA>(
        const LoggerOptions(
          tag: 'shared',
          mode: LogMode.enabled,
          skipCrashReporting: false,
        ),
      );
      expect(identical(a, b), isTrue);
    });

    test('repeated calls do not create new instances', () {
      final instances = <ScopedLogger<_ServiceA>>[];
      for (var i = 0; i < 10; i++) {
        instances.add(HyperLogger.withOptions<_ServiceA>(tag: 'stable'));
      }

      // All should be the exact same instance.
      for (var i = 1; i < instances.length; i++) {
        expect(identical(instances[i], instances[0]), isTrue);
      }
    });
  });

  // ── Cache: different args return different instances ───────────────────────

  group('different args return different instances', () {
    test('different types', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'x');
      final b = HyperLogger.withOptions<_ServiceB>(tag: 'x');
      expect(identical(a, b), isFalse);
    });

    test('different modes', () {
      final a = HyperLogger.withOptions<_ServiceA>(mode: LogMode.enabled);
      final b = HyperLogger.withOptions<_ServiceA>(mode: LogMode.disabled);
      expect(identical(a, b), isFalse);
    });

    test('different minLevels', () {
      final a = HyperLogger.withOptions<_ServiceA>(minLevel: LogLevel.info);
      final b = HyperLogger.withOptions<_ServiceA>(minLevel: LogLevel.error);
      expect(identical(a, b), isFalse);
    });

    test('null vs non-null minLevel', () {
      final a = HyperLogger.withOptions<_ServiceA>(minLevel: null);
      final b = HyperLogger.withOptions<_ServiceA>(minLevel: LogLevel.trace);
      expect(identical(a, b), isFalse);
    });

    test('different tags', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'auth');
      final b = HyperLogger.withOptions<_ServiceA>(tag: 'billing');
      expect(identical(a, b), isFalse);
    });

    test('null vs non-null tag', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: null);
      final b = HyperLogger.withOptions<_ServiceA>(tag: 'set');
      expect(identical(a, b), isFalse);
    });

    test('different skipCrashReporting', () {
      final a = HyperLogger.withOptions<_ServiceA>(skipCrashReporting: true);
      final b = HyperLogger.withOptions<_ServiceA>(skipCrashReporting: false);
      expect(identical(a, b), isFalse);
    });

    test('all options different at once', () {
      final a = HyperLogger.withOptions<_ServiceA>(
        mode: LogMode.enabled,
        minLevel: LogLevel.trace,
        tag: 'a',
        skipCrashReporting: false,
      );
      final b = HyperLogger.withOptions<_ServiceB>(
        mode: LogMode.disabled,
        minLevel: LogLevel.fatal,
        tag: 'b',
        skipCrashReporting: true,
      );
      expect(identical(a, b), isFalse);
    });
  });

  // ── Cache survives re-init (with same maxCacheSize) ───────────────────────

  group('cache lifecycle', () {
    test('cache survives re-init with same maxCacheSize', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'persistent');

      // Re-init with same default cache size.
      HyperLogger.init(printer: _RecordingPrinter());

      final b = HyperLogger.withOptions<_ServiceA>(tag: 'persistent');
      expect(identical(a, b), isTrue);
    });

    test('cache is cleared on reset()', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'reset-test');

      HyperLogger.reset();
      HyperLogger.init(printer: _RecordingPrinter());

      final b = HyperLogger.withOptions<_ServiceA>(tag: 'reset-test');
      expect(identical(a, b), isFalse);
    });

    test('cache is cleared when maxCacheSize changes', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'size-change');

      HyperLogger.init(printer: _RecordingPrinter(), maxCacheSize: 128);

      final b = HyperLogger.withOptions<_ServiceA>(tag: 'size-change');
      expect(identical(a, b), isFalse);
    });
  });

  // ── Multiple types and options coexistence ────────────────────────────────

  group('multiple cached instances coexist', () {
    test('three different type+option combos return three instances', () {
      final a = HyperLogger.withOptions<_ServiceA>(tag: 'a');
      final b = HyperLogger.withOptions<_ServiceB>(tag: 'b');
      final c = HyperLogger.withOptions<_ServiceC>(tag: 'c');

      expect(identical(a, b), isFalse);
      expect(identical(b, c), isFalse);
      expect(identical(a, c), isFalse);

      // Verify they're all still retrievable.
      expect(
        identical(HyperLogger.withOptions<_ServiceA>(tag: 'a'), a),
        isTrue,
      );
      expect(
        identical(HyperLogger.withOptions<_ServiceB>(tag: 'b'), b),
        isTrue,
      );
      expect(
        identical(HyperLogger.withOptions<_ServiceC>(tag: 'c'), c),
        isTrue,
      );
    });

    test('same type with different tags coexist', () {
      final auth = HyperLogger.withOptions<_ServiceA>(tag: 'auth');
      final billing = HyperLogger.withOptions<_ServiceA>(tag: 'billing');
      final general = HyperLogger.withOptions<_ServiceA>();

      expect(identical(auth, billing), isFalse);
      expect(identical(auth, general), isFalse);
      expect(identical(billing, general), isFalse);
    });
  });
}
