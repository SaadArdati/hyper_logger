import 'dart:convert';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/extraction/caller_extractor.dart';
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a minimal [LogEntry] from the supplied values.
LogEntry _record({
  String message = '',
  Object? object,
  Object? error,
  StackTrace? stackTrace,
  LogLevel level = LogLevel.info,
}) {
  return LogEntry(
    level: level,
    message: message,
    object: object,
    loggerName: 'test.logger',
    time: DateTime.now(),
    error: error,
    stackTrace: stackTrace,
  );
}

/// An object whose [toString] always throws, useful for testing fallback paths.
class _ThrowingToString {
  @override
  String toString() => throw StateError('poison toString');
}

/// A Map wrapper whose JSON encoding fails (because it contains a value
/// whose toString() throws, causing the toEncodable callback to throw)
/// but whose own [toString] returns a safe fallback string.
class _PoisonMap implements Map<String, Object> {
  final _inner = <String, Object>{'bad': _ThrowingToString()};

  // -- Delegate core Map methods to _inner --
  @override
  Object? operator [](Object? key) => _inner[key];
  @override
  void operator []=(String key, Object value) => _inner[key] = value;
  @override
  void addAll(Map<String, Object> other) => _inner.addAll(other);
  @override
  void addEntries(Iterable<MapEntry<String, Object>> entries) =>
      _inner.addEntries(entries);
  @override
  Map<RK, RV> cast<RK, RV>() => _inner.cast<RK, RV>();
  @override
  void clear() => _inner.clear();
  @override
  bool containsKey(Object? key) => _inner.containsKey(key);
  @override
  bool containsValue(Object? value) => _inner.containsValue(value);
  @override
  Iterable<MapEntry<String, Object>> get entries => _inner.entries;
  @override
  void forEach(void Function(String, Object) action) => _inner.forEach(action);
  @override
  bool get isEmpty => _inner.isEmpty;
  @override
  bool get isNotEmpty => _inner.isNotEmpty;
  @override
  Iterable<String> get keys => _inner.keys;
  @override
  int get length => _inner.length;
  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(String, Object) convert) =>
      _inner.map(convert);
  @override
  Object putIfAbsent(String key, Object Function() ifAbsent) =>
      _inner.putIfAbsent(key, ifAbsent);
  @override
  Object? remove(Object? key) => _inner.remove(key);
  @override
  void removeWhere(bool Function(String, Object) test) =>
      _inner.removeWhere(test);
  @override
  Object update(
    String key,
    Object Function(Object) update, {
    Object Function()? ifAbsent,
  }) => _inner.update(key, update, ifAbsent: ifAbsent);
  @override
  void updateAll(Object Function(String, Object) update) =>
      _inner.updateAll(update);
  @override
  Iterable<Object> get values => _inner.values;

  @override
  String toString() => 'PoisonMap(fallback)';
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
      final record = _record(message: 'warn', level: LogLevel.warning);

      final result = ext.extract(record);

      expect(result.level, equals(LogLevel.warning));
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
      // CallerExtractor may or may not find a frame in test context,
      // but the result must always contain the message section and be coherent.
      final ext = _extractor();
      final msg = LogMessage(
        'msg',
        String,
        callerStackTrace: StackTrace.current,
      );
      final record = _record(object: msg);

      final result = ext.extract(record);

      // The message section must always be present with the original text.
      final msgSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.message,
      );
      expect(msgSection.lines, equals(['msg']));

      // className should be 'String' (from LogMessage.type).
      expect(result.className, equals('String'));

      // CallerExtractor may or may not resolve a methodName from the stack,
      // but at least one of className or methodName must be non-null since
      // we provided a valid Type and a real stack trace.
      expect(
        result.className != null || result.methodName != null,
        isTrue,
        reason: 'at least className or methodName should be resolved',
      );
    });

    test('className and methodName are null for plain string records', () {
      final ext = _extractor();
      final record = _record(message: 'plain');

      final result = ext.extract(record);

      expect(result.className, isNull);
      expect(result.methodName, isNull);
    });

    // ── _formatData exception fallback ─────────────────────────────────────

    test('_formatData does not crash when data throws on JSON encoding', () {
      // _PoisonMap is a Map (so _formatData enters the JSON branch)
      // containing a value whose toString() throws. The JSON encoder's
      // toEncodable callback invokes toString() on that value, which throws,
      // causing convert() to throw. The catch block then calls
      // data.toString() on the _PoisonMap itself, which returns a safe string.
      final ext = _extractor();

      final poisonData = LogMessage('msg', String, data: _PoisonMap());
      final record = _record(object: poisonData);

      // Should not throw — the catch block in _formatData handles the failure.
      final result = ext.extract(record);
      final dataSection = result.sections.firstWhere(
        (s) => s.kind == SectionKind.data,
      );
      expect(dataSection.lines, equals(['PoisonMap(fallback)']));
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
