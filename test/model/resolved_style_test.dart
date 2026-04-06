import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/model/resolved_style.dart';
import 'package:test/test.dart';

// Helpers to build expected ANSI sequences without depending on AnsiColor
// internals beyond what the public API promises.
String _fg(int r, int g, int b) => '\x1b[38;2;$r;$g;${b}m';
String _bg(int r, int g, int b) => '\x1b[48;2;$r;$g;${b}m';
const String _reset = '\x1b[0m';

void main() {
  group('ResolvedSectionStyle.apply', () {
    test('returns line as-is when no formatting is set', () {
      const style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: null,
        bgColor: null,
      );
      expect(style.apply('hello'), 'hello');
    });

    test('returns empty line as-is when no formatting is set', () {
      const style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: null,
        bgColor: null,
      );
      expect(style.apply(''), '');
    });

    test('prepends linePrefix', () {
      const style = ResolvedSectionStyle(
        linePrefix: '│ ',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: null,
        bgColor: null,
      );
      expect(style.apply('hello'), '│ hello');
    });

    test('prepends emojiPrefix', () {
      const style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: '🔥 ',
        bracketPrefix: null,
        textColor: null,
        bgColor: null,
      );
      expect(style.apply('hello'), '🔥 hello');
    });

    test('prepends bracketPrefix', () {
      const style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: '[Foo] ',
        textColor: null,
        bgColor: null,
      );
      expect(style.apply('hello'), '[Foo] hello');
    });

    test('wraps with ANSI fg + reset when only textColor is set', () {
      final style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: AnsiColor.fromRGB(255, 0, 0),
        bgColor: null,
      );
      expect(style.apply('hello'), '${_fg(255, 0, 0)}hello$_reset');
    });

    test('wraps with ANSI bg + reset when only bgColor is set', () {
      final style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: null,
        bgColor: AnsiColor.fromRGB(0, 0, 255),
      );
      expect(style.apply('hello'), '${_bg(0, 0, 255)}hello$_reset');
    });

    test('wraps with ANSI bg + fg + reset when both colors set', () {
      final style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: AnsiColor.fromRGB(255, 255, 255),
        bgColor: AnsiColor.fromRGB(0, 0, 0),
      );
      expect(
        style.apply('hello'),
        '${_bg(0, 0, 0)}${_fg(255, 255, 255)}hello$_reset',
      );
    });

    test('AnsiColor.none() does not produce color output', () {
      final style = ResolvedSectionStyle(
        linePrefix: '',
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: AnsiColor.none(),
        bgColor: AnsiColor.none(),
      );
      // none colors → no ANSI wrapping, fast path
      expect(style.apply('hello'), 'hello');
    });

    test('combines all parts correctly: linePrefix outside ANSI block', () {
      final style = ResolvedSectionStyle(
        linePrefix: '│ ',
        emojiPrefix: '🔥 ',
        bracketPrefix: '[Foo] ',
        textColor: AnsiColor.fromRGB(255, 255, 255),
        bgColor: AnsiColor.fromRGB(0, 0, 0),
      );
      // Expected: linePrefix + bg + fg + emoji + bracket + text + reset
      final expected =
          '│ '
          '${_bg(0, 0, 0)}'
          '${_fg(255, 255, 255)}'
          '🔥 '
          '[Foo] '
          'hello'
          '$_reset';
      expect(style.apply('hello'), expected);
    });

    test('linePrefix with emoji but no colors — no reset emitted', () {
      const style = ResolvedSectionStyle(
        linePrefix: '  ',
        emojiPrefix: '✅ ',
        bracketPrefix: null,
        textColor: null,
        bgColor: null,
      );
      expect(style.apply('done'), '  ✅ done');
    });
  });

  group('ResolvedBorderStyle.none()', () {
    test('topBorder is null', () {
      const border = ResolvedBorderStyle.none();
      expect(border.topBorder, isNull);
    });

    test('bottomBorder is null', () {
      const border = ResolvedBorderStyle.none();
      expect(border.bottomBorder, isNull);
    });

    test('divider is null', () {
      const border = ResolvedBorderStyle.none();
      expect(border.divider, isNull);
    });
  });

  group('ResolvedBorderStyle stores values', () {
    test('topBorder is stored', () {
      const border = ResolvedBorderStyle(
        topBorder: '╔══╗',
        bottomBorder: '╚══╝',
        divider: '╠══╣',
      );
      expect(border.topBorder, '╔══╗');
    });

    test('bottomBorder is stored', () {
      const border = ResolvedBorderStyle(
        topBorder: '╔══╗',
        bottomBorder: '╚══╝',
        divider: '╠══╣',
      );
      expect(border.bottomBorder, '╚══╝');
    });

    test('divider is stored', () {
      const border = ResolvedBorderStyle(
        topBorder: '╔══╗',
        bottomBorder: '╚══╝',
        divider: '╠══╣',
      );
      expect(border.divider, '╠══╣');
    });

    test('values can be null individually', () {
      const border = ResolvedBorderStyle(
        topBorder: null,
        bottomBorder: null,
        divider: null,
      );
      expect(border.topBorder, isNull);
      expect(border.bottomBorder, isNull);
      expect(border.divider, isNull);
    });
  });
}
