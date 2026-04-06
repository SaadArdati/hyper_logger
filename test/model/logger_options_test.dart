import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

void main() {
  group('LoggerOptions', () {
    test('defaults has all default values', () {
      const opts = LoggerOptions.defaults;
      expect(opts.mode, LogMode.enabled);
      expect(opts.minLevel, isNull);
      expect(opts.tag, isNull);
      expect(opts.skipCrashReporting, isFalse);
    });

    test('const constructor with no args matches defaults', () {
      const opts = LoggerOptions();
      expect(opts, equals(LoggerOptions.defaults));
    });

    test('equality compares all fields', () {
      const a = LoggerOptions(mode: LogMode.disabled, tag: 'x');
      const b = LoggerOptions(mode: LogMode.disabled, tag: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different mode produces inequality', () {
      const a = LoggerOptions(mode: LogMode.disabled);
      const b = LoggerOptions(mode: LogMode.enabled);
      expect(a, isNot(equals(b)));
    });

    test('different minLevel produces inequality', () {
      const a = LoggerOptions(minLevel: LogLevel.info);
      const b = LoggerOptions(minLevel: LogLevel.warning);
      expect(a, isNot(equals(b)));
    });

    test('different tag produces inequality', () {
      const a = LoggerOptions(tag: 'auth');
      const b = LoggerOptions(tag: 'payments');
      expect(a, isNot(equals(b)));
    });

    test('different skipCrashReporting produces inequality', () {
      const a = LoggerOptions(skipCrashReporting: true);
      const b = LoggerOptions(skipCrashReporting: false);
      expect(a, isNot(equals(b)));
    });

    test('cacheKey includes all fields', () {
      const opts = LoggerOptions(
        mode: LogMode.disabled,
        minLevel: LogLevel.warning,
        tag: 'auth',
        skipCrashReporting: true,
      );
      final key = opts.cacheKey('MyType');
      expect(key, contains('MyType'));
      expect(key, contains('m=disabled'));
      expect(key, contains('l=warning'));
      expect(key, contains('t=auth'));
      expect(key, contains('s=true'));
    });

    test('cacheKey differs for different options', () {
      const a = LoggerOptions(mode: LogMode.disabled);
      const b = LoggerOptions(mode: LogMode.enabled);
      expect(a.cacheKey('T'), isNot(equals(b.cacheKey('T'))));
    });

    test('cacheKey differs for different types', () {
      const opts = LoggerOptions();
      expect(opts.cacheKey('A'), isNot(equals(opts.cacheKey('B'))));
    });

    test('toString is human-readable', () {
      const opts = LoggerOptions(tag: 'test');
      final str = opts.toString();
      expect(str, contains('LoggerOptions'));
      expect(str, contains('tag: test'));
    });
  });
}
