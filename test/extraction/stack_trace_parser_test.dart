import 'package:hyper_logger/src/extraction/stack_trace_parser.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

// Helper: builds a Frame with a given library URI, member name, line, and column.
Frame _frame(String library, String member, {int line = 1, int? column}) =>
    Frame(Uri.parse(library), line, column ?? 1, member);

// Helper: builds a Chain with a single Trace from the given frames.
Chain _singleTrace(List<Frame> frames) => Chain([Trace(frames)]);

// Helper: builds a Chain with two Traces (to test async gap handling).
Chain _twoTraces(List<Frame> first, List<Frame> second) =>
    Chain([Trace(first), Trace(second)]);

// Default parser with no filtering and methodCount=10.
StackTraceParser _parser({
  int methodCount = 10,
  int? errorMethodCount,
  List<String> excludePaths = const [],
  bool showAsyncGaps = true,
}) => StackTraceParser(
  methodCount: methodCount,
  errorMethodCount: errorMethodCount,
  excludePaths: excludePaths,
  showAsyncGaps: showAsyncGaps,
);

void main() {
  group('StackTraceParser.parse', () {
    // -------------------------------------------------------------------------
    // Null / empty input
    // -------------------------------------------------------------------------

    test('returns empty list for null stack trace', () {
      final parser = _parser();
      expect(parser.parse(null), isEmpty);
    });

    test('returns empty list for null stack trace when isError=true', () {
      final parser = _parser();
      expect(parser.parse(null, isError: true), isEmpty);
    });

    // -------------------------------------------------------------------------
    // Real StackTrace.current smoke test
    // -------------------------------------------------------------------------

    test('parses real StackTrace.current without throwing', () {
      final parser = _parser();
      expect(() => parser.parse(StackTrace.current), returnsNormally);
    });

    test('returns a list (possibly empty) from real StackTrace.current', () {
      final parser = _parser();
      final result = parser.parse(StackTrace.current);
      expect(result, isA<List<String>>());
    });

    // -------------------------------------------------------------------------
    // methodCount limiting
    // -------------------------------------------------------------------------

    test('respects methodCount limit — no more lines than methodCount', () {
      final frames = List.generate(
        20,
        (i) => _frame('package:my_app/src/foo_$i.dart', 'Foo$i.method$i'),
      );
      final chain = _singleTrace(frames);
      final parser = _parser(methodCount: 5);

      final lines = parser.parse(chain);

      // At most 5 frame lines (each frame produces one line).
      expect(lines.length, lessThanOrEqualTo(5));
    });

    test(
      'with methodCount=3 produces exactly 3 frame lines from 10-frame trace',
      () {
        final frames = List.generate(
          10,
          (i) => _frame('package:my_app/src/file.dart', 'MyClass.method$i'),
        );
        final chain = _singleTrace(frames);
        final parser = _parser(methodCount: 3);

        final lines = parser.parse(chain);

        expect(lines.length, equals(3));
      },
    );

    test('with methodCount=0 returns empty list (no frames shown)', () {
      final frames = [
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser(methodCount: 0);

      final lines = parser.parse(chain);

      expect(lines, isEmpty);
    });

    // -------------------------------------------------------------------------
    // errorMethodCount
    // -------------------------------------------------------------------------

    test('uses errorMethodCount when isError=true', () {
      final frames = List.generate(
        10,
        (i) => _frame('package:my_app/src/file.dart', 'MyClass.method$i'),
      );
      final chain = _singleTrace(frames);
      final parser = _parser(methodCount: 2, errorMethodCount: 7);

      final normalLines = parser.parse(chain);
      final errorLines = parser.parse(chain, isError: true);

      expect(normalLines.length, equals(2));
      expect(errorLines.length, equals(7));
    });

    test(
      'falls back to methodCount when errorMethodCount is null and isError=true',
      () {
        final frames = List.generate(
          10,
          (i) => _frame('package:my_app/src/file.dart', 'MyClass.method$i'),
        );
        final chain = _singleTrace(frames);
        // No errorMethodCount set — should fall back to methodCount.
        final parser = _parser(methodCount: 4, errorMethodCount: null);

        final errorLines = parser.parse(chain, isError: true);

        expect(errorLines.length, equals(4));
      },
    );

    // -------------------------------------------------------------------------
    // Frame filtering — excludePaths
    // -------------------------------------------------------------------------

    test('filters frames matching excludePaths exactly', () {
      final frames = [
        _frame('package:my_app/src/good.dart', 'Good.method'),
        _frame('package:bad_lib/src/evil.dart', 'Evil.method'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser(excludePaths: ['package:bad_lib/src/evil.dart']);

      final lines = parser.parse(chain);

      // Only the good frame should appear.
      expect(lines, hasLength(1));
      expect(lines.first, contains('Good.method'));
    });

    test('filters frames whose library starts with excludePaths entry + /', () {
      final frames = [
        _frame('package:my_app/src/good.dart', 'Good.method'),
        _frame('package:excluded/src/a.dart', 'Excluded.a'),
        _frame('package:excluded/src/b.dart', 'Excluded.b'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser(excludePaths: ['package:excluded']);

      final lines = parser.parse(chain);

      expect(lines, hasLength(1));
      expect(lines.first, contains('Good.method'));
    });

    test(
      'does not filter frames that only share a prefix but not a path boundary',
      () {
        // 'package:excluded_extra' does NOT start with 'package:excluded/'.
        final frames = [
          _frame('package:excluded_extra/src/a.dart', 'Extra.method'),
          _frame('package:my_app/src/good.dart', 'Good.method'),
        ];
        final chain = _singleTrace(frames);
        final parser = _parser(excludePaths: ['package:excluded']);

        final lines = parser.parse(chain);

        // Both frames should appear: 'package:excluded_extra' != 'package:excluded'
        // and doesn't start with 'package:excluded/'.
        expect(lines, hasLength(2));
      },
    );

    // -------------------------------------------------------------------------
    // Frame filtering — internal paths
    // -------------------------------------------------------------------------

    test('filters frames from package:logging/ (internal path)', () {
      final frames = [
        _frame('package:logging/src/logger.dart', 'Logger.log'),
        _frame('package:my_app/src/good.dart', 'Good.method'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser();

      final lines = parser.parse(chain);

      expect(lines, hasLength(1));
      expect(lines.first, contains('Good.method'));
    });

    test('filters frames from package:hyper_logger/ (internal path)', () {
      final frames = [
        _frame('package:hyper_logger/src/logger.dart', 'HyperLogger.log'),
        _frame('package:my_app/src/good.dart', 'Good.method'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser();

      final lines = parser.parse(chain);

      expect(lines, hasLength(1));
      expect(lines.first, contains('Good.method'));
    });

    test('returns empty list when all frames are internal', () {
      final frames = [
        _frame('package:logging/src/logger.dart', 'Logger.log'),
        _frame('package:hyper_logger/src/core.dart', 'Core.run'),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser();

      final lines = parser.parse(chain);

      expect(lines, isEmpty);
    });

    // -------------------------------------------------------------------------
    // Async gap separator
    // -------------------------------------------------------------------------

    test('shows async gap line between traces when showAsyncGaps=true', () {
      final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
      final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
      final chain = _twoTraces(trace1, trace2);
      final parser = _parser(showAsyncGaps: true);

      final lines = parser.parse(chain);

      final gapLines = lines
          .where((l) => l.contains('asynchronous gap'))
          .toList();
      expect(gapLines, hasLength(1));
    });

    test('async gap line contains the box-drawing characters', () {
      final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
      final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
      final chain = _twoTraces(trace1, trace2);
      final parser = _parser(showAsyncGaps: true);

      final lines = parser.parse(chain);

      final gapLine = lines.firstWhere((l) => l.contains('asynchronous gap'));
      expect(gapLine, contains('╔'));
      expect(gapLine, contains('╗'));
    });

    test('does NOT show async gap when showAsyncGaps=false', () {
      final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
      final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
      final chain = _twoTraces(trace1, trace2);
      final parser = _parser(showAsyncGaps: false);

      final lines = parser.parse(chain);

      expect(lines.any((l) => l.contains('asynchronous gap')), isFalse);
    });

    test(
      'produces correct frame lines from both traces when showAsyncGaps=true',
      () {
        final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
        final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
        final chain = _twoTraces(trace1, trace2);
        final parser = _parser(showAsyncGaps: true);

        final lines = parser.parse(chain);

        // Should include frame lines for both traces.
        final frameLines = lines.where((l) => l.startsWith('#')).toList();
        expect(frameLines, hasLength(2));
      },
    );

    // -------------------------------------------------------------------------
    // Frame numbering
    // -------------------------------------------------------------------------

    test('uses per-trace frame numbering when showAsyncGaps=true', () {
      // With two traces of 1 frame each, both should be numbered #0.
      final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
      final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
      final chain = _twoTraces(trace1, trace2);
      final parser = _parser(showAsyncGaps: true);

      final lines = parser.parse(chain);

      final frameLines = lines.where((l) => l.startsWith('#')).toList();
      // Both frames should start with '#0' (per-trace numbering).
      expect(frameLines.every((l) => l.startsWith('#0')), isTrue);
    });

    test('uses global frame numbering when showAsyncGaps=false', () {
      // Two traces of 1 frame each → global indices 0 and 1.
      final trace1 = [_frame('package:my_app/src/a.dart', 'A.methodA')];
      final trace2 = [_frame('package:my_app/src/b.dart', 'B.methodB')];
      final chain = _twoTraces(trace1, trace2);
      final parser = _parser(showAsyncGaps: false);

      final lines = parser.parse(chain);

      final frameLines = lines.where((l) => l.startsWith('#')).toList();
      expect(frameLines, hasLength(2));
      expect(frameLines[0], startsWith('#0'));
      expect(frameLines[1], startsWith('#1'));
    });

    // -------------------------------------------------------------------------
    // Multi-column aligned output
    // -------------------------------------------------------------------------

    test(
      'produces multi-column aligned output — all member columns have same width',
      () {
        // Use frames with very different member/library name lengths so alignment is visible.
        final frames = [
          _frame('package:my_app/src/short.dart', 'A.b', line: 10, column: 5),
          _frame(
            'package:my_app/src/longer_file.dart',
            'LongClassName.veryLongMethodName',
            line: 200,
            column: 15,
          ),
          _frame(
            'package:my_app/src/medium_file.dart',
            'MedClass.medMethod',
            line: 50,
            column: 3,
          ),
        ];
        final chain = _singleTrace(frames);
        final parser = _parser();

        final lines = parser.parse(chain);

        expect(lines, hasLength(3));

        // Each line starts with "#N " followed by the member column.
        // Extract the member portion start positions — the member column should
        // be padded so all library columns start at the same character offset.
        //
        // Find the position where the library segment begins by looking for the
        // longest member: 'LongClassName.veryLongMethodName' (32 chars) + 2 padding = 34.
        // Strip the "#N " prefix (variable width) and check member padding.

        // The simplest structural check: all lines should have the same length
        // for the #-prefix + member + library regions — i.e., the library column
        // always starts at the same offset within the frame text (after the counter).
        //
        // We verify by checking the member field widths are consistent:
        // line format: "#N <member_padded><library_padded><loc_padded>"
        // After "#N ", member is padRight(maxMemberWidth).
        // Extract the post-prefix segment and verify all members are same padded width.
        final countWidth = lines.length.toString().length;
        final prefixLen = '#'.length + countWidth + ' '.length; // "#N "

        // Parse out the member portion: from prefixLen to prefixLen+maxMemberWidth.
        // The widest member is 'LongClassName.veryLongMethodName' = 32 chars.
        // maxMemberWidth = 32 + 2 = 34.
        final memberSegments = lines
            .map((l) => l.substring(prefixLen))
            .toList();

        // All member segments should start with the same length of member field.
        // The widest member + padding is the key. The library for each frame starts
        // at the same offset — so all lines (after the counter prefix) have the
        // same structure. We check that the offset where 'package:' appears
        // is consistent across all lines (since library always starts with 'package:').
        final libraryOffsets = memberSegments
            .map((s) => s.indexOf('package:'))
            .toSet();
        expect(
          libraryOffsets,
          hasLength(1),
          reason:
              'All library columns should start at the same offset (multi-column alignment)',
        );
      },
    );

    test('format is #N prefix followed by member, library, location', () {
      final frames = [
        _frame(
          'package:my_app/src/foo.dart',
          'MyClass.myMethod',
          line: 42,
          column: 7,
        ),
      ];
      final chain = _singleTrace(frames);
      final parser = _parser();

      final lines = parser.parse(chain);

      expect(lines, hasLength(1));
      final line = lines.first;
      expect(line, startsWith('#'));
      expect(line, contains('MyClass.myMethod'));
      expect(line, contains('package:my_app/src/foo.dart'));
      expect(line, contains('42:7'));
    });

    test('uses <anonymous> for frames with null member', () {
      final nullMemberFrame = Frame(
        Uri.parse('package:my_app/src/anon.dart'),
        1,
        1,
        null,
      );
      final chain = _singleTrace([nullMemberFrame]);
      final parser = _parser();

      final lines = parser.parse(chain);

      expect(lines, hasLength(1));
      expect(lines.first, contains('<anonymous>'));
    });
  });
}
