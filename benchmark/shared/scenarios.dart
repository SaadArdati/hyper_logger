import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;

/// Pre-built log records for benchmarking.
///
/// Each record is constructed once and reused across iterations to measure
/// only the printer pipeline cost, not LogRecord/LogMessage allocation.
class BenchmarkScenarios {
  BenchmarkScenarios._();

  // ── Simple message (most common path) ───────────────────────────────────

  static final logging.LogRecord simpleInfo = _record(
    logging.Level.INFO,
    'User logged in successfully',
    'AuthBloc',
    'onLogin',
  );

  static final logging.LogRecord simpleDebug = _record(
    logging.Level.FINE,
    'Token refreshed',
    'AuthService',
    'refreshToken',
  );

  static final logging.LogRecord simpleWarning = _record(
    logging.Level.WARNING,
    'Rate limit approaching threshold',
    'ApiClient',
    'request',
  );

  static final logging.LogRecord simpleSevere = _record(
    logging.Level.SEVERE,
    'Connection failed after 3 retries',
    'WebSocket',
    'connect',
  );

  // ── Message with structured data ────────────────────────────────────────

  static final logging.LogRecord withData = _record(
    logging.Level.INFO,
    'Portfolio positions loaded',
    'PortfolioCubit',
    'load',
    data: {
      'positions': 12,
      'totalValue': 45230.50,
      'currency': 'USD',
      'updatedAt': '2026-04-02T10:30:00Z',
    },
  );

  // ── Message with error + stack trace ────────────────────────────────────

  static final logging.LogRecord withError = () {
    final error = FormatException('Unexpected character at position 42');
    // Capture a real stack trace for realistic parsing cost.
    final stack = StackTrace.current;
    return logging.LogRecord(
      logging.Level.SEVERE,
      'Failed to parse API response',
      'ApiClient',
      error,
      stack,
      null,
      LogMessage('Failed to parse API response', String, method: 'parseJson'),
    );
  }();

  // ── Varied messages (prevents constant folding) ─────────────────────────

  static final List<logging.LogRecord> varied = List.generate(
    100,
    (i) => _record(
      _levels[i % _levels.length],
      'Message variant $i with some payload text',
      'Service${i % 10}',
      'method${i % 5}',
    ),
  );

  // ── Helpers ─────────────────────────────────────────────────────────────

  static final _levels = [
    logging.Level.FINE,
    logging.Level.INFO,
    logging.Level.WARNING,
    logging.Level.SEVERE,
  ];

  static logging.LogRecord _record(
    logging.Level level,
    String message,
    String loggerName,
    String method, {
    Object? data,
  }) {
    final logMessage = LogMessage(message, String, method: method, data: data);
    return logging.LogRecord(
      level,
      message,
      loggerName,
      null,
      null,
      null,
      logMessage,
    );
  }
}
