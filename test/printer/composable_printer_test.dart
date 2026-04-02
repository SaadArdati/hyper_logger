import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a minimal [logging.LogRecord].
logging.LogRecord _record({
  String message = 'test message',
  Object? object,
  logging.Level level = logging.Level.INFO,
  Object? error,
  StackTrace? stackTrace,
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

/// Runs [printer.format] and returns the joined lines.
String _format(ComposablePrinter printer, logging.LogRecord record) {
  return printer.format(record).join('\n');
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

    test('ide() preset has emoji=true', () {
      final p = LogPrinterPresets.ide();
      expect(p.style.emoji, isTrue);
    });

    test('ide() preset has prefix=true', () {
      final p = LogPrinterPresets.ide();
      expect(p.style.prefix, isTrue);
    });

    test('ide() preset has box=false', () {
      final p = LogPrinterPresets.ide();
      expect(p.style.box, isFalse);
    });

    test('ide() preset has ansiColors=false', () {
      final p = LogPrinterPresets.ide();
      expect(p.style.ansiColors, isFalse);
    });

    test('preset output callback is forwarded', () {
      final captured = <String>[];
      final p = LogPrinterPresets.terminal(output: captured.add);
      p.log(_record(message: 'from preset'));
      expect(captured, isNotEmpty);
      expect(captured.any((l) => l.contains('from preset')), isTrue);
    });
  });
}
