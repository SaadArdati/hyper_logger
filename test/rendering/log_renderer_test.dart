import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ── Test doubles ───────────────────────────────────────────────────────────────

/// A StyleResolver subclass that records which className / methodName it saw
/// and lets the test configure border/section style behaviour.
class _CapturingResolver extends StyleResolver {
  final bool withBox;

  String? capturedClassName;
  String? capturedMethodName;

  _CapturingResolver({this.withBox = false});

  @override
  ResolvedBorderStyle resolveBorder(LogStyle style, LogLevel level) {
    if (!withBox) return const ResolvedBorderStyle.none();
    return const ResolvedBorderStyle(
      topBorder: '┌top┐',
      bottomBorder: '└bot┘',
      divider: '├div┤',
    );
  }

  @override
  ResolvedSectionStyle resolve({
    required LogStyle style,
    required SectionKind kind,
    required LogLevel level,
    String? className,
    String? methodName,
  }) {
    capturedClassName = className;
    capturedMethodName = methodName;
    return const ResolvedSectionStyle(
      linePrefix: '',
      emojiPrefix: null,
      bracketPrefix: null,
      textColor: null,
      bgColor: null,
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

ExtractionResult _extraction({
  List<LogSection> sections = const [],
  String? className,
  String? methodName,
  LogLevel level = LogLevel.info,
  DateTime? time,
}) => ExtractionResult(
  sections: sections,
  level: level,
  time: time ?? DateTime(2026, 4, 1, 12, 0, 0),
  className: className,
  methodName: methodName,
);

final _renderer = LogRenderer(sectionRenderer: const SectionRenderer());

// ──────────────────────────────────────────────────────────────────────────────

void main() {
  group('LogRenderer.render', () {
    // ── No box ────────────────────────────────────────────────────────────────

    test('simple message without box returns only the message lines', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()..box = false;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello world']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result, ['hello world']);
    });

    test('multi-line message without box returns all lines, no borders', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()..box = false;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['line1', 'line2', 'line3']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result, ['line1', 'line2', 'line3']);
    });

    test('no dividers inserted between sections when not boxed', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()..box = false;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['msg']),
          const LogSection(SectionKind.data, ['data']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      // Exactly 2 lines — no divider between them.
      expect(result, hasLength(2));
      expect(result, ['msg', 'data']);
    });

    // ── With box ──────────────────────────────────────────────────────────────

    test('with box: top border is first line', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result.first, startsWith('┌'));
    });

    test('with box: bottom border is last line', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result.last, startsWith('└'));
    });

    test('with box, single section: layout is top | content | bottom', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['msg']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result, ['┌top┐', 'msg', '└bot┘']);
    });

    // ── Dividers between sections ─────────────────────────────────────────────

    test('divider inserted between two sections when boxed', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['msg']),
          const LogSection(SectionKind.data, ['dat']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      // Expected: top, msg, divider, dat, bottom
      expect(result, ['┌top┐', 'msg', '├div┤', 'dat', '└bot┘']);
    });

    test('divider inserted between every adjacent pair of sections', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['m']),
          const LogSection(SectionKind.data, ['d']),
          const LogSection(SectionKind.error, ['e']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      // top + m + div + d + div + e + bottom = 7 items
      expect(result, hasLength(7));
      expect(result[2], startsWith('├'));
      expect(result[4], startsWith('├'));
    });

    test('no divider after last section', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['a']),
          const LogSection(SectionKind.data, ['b']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      // Second-to-last is 'b', last is bottom border.
      expect(result[result.length - 2], 'b');
      expect(result.last, startsWith('└'));
    });

    // ── Section ordering ──────────────────────────────────────────────────────

    test('sections appear in order they were supplied', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()..box = false;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['first']),
          const LogSection(SectionKind.data, ['second']),
          const LogSection(SectionKind.error, ['third']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result, ['first', 'second', 'third']);
    });

    // ── className / methodName passed to resolver ─────────────────────────────

    test('className is passed through to resolver.resolve', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle();
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hi']),
        ],
        className: 'MyService',
      );

      _renderer.render(extraction, style, resolver);

      expect(resolver.capturedClassName, 'MyService');
    });

    test('methodName is passed through to resolver.resolve', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle();
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hi']),
        ],
        methodName: 'doWork',
      );

      _renderer.render(extraction, style, resolver);

      expect(resolver.capturedMethodName, 'doWork');
    });

    test('null className and methodName are passed as null', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle();
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hi']),
        ],
      );

      _renderer.render(extraction, style, resolver);

      expect(resolver.capturedClassName, isNull);
      expect(resolver.capturedMethodName, isNull);
    });

    // ── Empty extraction ──────────────────────────────────────────────────────

    test('empty sections without box returns empty list', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()..box = false;
      final extraction = _extraction(sections: []);

      final result = _renderer.render(extraction, style, resolver);

      expect(result, isEmpty);
    });

    test('empty sections with box returns only top and bottom borders', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()..box = true;
      final extraction = _extraction(sections: []);

      final result = _renderer.render(extraction, style, resolver);

      expect(result, ['┌top┐', '└bot┘']);
    });
  });

  // ── Timestamp rendering ──────────────────────────────────────────────────

  group('Timestamp rendering', () {
    test('boxed timestamp appears as its own section before message', () {
      final resolver = _CapturingResolver(withBox: true);
      final style = LogStyle()
        ..box = true
        ..timestamp = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello']),
        ],
        time: DateTime(2026, 4, 1, 12, 0, 0),
      );

      final result = _renderer.render(extraction, style, resolver);

      // Layout: top, timestamp line, divider, message, bottom
      expect(result.first, startsWith('┌'));
      expect(result.last, startsWith('└'));
      // The timestamp section should be between the top border and the divider.
      // result[1] is the timestamp line, result[2] is the divider.
      expect(result[1], contains('[INFO]'));
      expect(result[2], startsWith('├'));
      expect(result[3], 'hello');
    });

    test('inline timestamp is prepended to the first line when box=false', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()
        ..box = false
        ..timestamp = true;
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello']),
        ],
        time: DateTime(2026, 4, 1, 12, 0, 0),
      );

      final result = _renderer.render(extraction, style, resolver);

      // The first (and only) line should start with the timestamp.
      expect(result, hasLength(1));
      expect(result[0], contains('[INFO]'));
      expect(result[0], contains('hello'));
    });

    test('custom dateTimeFormatter is used in timestamp', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()
        ..box = false
        ..timestamp = true
        ..dateTimeFormatter = (dt) => 'CUSTOM_TIME';
      final extraction = _extraction(
        sections: [
          const LogSection(SectionKind.message, ['hello']),
        ],
      );

      final result = _renderer.render(extraction, style, resolver);

      expect(result[0], startsWith('CUSTOM_TIME'));
    });

    test('timestamp contains [LEVEL] label tag', () {
      final resolver = _CapturingResolver(withBox: false);
      final style = LogStyle()
        ..box = false
        ..timestamp = true;

      for (final level in LogLevel.values) {
        final extraction = _extraction(
          sections: [
            const LogSection(SectionKind.message, ['msg']),
          ],
          level: level,
        );

        final result = _renderer.render(extraction, style, resolver);

        expect(
          result[0],
          contains('[${level.label}]'),
          reason: '$level should produce [${level.label}] in timestamp',
        );
      }
    });
  });
}
