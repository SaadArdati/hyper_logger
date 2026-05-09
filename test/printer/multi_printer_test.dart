import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

class _RecordingPrinter implements LogPrinter {
  final String name;
  final List<LogEntry> entries = [];
  int disposeCalls = 0;

  _RecordingPrinter(this.name);

  @override
  void log(LogEntry entry) {
    entries.add(entry);
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}

class _ThrowingPrinter implements LogPrinter {
  final Object error;
  final bool throwOnDispose;
  int logCalls = 0;
  int disposeCalls = 0;

  _ThrowingPrinter({
    this.error = 'boom',
    this.throwOnDispose = false,
  });

  @override
  void log(LogEntry entry) {
    logCalls++;
    throw error;
  }

  @override
  void dispose() {
    disposeCalls++;
    if (throwOnDispose) {
      throw 'dispose boom';
    }
  }
}

LogEntry _entry({String message = 'msg'}) {
  return LogEntry(
    level: LogLevel.info,
    message: message,
    object: null,
    loggerName: 'test',
    time: DateTime.utc(2026, 5, 9, 12, 0, 0),
  );
}

void main() {
  group('MultiPrinter.log()', () {
    test('fans an entry to every child in order', () {
      final a = _RecordingPrinter('a');
      final b = _RecordingPrinter('b');
      final c = _RecordingPrinter('c');
      final multi = MultiPrinter([a, b, c]);

      final entry = _entry(message: 'hi');
      multi.log(entry);

      expect(a.entries, [entry]);
      expect(b.entries, [entry]);
      expect(c.entries, [entry]);
    });

    test('preserves dispatch order across many entries', () {
      final received = <String>[];
      final multi = MultiPrinter([
        _OrderTrackingPrinter('first', received),
        _OrderTrackingPrinter('second', received),
        _OrderTrackingPrinter('third', received),
      ]);

      multi.log(_entry(message: 'A'));
      multi.log(_entry(message: 'B'));

      expect(received, [
        'first<-A',
        'second<-A',
        'third<-A',
        'first<-B',
        'second<-B',
        'third<-B',
      ]);
    });

    test('a throwing child does NOT prevent later children from receiving', () {
      final before = _RecordingPrinter('before');
      final boom = _ThrowingPrinter();
      final after = _RecordingPrinter('after');
      final multi = MultiPrinter([before, boom, after]);

      // Per the new aggregate-and-throw contract, log() throws after
      // the fan-out completes — but every child must still have
      // received the entry first.
      expect(() => multi.log(_entry()), throwsA(isA<MultiPrinterError>()));

      expect(before.entries, hasLength(1));
      expect(boom.logCalls, 1);
      expect(after.entries, hasLength(1),
          reason: 'after-printer must still receive when middle throws');
    });

    test('multiple throwing children are all delivered-to before the throw', () {
      final boom1 = _ThrowingPrinter(error: 'one');
      final ok = _RecordingPrinter('ok');
      final boom2 = _ThrowingPrinter(error: 'two');
      final multi = MultiPrinter([boom1, ok, boom2]);

      expect(() => multi.log(_entry()), throwsA(isA<MultiPrinterError>()));
      expect(boom1.logCalls, 1);
      expect(ok.entries, hasLength(1));
      expect(boom2.logCalls, 1);
    });

    test('all-children-OK does NOT throw', () {
      final a = _RecordingPrinter('a');
      final b = _RecordingPrinter('b');
      final multi = MultiPrinter([a, b]);

      expect(() => multi.log(_entry()), returnsNormally);
    });

    test('aggregate error carries per-child index, error, and stack trace', () {
      final boom1 = _ThrowingPrinter(error: 'one');
      final ok = _RecordingPrinter('ok');
      final boom2 = _ThrowingPrinter(error: 'two');
      final multi = MultiPrinter([boom1, ok, boom2]);

      MultiPrinterError? captured;
      try {
        multi.log(_entry());
      } on MultiPrinterError catch (e) {
        captured = e;
      }
      expect(captured, isNotNull);
      expect(captured!.childErrors, hasLength(2));
      // Order: boom1 (index 0), boom2 (index 2). ok (index 1) is absent.
      expect(captured.childErrors[0].index, 0);
      expect(captured.childErrors[0].error, 'one');
      expect(captured.childErrors[0].stackTrace, isA<StackTrace>());
      expect(captured.childErrors[1].index, 2);
      expect(captured.childErrors[1].error, 'two');
    });

    test('aggregate error toString lists every failure with its index', () {
      final boom1 = _ThrowingPrinter(error: 'one');
      final boom2 = _ThrowingPrinter(error: 'two');
      final multi = MultiPrinter([boom1, _RecordingPrinter('ok'), boom2]);

      MultiPrinterError? captured;
      try {
        multi.log(_entry());
      } on MultiPrinterError catch (e) {
        captured = e;
      }
      final s = captured!.toString();
      expect(s, contains('2 child printers threw'));
      expect(s, contains('[0] one'));
      expect(s, contains('[2] two'));
    });

    test('aggregate error childErrors list is unmodifiable', () {
      final multi = MultiPrinter([_ThrowingPrinter()]);
      MultiPrinterError? captured;
      try {
        multi.log(_entry());
      } on MultiPrinterError catch (e) {
        captured = e;
      }
      expect(
        () => captured!.childErrors.clear(),
        throwsUnsupportedError,
      );
    });

    test('singular grammar in toString when exactly one child throws', () {
      final multi = MultiPrinter([_ThrowingPrinter(error: 'solo')]);
      MultiPrinterError? captured;
      try {
        multi.log(_entry());
      } on MultiPrinterError catch (e) {
        captured = e;
      }
      expect(captured!.toString(), contains('1 child printer threw'));
    });

    test('empty list is a silent sink', () {
      final multi = MultiPrinter([]);
      expect(() => multi.log(_entry()), returnsNormally);
    });
  });

  group('MultiPrinter.dispose()', () {
    test('disposes every child in order', () {
      final a = _RecordingPrinter('a');
      final b = _RecordingPrinter('b');
      final multi = MultiPrinter([a, b]);

      multi.dispose();

      expect(a.disposeCalls, 1);
      expect(b.disposeCalls, 1);
    });

    test('a throwing child does not prevent others from being disposed', () {
      final before = _RecordingPrinter('before');
      final boom = _ThrowingPrinter(throwOnDispose: true);
      final after = _RecordingPrinter('after');
      final multi = MultiPrinter([before, boom, after]);

      expect(() => multi.dispose(), returnsNormally);
      expect(before.disposeCalls, 1);
      expect(boom.disposeCalls, 1);
      expect(after.disposeCalls, 1);
    });

    test('empty list dispose is a silent no-op', () {
      final multi = MultiPrinter([]);
      expect(() => multi.dispose(), returnsNormally);
    });
  });

  group('MultiPrinter immutability', () {
    test('printers list is unmodifiable', () {
      final a = _RecordingPrinter('a');
      final multi = MultiPrinter([a]);

      expect(() => multi.printers.add(_RecordingPrinter('sneak')),
          throwsUnsupportedError);
    });

    test('mutating the source list after construction does not affect the printer', () {
      final source = [_RecordingPrinter('a'), _RecordingPrinter('b')];
      final multi = MultiPrinter(source);

      source.add(_RecordingPrinter('c'));
      source.removeAt(0);

      expect(multi.printers, hasLength(2),
          reason: 'MultiPrinter must snapshot the input at construction');
      expect(multi.printers[0], isA<_RecordingPrinter>());
    });
  });

  group('MultiPrinter composition', () {
    test('nests inside another MultiPrinter (fanout-of-fanouts)', () {
      final a = _RecordingPrinter('a');
      final b = _RecordingPrinter('b');
      final c = _RecordingPrinter('c');
      final outer = MultiPrinter([
        a,
        MultiPrinter([b, c]),
      ]);

      outer.log(_entry());

      expect(a.entries, hasLength(1));
      expect(b.entries, hasLength(1));
      expect(c.entries, hasLength(1));
    });

    test(
      'aggregate error from a child fan-out propagates up through nesting',
      () {
        final ok = _RecordingPrinter('ok');
        final inner = MultiPrinter([_ThrowingPrinter(error: 'inner')]);
        final outer = MultiPrinter([ok, inner]);

        MultiPrinterError? captured;
        try {
          outer.log(_entry());
        } on MultiPrinterError catch (e) {
          captured = e;
        }
        // The OUTER error reports the inner MultiPrinter as the failed
        // child (at index 1). Drill down to the inner error to find
        // the actual leaf failure.
        expect(captured, isNotNull);
        expect(captured!.childErrors, hasLength(1));
        expect(captured.childErrors[0].index, 1);
        expect(captured.childErrors[0].error, isA<MultiPrinterError>());
      },
    );
  });

  group('MultiPrinter wired through HyperLogger.init', () {
    setUp(() {
      HyperLogger.reset();
    });
    tearDown(() {
      HyperLogger.reset();
    });

    test(
      'a child throwing surfaces via setPipelineErrorHandler '
      '(no silent swallow)',
      () {
        final ok = _RecordingPrinter('ok');
        final boom = _ThrowingPrinter(error: 'cloud-down');
        final reported = <(String, Object)>[];

        HyperLogger.setPipelineErrorHandler((source, error, _) {
          reported.add((source, error));
        });
        HyperLogger.init(printer: MultiPrinter([ok, boom]));

        HyperLogger.info<String>('hello');

        // The OK child got the entry...
        expect(ok.entries, hasLength(1));
        // ...and the throwing child's failure was reported up the
        // pipeline rather than silently dropped.
        expect(reported, hasLength(1));
        expect(reported.first.$1, 'printer.log');
        expect(reported.first.$2, isA<MultiPrinterError>());
      },
    );
  });
}

class _OrderTrackingPrinter implements LogPrinter {
  final String name;
  final List<String> sink;
  _OrderTrackingPrinter(this.name, this.sink);

  @override
  void log(LogEntry entry) {
    sink.add('$name<-${entry.message}');
  }

  @override
  void dispose() {}
}
