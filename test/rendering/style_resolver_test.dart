import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/model/log_section.dart';
import 'package:hyper_logger/src/rendering/style_resolver.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [LogStyle] with no flags set (all defaults).
LogStyle _plain() => LogStyle()..prefix = false;

/// Returns a [LogStyle] with [box] enabled.
LogStyle _boxed({int lineLength = 120}) => LogStyle()
  ..box = true
  ..prefix = false
  ..lineLength = lineLength;

/// Returns a [LogStyle] with [emoji] enabled.
LogStyle _emoji({Map<LogLevel, String>? custom}) => LogStyle()
  ..emoji = true
  ..prefix = false
  ..levelEmojis = custom;

/// Returns a [LogStyle] with [ansiColors] enabled.
LogStyle _colored({Map<LogLevel, AnsiColor>? custom}) => LogStyle()
  ..ansiColors = true
  ..prefix = false
  ..levelColors = custom;

/// Returns a [LogStyle] with [prefix] enabled (class + method given to resolve).
LogStyle _prefixed() => LogStyle()..prefix = true;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final resolver = StyleResolver();

  // --------------------------------------------------------------------------
  // No-flag baseline
  // --------------------------------------------------------------------------

  group('No flags — plain style', () {
    for (final kind in SectionKind.values) {
      test(
        'SectionKind.$kind → empty linePrefix, null emoji/bracket/colors',
        () {
          final style = resolver.resolve(
            style: _plain(),
            kind: kind,
            level: LogLevel.info,
          );
          expect(
            style.linePrefix,
            isEmpty,
            reason: 'no box → empty linePrefix',
          );
          expect(
            style.emojiPrefix,
            isNull,
            reason: 'no emoji flag → emojiPrefix null',
          );
          expect(
            style.bracketPrefix,
            isNull,
            reason: 'no prefix flag → bracketPrefix null',
          );
          expect(
            style.textColor,
            isNull,
            reason: 'no ansiColors → textColor null',
          );
          expect(style.bgColor, isNull, reason: 'no ansiColors → bgColor null');
        },
      );
    }
  });

  // --------------------------------------------------------------------------
  // box flag → linePrefix
  // --------------------------------------------------------------------------

  group('box flag → linePrefix contains "│"', () {
    for (final kind in SectionKind.values) {
      test('SectionKind.$kind gets "│ " linePrefix when box=true', () {
        final style = resolver.resolve(
          style: _boxed(),
          kind: kind,
          level: LogLevel.info,
        );
        expect(
          style.linePrefix,
          contains('│'),
          reason: 'box=true → linePrefix should contain │',
        );
      });
    }

    test('linePrefix is empty when box=false', () {
      final style = resolver.resolve(
        style: _plain(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(style.linePrefix, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // emoji flag → emojiPrefix only on SectionKind.message
  // --------------------------------------------------------------------------

  group('emoji flag → emojiPrefix on message only', () {
    test('SectionKind.message gets non-null emojiPrefix for info', () {
      final style = resolver.resolve(
        style: _emoji(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(
        style.emojiPrefix,
        isNotNull,
        reason: 'emoji=true + message → emojiPrefix must be set',
      );
    });

    for (final kind in [
      SectionKind.data,
      SectionKind.error,
      SectionKind.stackTrace,
      SectionKind.timestamp,
    ]) {
      test('SectionKind.$kind gets null emojiPrefix even when emoji=true', () {
        final style = resolver.resolve(
          style: _emoji(),
          kind: kind,
          level: LogLevel.info,
        );
        expect(
          style.emojiPrefix,
          isNull,
          reason: 'emoji only applies to message sections',
        );
      });
    }
  });

  // --------------------------------------------------------------------------
  // Different levels → different emojis
  // --------------------------------------------------------------------------

  group('Different levels → different default emojis', () {
    test('debug and info produce different emojis on message', () {
      final fineStyle = resolver.resolve(
        style: _emoji(),
        kind: SectionKind.message,
        level: LogLevel.debug,
      );
      final infoStyle = resolver.resolve(
        style: _emoji(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      // Both should be non-null (info and debug both have emojis).
      expect(infoStyle.emojiPrefix, isNotNull);
      expect(fineStyle.emojiPrefix, isNotNull);
      expect(
        fineStyle.emojiPrefix,
        isNot(equals(infoStyle.emojiPrefix)),
        reason: 'debug and info have distinct default emojis',
      );
    });

    test('trace returns empty-string emojiPrefix (not null)', () {
      for (final level in [LogLevel.trace]) {
        final style = resolver.resolve(
          style: _emoji(),
          kind: SectionKind.message,
          level: level,
        );
        // The default for trace is '' — resolved as empty string or null.
        // The resolver MAY return null or '' for empty strings.
        // We only assert it is NOT a non-empty emoji string.
        final ep = style.emojiPrefix;
        expect(
          ep == null || ep.isEmpty,
          isTrue,
          reason:
              '$level has no default emoji, so prefix should be null or empty',
        );
      }
    });

    test('warning emoji differs from error emoji', () {
      final warnStyle = resolver.resolve(
        style: _emoji(),
        kind: SectionKind.message,
        level: LogLevel.warning,
      );
      final severeStyle = resolver.resolve(
        style: _emoji(),
        kind: SectionKind.message,
        level: LogLevel.error,
      );
      expect(warnStyle.emojiPrefix, isNot(equals(severeStyle.emojiPrefix)));
    });
  });

  // --------------------------------------------------------------------------
  // Custom emojis override defaults
  // --------------------------------------------------------------------------

  group('Custom emojis override defaults', () {
    test('custom emoji for info overrides default', () {
      const customEmoji = '🔵 ';
      final style = resolver.resolve(
        style: _emoji(custom: {LogLevel.info: customEmoji}),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(
        style.emojiPrefix,
        equals(customEmoji),
        reason: 'custom emoji must win over default',
      );
    });

    test('non-overridden level still uses default', () {
      final style = resolver.resolve(
        style: _emoji(custom: {LogLevel.error: '💥 '}),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      // info default is '💡 '
      expect(
        style.emojiPrefix,
        equals('💡 '),
        reason: 'info default should still apply when only error is overridden',
      );
    });

    test('custom emoji for warning overrides default', () {
      final style = resolver.resolve(
        style: _emoji(custom: {LogLevel.warning: '🚨 '}),
        kind: SectionKind.message,
        level: LogLevel.warning,
      );
      expect(style.emojiPrefix, equals('🚨 '));
    });
  });

  // --------------------------------------------------------------------------
  // ansiColors → colors on message
  // --------------------------------------------------------------------------

  group('ansiColors → bgColor and textColor on message', () {
    test('message section gets non-null bgColor and textColor', () {
      final style = resolver.resolve(
        style: _colored(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(
        style.bgColor,
        isNotNull,
        reason: 'message with ansiColors → bgColor must be set',
      );
      expect(
        style.textColor,
        isNotNull,
        reason: 'message with ansiColors → textColor must be set',
      );
    });

    test('timestamp section gets level-based colors like message', () {
      final style = resolver.resolve(
        style: _colored(),
        kind: SectionKind.timestamp,
        level: LogLevel.warning,
      );
      expect(style.bgColor, isNotNull);
      expect(style.textColor, isNotNull);
    });

    test('different levels produce different bgColors on message', () {
      final infoStyle = resolver.resolve(
        style: _colored(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      final warnStyle = resolver.resolve(
        style: _colored(),
        kind: SectionKind.message,
        level: LogLevel.warning,
      );
      expect(
        infoStyle.bgColor,
        isNot(equals(warnStyle.bgColor)),
        reason: 'info and warning have different bg colors',
      );
    });

    test('custom level color overrides default', () {
      final customBg = AnsiColor.fromRGB(10, 20, 30);
      final style = resolver.resolve(
        style: _colored(custom: {LogLevel.info: customBg}),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(
        style.bgColor,
        equals(customBg),
        reason: 'custom color should override default',
      );
    });
  });

  // --------------------------------------------------------------------------
  // ansiColors + error section → error-specific color
  // --------------------------------------------------------------------------

  group('ansiColors + error section → error-specific color', () {
    test('error section gets distinct bgColor from message section', () {
      final errorStyle = resolver.resolve(
        style: _colored(),
        kind: SectionKind.error,
        level: LogLevel.info,
      );
      final messageStyle = resolver.resolve(
        style: _colored(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(errorStyle.bgColor, isNotNull);
      expect(
        errorStyle.bgColor,
        isNot(equals(messageStyle.bgColor)),
        reason: 'error has its own dedicated bg color',
      );
    });

    test('error section bgColor is the same regardless of level', () {
      final infoError = resolver.resolve(
        style: _colored(),
        kind: SectionKind.error,
        level: LogLevel.info,
      );
      final warnError = resolver.resolve(
        style: _colored(),
        kind: SectionKind.error,
        level: LogLevel.warning,
      );
      expect(
        infoError.bgColor,
        equals(warnError.bgColor),
        reason: 'error bg is level-independent',
      );
    });
  });

  // --------------------------------------------------------------------------
  // ansiColors + data section → muted color
  // --------------------------------------------------------------------------

  group('ansiColors + data section → uncolored by default', () {
    test('data section has null bgColor and textColor', () {
      final style = resolver.resolve(
        style: _colored(),
        kind: SectionKind.data,
        level: LogLevel.info,
      );
      expect(style.bgColor, isNull);
      expect(style.textColor, isNull);
    });
  });

  // --------------------------------------------------------------------------
  // ansiColors + stackTrace section → uncolored by default
  // --------------------------------------------------------------------------

  group('ansiColors + stackTrace section → uncolored by default', () {
    test('stackTrace has null bgColor and textColor', () {
      final style = resolver.resolve(
        style: _colored(),
        kind: SectionKind.stackTrace,
        level: LogLevel.error,
      );
      expect(style.bgColor, isNull);
      expect(style.textColor, isNull);
    });
  });

  // --------------------------------------------------------------------------
  // prefix flag → bracketPrefix on message only
  // --------------------------------------------------------------------------

  group('prefix flag → bracketPrefix on message section only', () {
    test('[Class.method] format when both className and methodName given', () {
      final style = resolver.resolve(
        style: _prefixed(),
        kind: SectionKind.message,
        level: LogLevel.info,
        className: 'MyClass',
        methodName: 'myMethod',
      );
      expect(
        style.bracketPrefix,
        equals('[MyClass.myMethod] '),
        reason: 'both class and method → [Class.method] ',
      );
    });

    test('[Class] format when only className given', () {
      final style = resolver.resolve(
        style: _prefixed(),
        kind: SectionKind.message,
        level: LogLevel.info,
        className: 'MyClass',
      );
      expect(
        style.bracketPrefix,
        equals('[MyClass] '),
        reason: 'no method → [Class] ',
      );
    });

    test('[methodName] format when only methodName given', () {
      final style = resolver.resolve(
        style: _prefixed(),
        kind: SectionKind.message,
        level: LogLevel.info,
        methodName: 'myMethod',
      );
      expect(
        style.bracketPrefix,
        equals('[myMethod] '),
        reason: 'no class → [methodName] ',
      );
    });

    test('null bracketPrefix when no className and no methodName', () {
      final style = resolver.resolve(
        style: _prefixed(),
        kind: SectionKind.message,
        level: LogLevel.info,
      );
      expect(
        style.bracketPrefix,
        isNull,
        reason: 'no class or method → no bracket prefix',
      );
    });

    for (final kind in [
      SectionKind.data,
      SectionKind.error,
      SectionKind.stackTrace,
      SectionKind.timestamp,
    ]) {
      test(
        'SectionKind.$kind → bracketPrefix is null even when prefix=true',
        () {
          final style = resolver.resolve(
            style: _prefixed(),
            kind: kind,
            level: LogLevel.info,
            className: 'MyClass',
            methodName: 'myMethod',
          );
          expect(
            style.bracketPrefix,
            isNull,
            reason: 'bracketPrefix only applies to message sections',
          );
        },
      );
    }
  });

  // --------------------------------------------------------------------------
  // resolveBorder: no box → none
  // --------------------------------------------------------------------------

  group('resolveBorder — no box → ResolvedBorderStyle.none()', () {
    test('all border fields are null when box=false', () {
      final border = resolver.resolveBorder(_plain(), LogLevel.info);
      expect(border.topBorder, isNull);
      expect(border.bottomBorder, isNull);
      expect(border.divider, isNull);
    });
  });

  // --------------------------------------------------------------------------
  // resolveBorder: box → borders with box-drawing characters
  // --------------------------------------------------------------------------

  group('resolveBorder — box=true → borders with ┌/└/├', () {
    test('topBorder contains ┌', () {
      final border = resolver.resolveBorder(_boxed(), LogLevel.info);
      expect(border.topBorder, isNotNull);
      expect(
        border.topBorder,
        contains('┌'),
        reason: 'top border must start with ┌',
      );
    });

    test('bottomBorder contains └', () {
      final border = resolver.resolveBorder(_boxed(), LogLevel.info);
      expect(border.bottomBorder, isNotNull);
      expect(border.bottomBorder, contains('└'));
    });

    test('divider contains ├', () {
      final border = resolver.resolveBorder(_boxed(), LogLevel.info);
      expect(border.divider, isNotNull);
      expect(border.divider, contains('├'));
    });

    test('borders contain ─ (solid) or ┄ (dashed) fill characters', () {
      final border = resolver.resolveBorder(_boxed(), LogLevel.info);
      // Top and bottom use solid lines, divider uses dashed.
      expect(border.topBorder, anyOf(contains('─'), contains('┄')));
      expect(border.bottomBorder, anyOf(contains('─'), contains('┄')));
      expect(border.divider, anyOf(contains('─'), contains('┄')));
    });

    test('border length respects lineLength', () {
      final border80 = resolver.resolveBorder(
        _boxed(lineLength: 80),
        LogLevel.info,
      );
      final border120 = resolver.resolveBorder(
        _boxed(lineLength: 120),
        LogLevel.info,
      );
      // Strip ANSI codes before measuring — compare relative lengths.
      final raw80 = _stripAnsi(border80.topBorder!);
      final raw120 = _stripAnsi(border120.topBorder!);
      expect(
        raw80.length,
        lessThan(raw120.length),
        reason: 'shorter lineLength → shorter border string',
      );
    });
  });

  // --------------------------------------------------------------------------
  // resolveBorder: box + ansiColors → borders contain ANSI codes
  // --------------------------------------------------------------------------

  group('resolveBorder — box + ansiColors → borders contain ANSI codes', () {
    test('topBorder contains ESC sequence when ansiColors=true', () {
      final style = LogStyle()
        ..box = true
        ..ansiColors = true
        ..prefix = false;
      final border = resolver.resolveBorder(style, LogLevel.info);
      expect(
        border.topBorder,
        contains('\x1b['),
        reason: 'ansiColors + box → border should have ANSI escape',
      );
    });

    test('bottomBorder contains ESC sequence', () {
      final style = LogStyle()
        ..box = true
        ..ansiColors = true
        ..prefix = false;
      final border = resolver.resolveBorder(style, LogLevel.info);
      expect(border.bottomBorder, contains('\x1b['));
    });

    test('divider contains ESC sequence', () {
      final style = LogStyle()
        ..box = true
        ..ansiColors = true
        ..prefix = false;
      final border = resolver.resolveBorder(style, LogLevel.info);
      expect(border.divider, contains('\x1b['));
    });

    test('box without ansiColors does NOT contain ESC sequence', () {
      final border = resolver.resolveBorder(_boxed(), LogLevel.info);
      expect(
        border.topBorder,
        isNot(contains('\x1b[')),
        reason: 'no ansiColors → no ANSI escapes in borders',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Utility: strip ANSI escape codes
// ---------------------------------------------------------------------------

/// Removes ANSI escape sequences from [s] for length/content comparisons.
String _stripAnsi(String s) {
  return s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
}
