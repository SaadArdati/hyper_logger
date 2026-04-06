import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

void main() {
  // ── label ─────────────────────────────────────────────────────────────────

  group('LogLevel.label', () {
    test('trace label is TRACE', () {
      expect(LogLevel.trace.label, equals('TRACE'));
    });

    test('debug label is DEBUG', () {
      expect(LogLevel.debug.label, equals('DEBUG'));
    });

    test('info label is INFO', () {
      expect(LogLevel.info.label, equals('INFO'));
    });

    test('warning label is WARN', () {
      expect(LogLevel.warning.label, equals('WARN'));
    });

    test('error label is ERROR', () {
      expect(LogLevel.error.label, equals('ERROR'));
    });

    test('fatal label is FATAL', () {
      expect(LogLevel.fatal.label, equals('FATAL'));
    });

    test('all labels are non-empty', () {
      for (final level in LogLevel.values) {
        expect(
          level.label,
          isNotEmpty,
          reason: '$level label should not be empty',
        );
      }
    });

    test('all labels are uppercase', () {
      for (final level in LogLevel.values) {
        expect(
          level.label,
          equals(level.label.toUpperCase()),
          reason: '$level label should be uppercase',
        );
      }
    });
  });

  // ── emoji ─────────────────────────────────────────────────────────────────

  group('LogLevel.emoji', () {
    test('trace emoji is empty string', () {
      expect(LogLevel.trace.emoji, equals(''));
    });

    test('debug emoji is bug', () {
      expect(LogLevel.debug.emoji, equals('\u{1F41B}')); // U+1F41B
    });

    test('info emoji is lightbulb', () {
      expect(LogLevel.info.emoji, equals('\u{1F4A1}')); // U+1F4A1
    });

    test('warning emoji is warning sign', () {
      // The warning emoji is U+26A0 + U+FE0F (variation selector)
      expect(LogLevel.warning.emoji, isNotEmpty);
    });

    test('error emoji is no entry', () {
      expect(LogLevel.error.emoji, equals('\u{26D4}')); // U+26D4
    });

    test('fatal emoji is alien monster', () {
      expect(LogLevel.fatal.emoji, equals('\u{1F47E}')); // U+1F47E
    });

    test('all emojis are defined (non-null)', () {
      for (final level in LogLevel.values) {
        // emoji returns a String (possibly empty for trace), never null.
        expect(level.emoji, isA<String>());
      }
    });
  });

  // ── toLoggingLevel ────────────────────────────────────────────────────────

  group('LogLevel.toLoggingLevel()', () {
    test('trace maps to FINEST', () {
      expect(LogLevel.trace.toLoggingLevel(), equals(logging.Level.FINEST));
    });

    test('debug maps to FINE', () {
      expect(LogLevel.debug.toLoggingLevel(), equals(logging.Level.FINE));
    });

    test('info maps to INFO', () {
      expect(LogLevel.info.toLoggingLevel(), equals(logging.Level.INFO));
    });

    test('warning maps to WARNING', () {
      expect(LogLevel.warning.toLoggingLevel(), equals(logging.Level.WARNING));
    });

    test('error maps to SEVERE', () {
      expect(LogLevel.error.toLoggingLevel(), equals(logging.Level.SEVERE));
    });

    test('fatal maps to SHOUT', () {
      expect(LogLevel.fatal.toLoggingLevel(), equals(logging.Level.SHOUT));
    });
  });

  // ── fromLoggingLevel ──────────────────────────────────────────────────────

  group('LogLevel.fromLoggingLevel()', () {
    test('FINEST maps to trace', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.FINEST), LogLevel.trace);
    });

    test('FINER maps to trace (below FINE boundary)', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.FINER), LogLevel.trace);
    });

    test('FINE maps to debug', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.FINE), LogLevel.debug);
    });

    test('CONFIG maps to info (between FINE and INFO)', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.CONFIG), LogLevel.info);
    });

    test('INFO maps to info', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.INFO), LogLevel.info);
    });

    test('WARNING maps to warning', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.WARNING),
        LogLevel.warning,
      );
    });

    test('SEVERE maps to error', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.SEVERE), LogLevel.error);
    });

    test('SHOUT maps to fatal', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.SHOUT), LogLevel.fatal);
    });

    test('ALL maps to trace (value 0, below FINER)', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.ALL), LogLevel.trace);
    });

    test('OFF maps to fatal (value 2000, above SHOUT)', () {
      expect(LogLevel.fromLoggingLevel(logging.Level.OFF), LogLevel.fatal);
    });

    test('custom level between INFO and WARNING maps to warning', () {
      // INFO is 800, WARNING is 900. A level at 850 should map to warning.
      final custom = logging.Level('CUSTOM', 850);
      expect(LogLevel.fromLoggingLevel(custom), LogLevel.warning);
    });

    test('custom level between FINE and INFO maps to info', () {
      // FINE is 500, CONFIG is 700, INFO is 800.
      final custom = logging.Level('CUSTOM', 600);
      expect(LogLevel.fromLoggingLevel(custom), LogLevel.info);
    });

    test('custom level just above SEVERE maps to fatal', () {
      // SEVERE is 1000, SHOUT is 1200.
      final custom = logging.Level('CUSTOM', 1100);
      expect(LogLevel.fromLoggingLevel(custom), LogLevel.fatal);
    });
  });

  // ── roundtrip ─────────────────────────────────────────────────────────────

  group('toLoggingLevel / fromLoggingLevel roundtrip', () {
    test('all LogLevel values roundtrip correctly', () {
      for (final level in LogLevel.values) {
        final loggingLevel = level.toLoggingLevel();
        final roundTripped = LogLevel.fromLoggingLevel(loggingLevel);
        expect(
          roundTripped,
          equals(level),
          reason: '$level should roundtrip through logging.Level',
        );
      }
    });
  });

  // ── fromLoggingLevel static method ──────────────────────────────────────

  group('LogLevel.fromLoggingLevel', () {
    test('FINEST returns trace', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.FINEST),
        equals(LogLevel.trace),
      );
    });

    test('FINE returns debug', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.FINE),
        equals(LogLevel.debug),
      );
    });

    test('INFO returns info', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.INFO),
        equals(LogLevel.info),
      );
    });

    test('WARNING returns warning', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.WARNING),
        equals(LogLevel.warning),
      );
    });

    test('SEVERE returns error', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.SEVERE),
        equals(LogLevel.error),
      );
    });

    test('SHOUT returns fatal', () {
      expect(
        LogLevel.fromLoggingLevel(logging.Level.SHOUT),
        equals(LogLevel.fatal),
      );
    });
  });

  // ── compareTo ordering ────────────────────────────────────────────────────

  group('compareTo ordering', () {
    test('levels are ordered by severity (index)', () {
      expect(LogLevel.trace.compareTo(LogLevel.debug), lessThan(0));
      expect(LogLevel.debug.compareTo(LogLevel.info), lessThan(0));
      expect(LogLevel.info.compareTo(LogLevel.warning), lessThan(0));
      expect(LogLevel.warning.compareTo(LogLevel.error), lessThan(0));
      expect(LogLevel.error.compareTo(LogLevel.fatal), lessThan(0));
    });

    test('same level compareTo returns 0', () {
      for (final level in LogLevel.values) {
        expect(level.compareTo(level), equals(0));
      }
    });

    test('higher severity is greater', () {
      expect(LogLevel.fatal.compareTo(LogLevel.trace), greaterThan(0));
      expect(LogLevel.error.compareTo(LogLevel.info), greaterThan(0));
    });

    test('sorted list matches enum declaration order', () {
      final shuffled = [
        LogLevel.error,
        LogLevel.trace,
        LogLevel.fatal,
        LogLevel.info,
        LogLevel.debug,
        LogLevel.warning,
      ];
      shuffled.sort();

      expect(shuffled, equals(LogLevel.values));
    });
  });
}
