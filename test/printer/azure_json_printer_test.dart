import 'dart:convert';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

LogEntry _record({
  String message = 'test message',
  Object? object,
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stackTrace,
  String loggerName = 'test.logger',
}) {
  return LogEntry(
    level: level,
    message: message,
    object: object,
    loggerName: loggerName,
    time: DateTime.utc(2026, 5, 9, 12, 0, 0),
    error: error,
    stackTrace: stackTrace,
  );
}

Map<String, dynamic> _parse(LogEntry entry) {
  final captured = <String>[];
  final printer = AzureJsonPrinter(output: captured.add);
  printer.log(entry);
  expect(captured, hasLength(1), reason: 'expected exactly one JSON line');
  return jsonDecode(captured.first) as Map<String, dynamic>;
}

void main() {
  group('AzureJsonPrinter.format()', () {
    test('returns exactly one element per record', () {
      final printer = AzureJsonPrinter(output: (_) {});
      expect(printer.format(_record()), hasLength(1));
    });

    test('returned element is valid JSON', () {
      final printer = AzureJsonPrinter(output: (_) {});
      expect(() => jsonDecode(printer.format(_record()).first), returnsNormally);
    });
  });

  group('AzureJsonPrinter level mapping', () {
    test('trace → 0 (Verbose)', () {
      expect(_parse(_record(level: LogLevel.trace))['severityLevel'], 0);
    });

    test('debug → 0 (Verbose)', () {
      expect(_parse(_record(level: LogLevel.debug))['severityLevel'], 0);
    });

    test('info → 1 (Information)', () {
      expect(_parse(_record(level: LogLevel.info))['severityLevel'], 1);
    });

    test('warning → 2 (Warning)', () {
      expect(_parse(_record(level: LogLevel.warning))['severityLevel'], 2);
    });

    test('error → 3 (Error)', () {
      expect(_parse(_record(level: LogLevel.error))['severityLevel'], 3);
    });

    test('fatal → 4 (Critical)', () {
      expect(_parse(_record(level: LogLevel.fatal))['severityLevel'], 4);
    });

    test('severityLevel is a JSON int, not a string', () {
      final json = _parse(_record(level: LogLevel.warning));
      expect(json['severityLevel'], isA<int>());
    });
  });

  group('AzureJsonPrinter shape conformance', () {
    test('uses "time" timestamp key (Application Insights envelope convention)', () {
      final json = _parse(_record());
      expect(json.containsKey('time'), isTrue);
      expect(json.containsKey('timestamp'), isFalse);
    });

    test('"time" is ISO-8601 UTC', () {
      final json = _parse(_record());
      expect(
        json['time'],
        matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'),
      );
    });

    test('uses "severityLevel" (Application Insights traces field)', () {
      final json = _parse(_record(level: LogLevel.info));
      expect(json.containsKey('severityLevel'), isTrue);
      expect(json.containsKey('severity'), isFalse);
      expect(json.containsKey('level'), isFalse);
    });

    test('includes message field', () {
      final json = _parse(_record(message: 'my message'));
      expect(json['message'], 'my message');
    });

    test('drops generic logger names (dynamic/Object/Null)', () {
      for (final generic in ['dynamic', 'Object', 'Null']) {
        final json = _parse(_record(loggerName: generic));
        expect(
          json.containsKey('logger'),
          isFalse,
          reason: '"$generic" should be dropped, not surfaced',
        );
      }
    });

    test('keeps non-generic logger names', () {
      final json = _parse(_record(loggerName: 'PaymentService'));
      expect(json['logger'], 'PaymentService');
    });
  });

  group('AzureJsonPrinter context (customDimensions)', () {
    test('context lands inside customDimensions, not at root', () {
      final json = _parse(_record(
        object: const LogMessage(
          'msg',
          dynamic,
          context: {'requestId': 'abc-123', 'userId': 'u-42'},
        ),
      ));

      expect(json.containsKey('requestId'), isFalse,
          reason: 'context should be nested, not flat');
      expect(json.containsKey('userId'), isFalse);

      final cd = json['customDimensions'] as Map<String, dynamic>;
      expect(cd['requestId'], 'abc-123');
      expect(cd['userId'], 'u-42');
    });

    test('omits customDimensions when context is null', () {
      final json = _parse(_record());
      expect(json.containsKey('customDimensions'), isFalse);
    });

    test('omits customDimensions when context is empty', () {
      final json = _parse(_record(
        object: const LogMessage('msg', dynamic, context: {}),
      ));
      expect(json.containsKey('customDimensions'), isFalse);
    });

    test('drops reserved keys from context', () {
      final json = _parse(_record(
        object: const LogMessage(
          'msg',
          dynamic,
          context: {
            'severityLevel': 99, // reserved
            'message': 'BUG', // reserved
            'time': 'BUG', // reserved
            'customDimensions': 'BUG', // reserved
            'safe': 'value',
          },
        ),
      ));
      // Reserved keys are not surfaced anywhere
      expect(json['severityLevel'], 1, reason: 'must reflect the real level');
      expect(json['message'], 'msg', reason: 'must reflect the real message');
      // ...and they don't leak into customDimensions either
      final cd = json['customDimensions'] as Map<String, dynamic>;
      expect(cd.containsKey('severityLevel'), isFalse);
      expect(cd.containsKey('message'), isFalse);
      expect(cd.containsKey('time'), isFalse);
      expect(cd.containsKey('customDimensions'), isFalse);
      expect(cd['safe'], 'value');
    });
  });

  group('AzureJsonPrinter error/stackTrace embedding', () {
    test('error severity embeds stack trace in message', () {
      final st = StackTrace.fromString('at Foo.bar (file.dart:1:2)');
      final json = _parse(_record(
        message: 'failure',
        level: LogLevel.error,
        error: Exception('boom'),
        stackTrace: st,
      ));
      expect(json['message'], contains('failure'));
      expect(json['message'], contains('boom'));
      expect(json['message'], contains('Foo.bar'));
    });

    test('fatal severity embeds stack trace in message', () {
      final st = StackTrace.fromString('at Foo.bar (file.dart:1:2)');
      final json = _parse(_record(
        message: 'failure',
        level: LogLevel.fatal,
        error: Exception('boom'),
        stackTrace: st,
      ));
      expect(json['message'], contains('boom'));
      expect(json['message'], contains('Foo.bar'));
    });

    test('warning severity does NOT embed stack trace in message', () {
      final st = StackTrace.fromString('at Foo.bar (file.dart:1:2)');
      final json = _parse(_record(
        message: 'just a warning',
        level: LogLevel.warning,
        error: Exception('boom'),
        stackTrace: st,
      ));
      expect(json['message'], 'just a warning');
      expect(json['error'], contains('boom'));
      expect(json['stackTrace'], contains('Foo.bar'));
    });
  });

  group('LogPrinterPresets.azure()', () {
    test('returns an AzureJsonPrinter', () {
      final p = LogPrinterPresets.azure(output: (_) {});
      expect(p, isA<AzureJsonPrinter>());
    });
  });
}
