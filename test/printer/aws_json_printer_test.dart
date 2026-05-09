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

/// Formats [entry] via an [AwsJsonPrinter] and parses the resulting JSON.
Map<String, dynamic> _parse(LogEntry entry) {
  final captured = <String>[];
  final printer = AwsJsonPrinter(output: captured.add);
  printer.log(entry);
  expect(captured, hasLength(1), reason: 'expected exactly one JSON line');
  return jsonDecode(captured.first) as Map<String, dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('AwsJsonPrinter.format()', () {
    test('returns exactly one element per record', () {
      final printer = AwsJsonPrinter(output: (_) {});
      final result = printer.format(_record(message: 'hi'));
      expect(result, hasLength(1));
    });

    test('returned element is valid JSON', () {
      final printer = AwsJsonPrinter(output: (_) {});
      final line = printer.format(_record(message: 'hi')).first;
      expect(() => jsonDecode(line), returnsNormally);
    });

    test('uses CloudWatch "level" field, not GCP "severity"', () {
      final json = _parse(_record(level: LogLevel.info));
      expect(json.containsKey('level'), isTrue);
      expect(json.containsKey('severity'), isFalse);
    });

    test('includes message field', () {
      final json = _parse(_record(message: 'my message'));
      expect(json['message'], equals('my message'));
    });

    test('includes timestamp field as ISO-8601 UTC', () {
      final json = _parse(_record());
      expect(json.containsKey('timestamp'), isTrue);
      final parsed = DateTime.parse(json['timestamp'] as String);
      expect(parsed.isUtc, isTrue);
    });

    test('includes logger name', () {
      final json = _parse(_record());
      expect(json['logger'], equals('test.logger'));
    });
  });

  // ── Level → CloudWatch level mapping ──────────────────────────────────────

  group('AwsJsonPrinter level mapping', () {
    test('trace → TRACE', () {
      final json = _parse(_record(level: LogLevel.trace));
      expect(json['level'], equals('TRACE'));
    });

    test('debug → DEBUG', () {
      final json = _parse(_record(level: LogLevel.debug));
      expect(json['level'], equals('DEBUG'));
    });

    test('info → INFO', () {
      final json = _parse(_record(level: LogLevel.info));
      expect(json['level'], equals('INFO'));
    });

    test('warning → WARN (CloudWatch convention, not WARNING)', () {
      final json = _parse(_record(level: LogLevel.warning));
      expect(json['level'], equals('WARN'));
    });

    test('error → ERROR', () {
      final json = _parse(_record(level: LogLevel.error));
      expect(json['level'], equals('ERROR'));
    });

    test('fatal → FATAL (CloudWatch convention, not CRITICAL)', () {
      final json = _parse(_record(level: LogLevel.fatal));
      expect(json['level'], equals('FATAL'));
    });
  });

  // ── LogMessage structured data ────────────────────────────────────────────

  group('AwsJsonPrinter with LogMessage', () {
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
  });

  // ── Reserved-key precedence ───────────────────────────────────────────────

  group('AwsJsonPrinter reserved-key precedence', () {
    Map<String, dynamic> withContextKeys(Map<String, Object?> ctx) {
      final captured = <String>[];
      final p = AwsJsonPrinter(output: captured.add);
      final entry = LogEntry(
        level: LogLevel.warning,
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

    test('context cannot override level', () {
      final json = withContextKeys({'level': 'CUSTOM'});
      expect(json['level'], equals('WARN'));
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

    test('context cannot override error or stackTrace', () {
      final json = withContextKeys({
        'error': 'fake error',
        'stackTrace': 'fake trace',
      });
      expect(json['error'], contains('e'));
      expect(json['stackTrace'], contains('a.dart:1'));
    });

    test('non-reserved context keys still flow through', () {
      final json = withContextKeys({
        'level': 'CUSTOM',
        'requestId': 'R-42',
      });
      expect(json['level'], equals('WARN'));
      expect(json['requestId'], equals('R-42'));
    });

    test('nested context with reserved-named key is NOT filtered', () {
      final json = withContextKeys({
        'payment': {'level': 'urgent', 'amount': 100},
      });
      final payment = json['payment'] as Map;
      expect(payment['level'], equals('urgent'));
      expect(json['level'], equals('WARN'));
    });
  });

  group('AwsJsonPrinter CloudWatch error visibility', () {
    String runError({
      required LogLevel level,
      Object? error,
      StackTrace? stackTrace,
    }) {
      final captured = <String>[];
      final p = AwsJsonPrinter(output: captured.add);
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
      expect(json['stackTrace'], contains('a.dart:1'));
    });

    test('warning severity does NOT embed stack trace into message', () {
      final st = StackTrace.fromString('a.dart:1');
      final line = runError(
        level: LogLevel.warning,
        error: Exception('warn'),
        stackTrace: st,
      );
      final json = jsonDecode(line) as Map<String, dynamic>;
      expect(json['message'], equals('base'));
    });
  });

  // ── Error & stack trace ───────────────────────────────────────────────────

  group('AwsJsonPrinter error and stack trace', () {
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

    test('includes stackTrace when record.stackTrace is set', () {
      final st = StackTrace.current;
      final json = _parse(_record(stackTrace: st));
      expect(json.containsKey('stackTrace'), isTrue);
    });
  });
}
