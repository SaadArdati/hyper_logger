import 'dart:convert';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a minimal [LogEntry].
LogEntry _record({
  String message = 'test message',
  Object? object,
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stackTrace,
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

/// Formats [entry] via a [GcpJsonPrinter] and parses the resulting JSON.
Map<String, dynamic> _parse(LogEntry entry) {
  final captured = <String>[];
  final printer = GcpJsonPrinter(output: captured.add);
  printer.log(entry);
  expect(captured, hasLength(1), reason: 'expected exactly one JSON line');
  return jsonDecode(captured.first) as Map<String, dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('GcpJsonPrinter.format()', () {
    test('returns exactly one element per record', () {
      final printer = GcpJsonPrinter(output: (_) {});
      final result = printer.format(_record(message: 'hi'));
      expect(result, hasLength(1));
    });

    test('returned element is valid JSON', () {
      final printer = GcpJsonPrinter(output: (_) {});
      final line = printer.format(_record(message: 'hi')).first;
      expect(() => jsonDecode(line), returnsNormally);
    });

    test('includes severity field', () {
      final json = _parse(_record(level: LogLevel.info));
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

  group('GcpJsonPrinter level → severity mapping', () {
    test('trace → DEBUG', () {
      final json = _parse(_record(level: LogLevel.trace));
      expect(json['severity'], equals('DEBUG'));
    });

    test('debug → DEBUG', () {
      final json = _parse(_record(level: LogLevel.debug));
      expect(json['severity'], equals('DEBUG'));
    });

    test('info → INFO', () {
      final json = _parse(_record(level: LogLevel.info));
      expect(json['severity'], equals('INFO'));
    });

    test('warning → WARNING', () {
      final json = _parse(_record(level: LogLevel.warning));
      expect(json['severity'], equals('WARNING'));
    });

    test('error → ERROR', () {
      final json = _parse(_record(level: LogLevel.error));
      expect(json['severity'], equals('ERROR'));
    });

    test('fatal → CRITICAL', () {
      final json = _parse(_record(level: LogLevel.fatal));
      expect(json['severity'], equals('CRITICAL'));
    });
  });

  // ── LogMessage structured data ────────────────────────────────────────────

  group('GcpJsonPrinter with LogMessage', () {
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

  group('GcpJsonPrinter error and stack trace', () {
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

  // ── Reserved-key precedence ───────────────────────────────────────────────

  group('GcpJsonPrinter reserved-key precedence', () {
    Map<String, dynamic> withContextKeys(Map<String, Object?> ctx) {
      final captured = <String>[];
      final p = GcpJsonPrinter(output: captured.add);
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'm',
        object: LogMessage('m', String, context: ctx),
        loggerName: 'test',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
        error: Exception('e'),
        stackTrace: StackTrace.fromString('a.dart:1'),
      );
      p.log(entry);
      return jsonDecode(captured.single) as Map<String, dynamic>;
    }

    test('context cannot override severity', () {
      final json = withContextKeys({'severity': 'CUSTOM'});
      expect(json['severity'], equals('INFO'));
    });

    test('context cannot override message', () {
      final json = withContextKeys({'message': 'spoofed'});
      expect(json['message'], equals('m'));
    });

    test('context cannot override timestamp', () {
      final json = withContextKeys({'timestamp': '1970-01-01T00:00:00.000Z'});
      expect(json['timestamp'], equals('2026-05-08T12:00:00.000Z'));
    });

    test('context cannot override logger', () {
      final json = withContextKeys({'logger': 'fake'});
      expect(json['logger'], equals('test'));
    });

    test('context cannot override data', () {
      final json = withContextKeys({'data': 'fake'});
      // Original entry has no data, so the field should be absent — not the
      // context-supplied 'fake'.
      expect(json.containsKey('data'), isFalse);
    });

    test('context cannot override error or stackTrace', () {
      final json = withContextKeys({
        'error': 'fake error',
        'stackTrace': 'fake trace',
      });
      expect(json['error'], contains('e'));
      expect(json['error'], isNot(equals('fake error')));
      expect(json['stackTrace'], contains('a.dart:1'));
    });

    test('non-reserved context keys still flow through', () {
      final json = withContextKeys({
        'severity': 'CUSTOM',
        'requestId': 'R-42',
      });
      expect(json['severity'], equals('INFO'));
      expect(json['requestId'], equals('R-42'));
    });

    test('nested context with a reserved-named key is NOT filtered', () {
      // Reserved-key filtering is intentionally top-level only. A user
      // putting a `severity` key inside a nested map (e.g. metadata
      // about a payment that itself has a "severity" field) should not
      // have that nested key disappear.
      final json = withContextKeys({
        'payment': {'severity': 'urgent', 'amount': 100},
      });
      expect(json['payment'], isA<Map<String, dynamic>>());
      final payment = json['payment'] as Map<String, dynamic>;
      expect(payment['severity'], equals('urgent'));
      expect(payment['amount'], equals(100));
      // Top-level severity is still ours.
      expect(json['severity'], equals('INFO'));
    });

    test('GCP magic fields (httpRequest, trace, etc.) flow through context',
        () {
      // These are recognized by Cloud Logging as structured fields. We
      // do NOT reserve them — users can and should set them via context
      // to take advantage of Cloud Logging features like trace
      // correlation and HTTP request rendering.
      final json = withContextKeys({
        'httpRequest': {'requestMethod': 'GET', 'status': 200},
        'logging.googleapis.com/trace':
            'projects/my-project/traces/abc123',
        'logging.googleapis.com/spanId': '0000000000000042',
      });
      expect(json['httpRequest'], isA<Map<String, dynamic>>());
      expect(
        json['logging.googleapis.com/trace'],
        equals('projects/my-project/traces/abc123'),
      );
      expect(json['logging.googleapis.com/spanId'], equals('0000000000000042'));
    });
  });

  group('GcpJsonPrinter Cloud Error Reporting integration', () {
    String runError({
      required LogLevel level,
      Object? error,
      StackTrace? stackTrace,
    }) {
      final captured = <String>[];
      final p = GcpJsonPrinter(output: captured.add);
      p.log(LogEntry(
        level: level,
        message: 'base',
        object: LogMessage('base', String),
        loggerName: 'svc',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
        error: error,
        stackTrace: stackTrace,
      ));
      return captured.single;
    }

    test('error severity with stack trace embeds the trace into message', () {
      final st = StackTrace.fromString('a.dart:1\nb.dart:2');
      final line = runError(
        level: LogLevel.error,
        error: Exception('boom'),
        stackTrace: st,
      );
      final json = jsonDecode(line) as Map<String, dynamic>;
      expect(json['message'], contains('base'));
      expect(json['message'], contains('boom'));
      expect(json['message'], contains('a.dart:1'));
      // The stack trace is also preserved in its own field for inspection.
      expect(json['stackTrace'], contains('a.dart:1'));
    });

    test('info severity does NOT embed stack trace into message', () {
      final st = StackTrace.fromString('a.dart:1');
      final line = runError(
        level: LogLevel.info,
        error: Exception('warn'),
        stackTrace: st,
      );
      final json = jsonDecode(line) as Map<String, dynamic>;
      expect(json['message'], equals('base'));
    });

    test('error without stack trace does NOT embed', () {
      final line = runError(
        level: LogLevel.error,
        error: Exception('boom'),
      );
      final json = jsonDecode(line) as Map<String, dynamic>;
      expect(json['message'], equals('base'));
      expect(json['error'], contains('boom'));
    });
  });

  // ── Output callback ───────────────────────────────────────────────────────

  group('GcpJsonPrinter output callback', () {
    test('log() calls output exactly once per record', () {
      int calls = 0;
      final printer = GcpJsonPrinter(output: (_) => calls++);
      printer.log(_record());
      expect(calls, 1);
    });

    test('output receives valid JSON', () {
      String? received;
      final printer = GcpJsonPrinter(output: (s) => received = s);
      printer.log(_record(message: 'check'));
      expect(received, isNotNull);
      final decoded = jsonDecode(received!) as Map<String, dynamic>;
      expect(decoded['message'], equals('check'));
    });
  });
}
