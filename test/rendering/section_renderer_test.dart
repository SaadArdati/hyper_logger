import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/model/log_section.dart';
import 'package:hyper_logger/src/model/resolved_style.dart';
import 'package:hyper_logger/src/rendering/section_renderer.dart';
import 'package:test/test.dart';

// Helpers ──────────────────────────────────────────────────────────────────────

const SectionRenderer _renderer = SectionRenderer();

/// Plain style: no prefix, no emoji, no bracket, no colors.
const ResolvedSectionStyle _plain = ResolvedSectionStyle(
  linePrefix: '',
  emojiPrefix: null,
  bracketPrefix: null,
  textColor: null,
  bgColor: null,
);

ResolvedSectionStyle _styleWith({
  String linePrefix = '',
  String? emojiPrefix,
  String? bracketPrefix,
  AnsiColor? textColor,
  AnsiColor? bgColor,
}) => ResolvedSectionStyle(
  linePrefix: linePrefix,
  emojiPrefix: emojiPrefix,
  bracketPrefix: bracketPrefix,
  textColor: textColor,
  bgColor: bgColor,
);

// ──────────────────────────────────────────────────────────────────────────────

void main() {
  group('SectionRenderer.render', () {
    // ── Empty section ────────────────────────────────────────────────────────

    test('empty section returns empty list', () {
      const section = LogSection(SectionKind.message, []);
      final result = _renderer.render(section, _plain);
      expect(result, isEmpty);
    });

    // ── Single line ──────────────────────────────────────────────────────────

    test('single line with plain style returns line as-is', () {
      const section = LogSection(SectionKind.message, ['hello']);
      final result = _renderer.render(section, _plain);
      expect(result, ['hello']);
    });

    test('single line: full style applied (emoji + bracket + linePrefix)', () {
      final style = _styleWith(
        linePrefix: '│ ',
        emojiPrefix: '🔥 ',
        bracketPrefix: '[Foo] ',
      );
      const section = LogSection(SectionKind.message, ['hello']);
      final result = _renderer.render(section, style);
      expect(result, hasLength(1));
      expect(result[0], '│ 🔥 [Foo] hello');
    });

    // ── linePrefix applied to every line ────────────────────────────────────

    test('linePrefix appears on every line of a multi-line section', () {
      final style = _styleWith(linePrefix: '│ ');
      const section = LogSection(SectionKind.message, [
        'line1',
        'line2',
        'line3',
      ]);
      final result = _renderer.render(section, style);
      expect(result, hasLength(3));
      for (final line in result) {
        expect(line, startsWith('│ '));
      }
    });

    // ── Emoji prefix: first line only ────────────────────────────────────────

    test('emoji prefix appears on first line only', () {
      final style = _styleWith(emojiPrefix: '🚀 ');
      const section = LogSection(SectionKind.message, [
        'first',
        'second',
        'third',
      ]);
      final result = _renderer.render(section, style);
      expect(result, hasLength(3));
      expect(result[0], startsWith('🚀 '));
      expect(result[1], isNot(startsWith('🚀 ')));
      expect(result[2], isNot(startsWith('🚀 ')));
    });

    test('emoji prefix: continuation lines do not contain the emoji', () {
      final style = _styleWith(emojiPrefix: '✅ ');
      const section = LogSection(SectionKind.data, ['a', 'b']);
      final result = _renderer.render(section, style);
      expect(result[0], contains('✅ '));
      expect(result[1], isNot(contains('✅ ')));
    });

    // ── Bracket prefix: first line only ─────────────────────────────────────

    test('bracket prefix appears on first line only', () {
      final style = _styleWith(bracketPrefix: '[MyClass] ');
      const section = LogSection(SectionKind.message, ['first', 'second']);
      final result = _renderer.render(section, style);
      expect(result[0], startsWith('[MyClass] '));
      expect(result[1], isNot(startsWith('[MyClass] ')));
    });

    test('bracket prefix: second line content is rendered without bracket', () {
      final style = _styleWith(bracketPrefix: '[Svc] ');
      const section = LogSection(SectionKind.message, ['msg', 'continued']);
      final result = _renderer.render(section, style);
      expect(result[1], 'continued');
    });

    // ── Combination: linePrefix on all, emoji+bracket on first only ──────────

    test('linePrefix on all lines, emoji+bracket on first only', () {
      final style = _styleWith(
        linePrefix: '│ ',
        emojiPrefix: '🔥 ',
        bracketPrefix: '[X] ',
      );
      const section = LogSection(SectionKind.message, ['one', 'two', 'three']);
      final result = _renderer.render(section, style);

      expect(result[0], '│ 🔥 [X] one');
      expect(result[1], '│ two');
      expect(result[2], '│ three');
    });

    // ── ANSI colors propagate to continuation lines ──────────────────────────

    test('textColor propagates to continuation lines', () {
      // We verify indirectly: if textColor is set, the ANSI reset must appear
      // in continuation lines too.
      final color = AnsiColor.fromRGB(255, 0, 0);
      final style = _styleWith(textColor: color);
      const section = LogSection(SectionKind.message, ['first', 'second']);
      final result = _renderer.render(section, style);
      // Both lines must contain the ANSI reset character since color is active.
      expect(result[0], contains('\x1b[0m'));
      expect(result[1], contains('\x1b[0m'));
    });

    test('bgColor propagates to continuation lines', () {
      final color = AnsiColor.fromRGB(0, 0, 255);
      final style = _styleWith(bgColor: color);
      const section = LogSection(SectionKind.message, ['first', 'second']);
      final result = _renderer.render(section, style);
      expect(result[1], contains('\x1b[0m'));
    });

    // ── Result size ──────────────────────────────────────────────────────────

    test('result has exactly as many lines as section.lines', () {
      const section = LogSection(SectionKind.stackTrace, [
        'frame0',
        'frame1',
        'frame2',
        'frame3',
        'frame4',
      ]);
      final result = _renderer.render(section, _plain);
      expect(result, hasLength(section.lines.length));
    });

    // ── No mutation of input ─────────────────────────────────────────────────

    test('render returns a new list; original lines are unchanged', () {
      const lines = ['original'];
      const section = LogSection(SectionKind.message, lines);
      final result = _renderer.render(section, _plain);
      expect(result, isNot(same(lines)));
      expect(lines, ['original']); // untouched
    });
  });
}
