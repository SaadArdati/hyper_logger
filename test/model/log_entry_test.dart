import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';

void main() {
  // ── Construction with all fields ──────────────────────────────────────────

  group('LogEntry construction', () {
    test('all required fields are stored', () {
      final time = DateTime(2026, 1, 15, 10, 30, 0);
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'Test message',
        loggerName: 'MyLogger',
        time: time,
      );

      expect(entry.level, equals(LogLevel.info));
      expect(entry.message, equals('Test message'));
      expect(entry.loggerName, equals('MyLogger'));
      expect(entry.time, equals(time));
      expect(entry.object, isNull);
      expect(entry.error, isNull);
      expect(entry.stackTrace, isNull);
    });

    test('optional fields are stored when provided', () {
      final time = DateTime.now();
      final st = StackTrace.current;
      final error = Exception('test');
      final dataObj = {'key': 'value'};

      final entry = LogEntry(
        level: LogLevel.error,
        message: 'Error occurred',
        object: dataObj,
        loggerName: 'ErrorLogger',
        time: time,
        error: error,
        stackTrace: st,
      );

      expect(entry.object, equals(dataObj));
      expect(entry.error, equals(error));
      expect(entry.stackTrace, equals(st));
    });

    test('works with every LogLevel', () {
      for (final level in LogLevel.values) {
        final entry = LogEntry(
          level: level,
          message: '${level.label} message',
          loggerName: 'Test',
          time: DateTime.now(),
        );
        expect(entry.level, equals(level));
      }
    });

    test('message can be empty string', () {
      final entry = LogEntry(
        level: LogLevel.debug,
        message: '',
        loggerName: 'Test',
        time: DateTime.now(),
      );
      expect(entry.message, equals(''));
    });

    test('loggerName can be empty string', () {
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'msg',
        loggerName: '',
        time: DateTime.now(),
      );
      expect(entry.loggerName, equals(''));
    });

    test('error can be a non-Exception object', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'msg',
        loggerName: 'Test',
        time: DateTime.now(),
        error: 'string error',
      );
      expect(entry.error, equals('string error'));
    });
  });

  // ── fromLogRecord conversion ──────────────────────────────────────────────

  group('LogEntry.fromLogRecord', () {
    test('preserves message', () {
      final logger = logging.Logger('TestLogger');
      // We need to listen to capture the record.
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);
      logger.info('hello from logger');

      expect(captured, isNotNull);
      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.message, equals('hello from logger'));
    });

    test('preserves loggerName', () {
      final logger = logging.Logger('MyComponent');
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);
      logger.info('msg');

      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.loggerName, equals('MyComponent'));
    });

    test('preserves time', () {
      final logger = logging.Logger('TimeTest');
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);
      logger.info('msg');

      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.time, equals(captured!.time));
    });

    test('preserves error and stackTrace', () {
      final logger = logging.Logger('ErrorTest');
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);

      final exception = FormatException('bad format');
      final st = StackTrace.current;
      logger.severe('error occurred', exception, st);

      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.error, equals(exception));
      expect(entry.stackTrace, equals(st));
    });

    test('preserves object (structured payload)', () {
      final logger = logging.Logger('ObjectTest');
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);

      final payload = LogMessage('test', String);
      logger.log(logging.Level.INFO, payload);

      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.object, equals(payload));
    });

    test('null error and stackTrace are preserved as null', () {
      final logger = logging.Logger('NullTest');
      logging.LogRecord? captured;
      logger.onRecord.listen((r) => captured = r);
      logger.info('no error');

      final entry = LogEntry.fromLogRecord(captured!);
      expect(entry.error, isNull);
      expect(entry.stackTrace, isNull);
    });
  });

  // ── fromLogRecord level conversion ────────────────────────────────────────

  group('fromLogRecord level conversion', () {
    test('INFO converts to LogLevel.info', () {
      final record = logging.LogRecord(logging.Level.INFO, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.info));
    });

    test('FINE converts to LogLevel.debug', () {
      final record = logging.LogRecord(logging.Level.FINE, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.debug));
    });

    test('FINEST converts to LogLevel.trace', () {
      final record = logging.LogRecord(logging.Level.FINEST, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.trace));
    });

    test('WARNING converts to LogLevel.warning', () {
      final record = logging.LogRecord(logging.Level.WARNING, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.warning));
    });

    test('SEVERE converts to LogLevel.error', () {
      final record = logging.LogRecord(logging.Level.SEVERE, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.error));
    });

    test('SHOUT converts to LogLevel.fatal', () {
      final record = logging.LogRecord(logging.Level.SHOUT, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.fatal));
    });

    test('FINER converts to LogLevel.trace', () {
      final record = logging.LogRecord(logging.Level.FINER, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.trace));
    });

    test('CONFIG converts to LogLevel.info', () {
      final record = logging.LogRecord(logging.Level.CONFIG, 'msg', 'Test');
      final entry = LogEntry.fromLogRecord(record);
      expect(entry.level, equals(LogLevel.info));
    });
  });
}
