import 'package:hyper_logger/hyper_logger.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Synthetic frames — a real `StackTrace.current` varies by platform and
/// test runner, which would make frame counts unstable.
final _frames = [
  Frame(Uri.parse('package:app/a.dart'), 1, 1, 'A.one'),
  Frame(Uri.parse('package:app/b.dart'), 2, 1, 'B.two'),
  Frame(Uri.parse('package:noisy/c.dart'), 3, 1, 'C.three'),
  Frame(Uri.parse('package:app/d.dart'), 4, 1, 'D.four'),
];

Chain _chain(List<Frame> frames) => Chain([Trace(frames)]);

/// A two-[Trace] chain — the shape `showAsyncGaps` acts on.
Chain _twoTraceChain() =>
    Chain([Trace(_frames.take(2).toList()), Trace(_frames.skip(2).toList())]);

/// The rendered `#N  member  library  line:col` rows of a formatted entry.
/// Matched anywhere in the line so boxed output (which prefixes each row
/// with a border glyph) counts the same as plain output.
final _framePattern = RegExp(r'#\d+\s');

List<String> _frameLines(String formatted) =>
    formatted.split('\n').where(_framePattern.hasMatch).toList();

/// Builds a minimal [LogEntry].
LogEntry _record({
  String? message,
  Object? object,
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stackTrace,
  String? loggerName,
}) {
  return LogEntry(
    level: level,
    message:
        message ?? (object is LogMessage ? object.message : 'test message'),
    object: object,
    loggerName:
        loggerName ??
        (object is LogMessage ? object.type.toString() : 'test.logger'),
    time: DateTime.now(),
    error: error,
    stackTrace: stackTrace,
  );
}

/// Runs [printer.format] and returns the joined lines.
String _format(ComposablePrinter printer, LogEntry entry) {
  return printer.format(entry).join('\n');
}

// ── Stub decorator that records apply() calls ─────────────────────────────────

class _TrackingDecorator extends LogDecorator {
  int applyCalls = 0;
  final void Function(LogStyle) action;

  _TrackingDecorator(this.action);

  @override
  void apply(LogStyle style) {
    applyCalls++;
    action(style);
  }
}

final class _ThrowingStackTrace implements StackTrace {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls++;
    throw StateError('stack trace must not be inspected');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ComposablePrinter construction', () {
    test('constructs successfully with empty decorator list', () {
      expect(() => ComposablePrinter(const []), returnsNormally);
    });

    test('style is not null after construction', () {
      final printer = ComposablePrinter(const []);
      // ignore: unnecessary_null_comparison — verifying late field is set
      expect(printer.style, isNotNull);
    });

    test('decorators applied exactly once during construction', () {
      int count = 0;
      final d = _TrackingDecorator((s) => count++);

      ComposablePrinter([d]);

      expect(d.applyCalls, 1);
    });

    test('decorator writes its flag into style', () {
      final printer = ComposablePrinter([
        _TrackingDecorator((s) => s.box = true),
      ]);
      expect(printer.style.box, isTrue);
    });

    test('multiple decorators all applied; style reflects all flags', () {
      final printer = ComposablePrinter([
        _TrackingDecorator((s) => s.box = true),
        _TrackingDecorator((s) => s.emoji = true),
        _TrackingDecorator((s) => s.ansiColors = true),
      ]);
      expect(printer.style.box, isTrue);
      expect(printer.style.emoji, isTrue);
      expect(printer.style.ansiColors, isTrue);
    });

