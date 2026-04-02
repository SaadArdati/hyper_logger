import 'dart:convert';

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

/// Formats [record] via a [JsonPrinter] and parses the resulting JSON.
Map<String, dynamic> _parse(logging.LogRecord record) {
  final captured = <String>[];
  final printer = JsonPrinter(output: captured.add);
  printer.log(record);
  expect(captured, hasLength(1), reason: 'expected exactly one JSON line');
  return jsonDecode(captured.first) as Map<String, dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('JsonPrinter.format()', () {
    test('returns exactly one element per record', () {
      final printer = JsonPrinter(output: (_) {});
      final result = printer.format(_record(message: 'hi'));
      expect(result, hasLength(1));
    });

    test('returned element is valid JSON', () {
      final printer = JsonPrinter(output: (_) {});
      final line = printer.format(_record(message: 'hi')).first;
      expect(() => jsonDecode(line), returnsNormally);
    });

    test('includes severity field', () {
      final json = _parse(_record(level: logging.Level.INFO));
      expect(json.containsKey('severity'), isTrue);
    });

    test('includes message field', () {
      final json = _parse(_record(message: 'my message'));
      expect(json['message'], equals('my message'));
    });

    test('includes timestamp field as ISO-8601 string', () {
      final json = _parse(_record());
      expect(json.containsKey('timestamp'), isTrue);
      // Should parse without throwing.
      expect(
        () => DateTime.parse(json['timestamp'] as String),
        returnsNormally,
      );
    });

    test('includes logger name', () {
      final json = _parse(_record());
      expect(json['logger'], equals('test.logger'));
    });
  });

  // ── Level → severity mapping ──────────────────────────────────────────────

  group('JsonPrinter level → severity mapping', () {
    test('FINEST → DEBUG', () {
      final json = _parse(_record(level: logging.Level.FINEST));
      expect(json['severity'], equals('DEBUG'));
    });

    test('FINER → DEBUG', () {
      final json = _parse(_record(level: logging.Level.FINER));
      expect(json['severity'], equals('DEBUG'));
    });

    test('FINE → DEBUG', () {
      final json = _parse(_record(level: logging.Level.FINE));
      expect(json['severity'], equals('DEBUG'));
    });

    test('INFO → INFO', () {
      final json = _parse(_record(level: logging.Level.INFO));
      expect(json['severity'], equals('INFO'));
    });

    test('WARNING → WARNING', () {
      final json = _parse(_record(level: logging.Level.WARNING));
      expect(json['severity'], equals('WARNING'));
    });

    test('SEVERE → ERROR', () {
      final json = _parse(_record(level: logging.Level.SEVERE));
      expect(json['severity'], equals('ERROR'));
    });

    test('SHOUT → CRITICAL', () {
      final json = _parse(_record(level: logging.Level.SHOUT));
      expect(json['severity'], equals('CRITICAL'));
    });
  });

  // ── LogMessage structured data ────────────────────────────────────────────

  group('JsonPrinter with LogMessage', () {
    test('uses LogMessage.message over record.message', () {
      final msg = LogMessage('structured text', String);
      final json = _parse(_record(message: 'raw', object: msg));
      expect(json['message'], equals('structured text'));
    });

    test('includes LogMessage.data under "data" key', () {
      final msg = LogMessage('msg', String, data: {'userId': 42});
      final json = _parse(_record(object: msg));
      expect(json.containsKey('data'), isTrue);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['userId'], equals(42));
    });

    test('no "data" key when LogMessage.data is null', () {
      final msg = LogMessage('msg', String);
      final json = _parse(_record(object: msg));
      expect(json.containsKey('data'), isFalse);
    });

    test('LogMessage with list data serialises correctly', () {
      final msg = LogMessage('msg', String, data: [1, 2, 3]);
      final json = _parse(_record(object: msg));
      expect(json['data'], equals([1, 2, 3]));
    });
  });

  // ── Error & stack trace ───────────────────────────────────────────────────

  group('JsonPrinter error and stack trace', () {
    test('includes error string when record.error is set', () {
      final err = Exception('something broke');
      final json = _parse(_record(error: err));
      expect(json.containsKey('error'), isTrue);
      expect(json['error'], contains('something broke'));
    });

    test('no "error" key when record.error is null', () {
      final json = _parse(_record());
      expect(json.containsKey('error'), isFalse);
    });

    test('includes stackTrace string when record.stackTrace is set', () {
      final st = StackTrace.current;
      final json = _parse(_record(stackTrace: st));
      expect(json.containsKey('stackTrace'), isTrue);
      expect(json['stackTrace'], isA<String>());
    });

    test('no "stackTrace" key when record.stackTrace is null', () {
      final json = _parse(_record());
      expect(json.containsKey('stackTrace'), isFalse);
    });

    test('error and stack trace both present together', () {
      final err = StateError('bad state');
      final st = StackTrace.current;
      final json = _parse(_record(error: err, stackTrace: st));
      expect(json.containsKey('error'), isTrue);
      expect(json.containsKey('stackTrace'), isTrue);
    });
  });

  // ── Output callback ───────────────────────────────────────────────────────

  group('JsonPrinter output callback', () {
    test('log() calls output exactly once per record', () {
      int calls = 0;
      final printer = JsonPrinter(output: (_) => calls++);
      printer.log(_record());
      expect(calls, 1);
    });

    test('output receives valid JSON', () {
      String? received;
      final printer = JsonPrinter(output: (s) => received = s);
      printer.log(_record(message: 'check'));
      expect(received, isNotNull);
      final decoded = jsonDecode(received!) as Map<String, dynamic>;
      expect(decoded['message'], equals('check'));
    });
  });
}
