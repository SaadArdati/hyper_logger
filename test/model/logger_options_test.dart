import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

void main() {
  group('LoggerOptions', () {
    test('defaults has all default values', () {
      const opts = LoggerOptions.defaults;
      expect(opts.disabled, isFalse);
      expect(opts.minLevel, isNull);
      expect(opts.tag, isNull);
      expect(opts.skipCrashReporting, isFalse);
      expect(opts.printer, isNull);
    });

    test('const constructor with no args matches defaults', () {
      const opts = LoggerOptions();
      expect(opts, equals(LoggerOptions.defaults));
    });

    test('equality compares all fields', () {
      const a = LoggerOptions(disabled: true, tag: 'x');
      const b = LoggerOptions(disabled: true, tag: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different disabled produces inequality', () {
      const a = LoggerOptions(disabled: true);
      const b = LoggerOptions(disabled: false);
      expect(a, isNot(equals(b)));
    });

    test('different minLevel produces inequality', () {
      const a = LoggerOptions(minLevel: logging.Level.INFO);
      const b = LoggerOptions(minLevel: logging.Level.WARNING);
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

    test('different printer produces inequality', () {
      final p1 = DirectPrinter();
      final p2 = DirectPrinter();
      final a = LoggerOptions(printer: p1);
      final b = LoggerOptions(printer: p2);
      // Different instances → not equal.
      expect(a, isNot(equals(b)));
    });

    test('same printer instance produces equality', () {
      final p = DirectPrinter();
      final a = LoggerOptions(printer: p);
      final b = LoggerOptions(printer: p);
      expect(a, equals(b));
    });

    test('cacheKey includes all fields', () {
      const opts = LoggerOptions(
        disabled: true,
        minLevel: logging.Level.WARNING,
        tag: 'auth',
        skipCrashReporting: true,
      );
      final key = opts.cacheKey('MyType');
      expect(key, contains('MyType'));
      expect(key, contains('d=true'));
      expect(key, contains('l=${logging.Level.WARNING.value}'));
      expect(key, contains('t=auth'));
      expect(key, contains('s=true'));
    });

    test('cacheKey differs for different options', () {
      const a = LoggerOptions(disabled: true);
      const b = LoggerOptions(disabled: false);
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