    test('decorators applied in list order', () {
      final order = <int>[];
      final printer = ComposablePrinter([
        _TrackingDecorator((_) => order.add(1)),
        _TrackingDecorator((_) => order.add(2)),
        _TrackingDecorator((_) => order.add(3)),
      ]);
      expect(printer.style, isNotNull); // ensure construction ran
      expect(order, [1, 2, 3]);
    });
  });

  // ── format() ────────────────────────────────────────────────────────────────

  group('ComposablePrinter.format()', () {
    test('returns non-empty list for simple record', () {
      final printer = ComposablePrinter(const []);
      final result = printer.format(_record(message: 'hello'));
      expect(result, isNotEmpty);
    });

    test('output contains the message text', () {
      final printer = ComposablePrinter(const []);
      final result = _format(printer, _record(message: 'hello world'));
      expect(result, contains('hello world'));
    });

    test('format() for LogMessage with emoji+prefix includes message text', () {
      final printer = ComposablePrinter(const [
        EmojiDecorator(),
        PrefixDecorator(),
      ]);
      final msg = LogMessage('structured message', String, method: 'doWork');
      final result = _format(printer, _record(object: msg));
      expect(result, contains('structured message'));
    });

    test('format() for LogMessage includes className bracket prefix', () {
      final printer = ComposablePrinter(const [PrefixDecorator()]);
      // LogStyle.prefix defaults to true; PrefixDecorator is redundant but explicit.
      final msg = LogMessage('msg', String, method: 'run');
      final result = _format(printer, _record(object: msg));
      expect(result, contains('[String.run]'));
    });

    test('returns List<String> — each element is a single line', () {
      final printer = ComposablePrinter(const []);
      final lines = printer.format(_record(message: 'line1\nline2'));
      // Multi-line messages are split; none of the returned strings contains
      // an embedded newline from the split itself.
      for (final line in lines) {
        expect(line.contains('\n'), isFalse);
      }
    });

    test('log() calls output once per line returned by format()', () {
      final captured = <String>[];
      final printer = ComposablePrinter(const [], output: captured.add);
      final record = _record(message: 'hello');
      final expectedLines = printer.format(record);

      // Reset captured after the format() call above (format doesn't emit).
      captured.clear();
      printer.log(record);

      expect(captured, hasLength(expectedLines.length));
    });

    test('decorator order does not change produced output', () {
      // Both orderings should produce the same rendered lines because each
      // decorator owns disjoint LogStyle flags.
      final printerAB = ComposablePrinter(const [
        EmojiDecorator(),
        PrefixDecorator(),
      ]);
      final printerBA = ComposablePrinter(const [
        PrefixDecorator(),
        EmojiDecorator(),
      ]);

      final msg = LogMessage('hello', String, method: 'go');
      final record = _record(object: msg);

      expect(printerAB.format(record), printerBA.format(record));
    });
  });

  // ── Presets ──────────────────────────────────────────────────────────────────

  group('ComposablePrinter presets', () {
    test('terminal() preset has box=true', () {
      final p = LogPrinterPresets.terminal();
      expect(p.style.box, isTrue);
    });

    test('terminal() preset has emoji=true', () {
      final p = LogPrinterPresets.terminal();
      expect(p.style.emoji, isTrue);
    });

    test('terminal() preset has ansiColors=true', () {
      final p = LogPrinterPresets.terminal();
      expect(p.style.ansiColors, isTrue);
    });

    test('terminal() preset has prefix=true', () {
      final p = LogPrinterPresets.terminal();
      expect(p.style.prefix, isTrue);
    });

    test('ci() preset has prefix=true', () {
      final p = LogPrinterPresets.ci();
      expect(p.style.prefix, isTrue);
    });

    test('ci() preset has timestamp=true', () {
      final p = LogPrinterPresets.ci();
      expect(p.style.timestamp, isTrue);
    });

    test('ci() preset has box=false', () {
      final p = LogPrinterPresets.ci();
      expect(p.style.box, isFalse);
    });

    test('ci() preset has ansiColors=false', () {
      final p = LogPrinterPresets.ci();
      expect(p.style.ansiColors, isFalse);
    });

    test('human(ansi+tty) has the full real-terminal style', () {
      final p = LogPrinterPresets.human(
        const TerminalCapabilities(ansi: true, tty: true),
      );
      expect(p.style.emoji, isTrue);
      expect(p.style.box, isTrue);
      expect(p.style.ansiColors, isTrue);
      expect(p.style.prefix, isTrue);
    });

    test('human(ansi only, no tty) skips box but keeps color', () {
      // The IDE Run Console shape — ANSI is supported but stdout is a
      // pipe with unknown column width, so box drawing is unsafe.
      final p = LogPrinterPresets.human(
        const TerminalCapabilities(ansi: true, tty: false),
      );
      expect(p.style.emoji, isTrue);
      expect(p.style.box, isFalse);
      expect(p.style.ansiColors, isTrue);
      expect(p.style.prefix, isTrue);
    });

    test('human(no ansi, no tty) emits inline timestamps', () {
      // Pipe-to-file / low-feature shell — no ANSI means no host UI
      // tracking time, so the timestamp must travel inline.
      final p = LogPrinterPresets.human(
        const TerminalCapabilities(ansi: false, tty: false),
      );
      expect(p.style.emoji, isTrue);
      expect(p.style.box, isFalse);
      expect(p.style.ansiColors, isFalse);
      expect(p.style.prefix, isTrue);
      expect(p.style.timestamp, isTrue);
    });

    test('human(no ansi but tty) emits timestamps without color', () {
      // Rare: a real TTY without ANSI support (basic shell). No color
      // means no host UI per row, so timestamps inline.
      final p = LogPrinterPresets.human(
        const TerminalCapabilities(ansi: false, tty: true),
      );
      expect(p.style.ansiColors, isFalse);
      expect(p.style.box, isFalse);
      expect(p.style.timestamp, isTrue);
    });

    test('preset output callback is forwarded', () {
      final captured = <String>[];
      final p = LogPrinterPresets.terminal(output: captured.add);
      p.log(_record(message: 'from preset'));
      expect(captured, isNotEmpty);
      expect(captured.any((l) => l.contains('from preset')), isTrue);
    });
  });

  // ── Preset → ComposablePrinter parameter forwarding ──────────────────────────

  // Every ComposablePrinter tuning knob is a plain pass-through, so the
  // failure mode is a silently-dropped argument rather than a crash.
  // These assert the observable effect of each one through a preset.
  group('preset tuning parameters reach the extraction pipeline', () {
    test('methodCount: 0 suppresses the stack-trace section', () {
      final p = LogPrinterPresets.ci(methodCount: 0);
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(out, isNot(contains('#0')));
    });

    test('methodCount: 0 never inspects the stack trace on first use', () {
      final stackTrace = _ThrowingStackTrace();
      final p = ComposablePrinter(const [], methodCount: 0);
      final entry = _record(
        object: const LogMessage('failed', String, method: 'run'),
        error: StateError('failed'),
        stackTrace: stackTrace,
      );

      expect(() => p.format(entry), returnsNormally);
      expect(stackTrace.toStringCalls, 0);
    });

    test('methodCount caps the frames rendered', () {
      final p = LogPrinterPresets.ci(methodCount: 2);
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(_frameLines(out), hasLength(2));
    });

    test('errorMethodCount applies when the entry carries an error', () {
      final p = LogPrinterPresets.ci(methodCount: 1, errorMethodCount: 3);
      final out = _format(
        p,
        _record(error: 'boom', stackTrace: _chain(_frames)),
      );
      expect(_frameLines(out), hasLength(3));
    });

    test('errorMethodCount is ignored for a non-error entry', () {
      final p = LogPrinterPresets.ci(methodCount: 1, errorMethodCount: 3);
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(_frameLines(out), hasLength(1));
    });

    test('excludePaths drops matching frames', () {
      final p = LogPrinterPresets.ci(excludePaths: const ['package:noisy']);
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(out, isNot(contains('package:noisy/')));
      expect(out, contains('package:app/a.dart'));
    });

    test('showAsyncGaps defaults to off — traces are spliced together', () {
      final p = LogPrinterPresets.ci();
      final out = _format(p, _record(stackTrace: _twoTraceChain()));
      expect(out, isNot(contains('asynchronous gap')));
    });

    test('showAsyncGaps: true separates the traces of a chain', () {
      final p = LogPrinterPresets.ci(showAsyncGaps: true);
      final out = _format(p, _record(stackTrace: _twoTraceChain()));
      expect(out, contains('asynchronous gap'));
    });

    test('suppressTypeNames: true drops the class name from the prefix', () {
      final msg = LogMessage('hello', String, method: 'go');
      final withNames = _format(
        LogPrinterPresets.ci(suppressTypeNames: false),
        _record(object: msg),
      );
      final without = _format(
        LogPrinterPresets.ci(suppressTypeNames: true),
        _record(object: msg),
      );

      expect(withNames, contains('[String.go]'));
      expect(without, contains('[go]'));
      expect(without, isNot(contains('String')));
    });

    test('terminal() forwards tuning to the underlying human() preset', () {
      final p = LogPrinterPresets.terminal(
        methodCount: 2,
        excludePaths: const ['package:noisy'],
      );
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(out, isNot(contains('package:noisy/')));
      expect(_frameLines(out), hasLength(2));
    });

    test('human() forwards tuning', () {
      final p = LogPrinterPresets.human(
        const TerminalCapabilities(ansi: false, tty: false),
        methodCount: 1,
      );
      final out = _format(p, _record(stackTrace: _chain(_frames)));
      expect(_frameLines(out), hasLength(1));
    });
  });
}
