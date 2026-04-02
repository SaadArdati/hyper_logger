import 'dart:convert';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/extraction/caller_extractor.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a minimal [logging.LogRecord] from the supplied values.
logging.LogRecord _record({
  String message = '',
  Object? object,
  Object? error,
  StackTrace? stackTrace,
  logging.Level level = logging.Level.INFO,
}) {
  return logging.LogRecord(
    level,
    message,
    'test.logger',
    error,
    stackTrace,
    null,
    object,
  );
}

/// Constructs a [ContentExtractor] with real (but default) collaborators.
ContentExtractor _extractor() => ContentExtractor(
  stackTraceParser: const StackTraceParser(
    methodCount: 10,
    excludePaths: [],
    showAsyncGaps: false,
  ),
  callerExtractor: CallerExtractor(),
);

void main() {
  group('ContentExtractor', () {
    // ── Plain string messages ─────────────────────────────────────────────

    test('extracts simple string message → single message section', () {
      final ext = _extractor();
      final record = _record(message: 'Hello world');

      final result = ext.extract(record);

      expect(result.sections, hasLength(1));
      expect(result.sections[0].kind, equals(SectionKind.message));
      expect(result.sections[0].lines, equals(['Hello world']));
    });

    test('multi-line message produces multiple lines in message section', () {
      final ext = _extractor();
      final record = _record(message: 'line one\nline two\nline three');

      final result = ext.extract(record);

      final msg = result.sections.firstWhere(
        (s) => s.kind == SectionKind.message,
      );
      expect(msg.lines, equals(['line one', 'line two', 'line three']));
    });

    test('level is preserved in result', () {
      final ext = _extractor();
      final record = _record(message: 'warn', level: logging.Level.WARNING);

      final result = ext.extract(record);

      expect(result.level, equals(logging.Level.WARNING));
    });

    // ── LogMessage extraction ─────────────────────────────────────────────

    test('extracts LogMessage with message → message section', () {
      final ext = _extractor();
      final msg = LogMessage('Hello from LogMessage', String);
      final record = _record(object: msg);

      final result = ext.extract(record);

      final section = result.sections.firstWhere(
        (s) => s.kind == SectionKind.message,
      );
      expect(section.lines, equals(['Hello from LogMessage']));
    });

    test('extracts LogMessage with data → message + data sections', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String, data: {'key': 'value'});
      final record = _record(object: msg);

      final result = ext.extract(record);

      final kinds = result.sections.map((s) => s.kind).toList();
      expect(kinds, contains(SectionKind.message));
      expect(kinds, contains(SectionKind.data));
    });

    test('LogMessage without data → no data section', () {
      final ext = _extractor();
      final msg = LogMessage('no data', String);
      final record = _record(object: msg);

      final result = ext.extract(record);

      expect(result.sections.any((s) => s.kind == SectionKind.data), isFalse);
    });

    test('extracts className from LogMessage.type, skips dynamic', () {
      final ext = _extractor();
      final msg = LogMessage('msg', dynamic);
      final record = _record(object: msg);

      final result = ext.extract(record);

      expect(result.className, isNull);
    });

    test('extracts className from LogMessage.type, skips Object', () {
      final ext = _extractor();
      final msg = LogMessage('msg', Object);
      final record = _record(object: msg);

      final result = ext.extract(record);

      expect(result.className, isNull);
    });

    test('extracts className from LogMessage.type for a real type', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String);
      final record = _record(object: msg);

      final result = ext.extract(record);

      expect(result.className, equals('String'));
    });

    test('extracts methodName from LogMessage.method', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String, method: 'myMethod');
      final record = _record(object: msg);

      final result = ext.extract(record);

      expect(result.methodName, equals('myMethod'));
    });

    test('falls back to callerExtractor when LogMessage.method is null', () {
      // Verifies no exception is thrown and the result is coherent.
      // CallerExtractor may or may not find a frame in test context.
      final ext = _extractor();
      final msg = LogMessage(
        'msg',
        String,
        callerStackTrace: StackTrace.current,
      );
      final record = _record(object: msg);

      expect(() => ext.extract(record), returnsNormally);
    });

    test('className and methodName are null for plain string records', () {
      final ext = _extractor();
      final record = _record(message: 'plain');

      final result = ext.extract(record);

      expect(result.className, isNull);
      expect(result.methodName, isNull);
    });

    // ── Error / StackTrace sections ───────────────────────────────────────

    test('extracts error from record.error → error section', () {
      final ext = _extractor();
      final err = Exception('something went wrong');
      final record = _record(message: 'oops', error: err);

      final result = ext.extract(record);

      final kinds = result.sections.map((s) => s.kind).toList();
      expect(kinds, contains(SectionKind.error));
      final errSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.error,
      );
      expect(errSection.lines.first, contains('something went wrong'));
    });

    test('no error section when record.error is null', () {
      final ext = _extractor();
      final record = _record(message: 'fine');

      final result = ext.extract(record);

      expect(result.sections.any((s) => s.kind == SectionKind.error), isFalse);
    });

    test('extracts stack trace → stackTrace section', () {
      final ext = _extractor();
      final st = StackTrace.current;
      final record = _record(
        message: 'boom',
        error: Exception('boom'),
        stackTrace: st,
      );

      final result = ext.extract(record);

      final kinds = result.sections.map((s) => s.kind).toList();
      expect(kinds, contains(SectionKind.stackTrace));
    });

    test('stackTrace section lines are non-empty', () {
      final ext = _extractor();
      final st = StackTrace.current;
      final record = _record(message: 'trace', stackTrace: st);

      final result = ext.extract(record);

      final stSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.stackTrace,
      );
      expect(stSection.lines, isNotEmpty);
    });

    test('no stackTrace section when record.stackTrace is null', () {
      final ext = _extractor();
      final record = _record(message: 'no trace');

      final result = ext.extract(record);

      expect(
        result.sections.any((s) => s.kind == SectionKind.stackTrace),
        isFalse,
      );
    });

    // ── Section ordering ──────────────────────────────────────────────────

    test(
      'sections are in correct order: message → data → error → stackTrace',
      () {
        final ext = _extractor();
        final msg = LogMessage('msg', String, data: {'a': 1});
        final err = Exception('oh no');
        final st = StackTrace.current;
        final record = _record(object: msg, error: err, stackTrace: st);

        final result = ext.extract(record);

        final kinds = result.sections.map((s) => s.kind).toList();
        expect(kinds[0], equals(SectionKind.message));
        expect(kinds[1], equals(SectionKind.data));
        expect(kinds[2], equals(SectionKind.error));
        expect(kinds[3], equals(SectionKind.stackTrace));
      },
    );

    test('sections order without data: message → error → stackTrace', () {
      final ext = _extractor();
      final err = Exception('fail');
      final st = StackTrace.current;
      final record = _record(message: 'plain', error: err, stackTrace: st);

      final result = ext.extract(record);

      final kinds = result.sections.map((s) => s.kind).toList();
      expect(kinds[0], equals(SectionKind.message));
      expect(kinds[1], equals(SectionKind.error));
      expect(kinds[2], equals(SectionKind.stackTrace));
    });

    // ── Data formatting ───────────────────────────────────────────────────

    test('pretty-prints map data as JSON (multi-line)', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String, data: {'key': 'value', 'n': 42});
      final record = _record(object: msg);

      final result = ext.extract(record);

      final dataSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.data,
      );
      // A non-trivial map pretty-printed with indent has more than one line.
      expect(dataSection.lines.length, greaterThan(1));
      // Reassembled lines must form valid JSON.
      final joined = dataSection.lines.join('\n');
      expect(() => jsonDecode(joined), returnsNormally);
    });

    test('pretty-prints list data as JSON (multi-line)', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String, data: [1, 2, 3]);
      final record = _record(object: msg);

      final result = ext.extract(record);

      final dataSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.data,
      );
      expect(dataSection.lines.length, greaterThan(1));
    });

    test('non-collection data is formatted as single-line toString', () {
      final ext = _extractor();
      final msg = LogMessage('msg', String, data: 42);
      final record = _record(object: msg);

      final result = ext.extract(record);

      final dataSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.data,
      );
      expect(dataSection.lines, equals(['42']));
    });

    test('LogMessage multi-line message splits into multiple lines', () {
      final ext = _extractor();
      final msg = LogMessage('first\nsecond\nthird', String);
      final record = _record(object: msg);

      final result = ext.extract(record);

      final msgSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.message,
      );
      expect(msgSection.lines, equals(['first', 'second', 'third']));
    });
  });
}
