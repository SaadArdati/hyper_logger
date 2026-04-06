import 'package:hyper_logger/hyper_logger.dart';

/// Pre-built log entries for benchmarking.
///
/// Each entry is constructed once and reused across iterations to measure
/// only the printer pipeline cost, not LogEntry/LogMessage allocation.
class BenchmarkScenarios {
  BenchmarkScenarios._();

  // ── Simple message (most common path) ───────────────────────────────────

  static final LogEntry simpleInfo = _entry(
    LogLevel.info,
    'User logged in successfully',
    'AuthBloc',
    'onLogin',
  );

  static final LogEntry simpleDebug = _entry(
    LogLevel.debug,
    'Token refreshed',
    'AuthService',
    'refreshToken',
  );

  static final LogEntry simpleWarning = _entry(
    LogLevel.warning,
    'Rate limit approaching threshold',
    'ApiClient',
    'request',
  );

  static final LogEntry simpleSevere = _entry(
    LogLevel.error,
    'Connection failed after 3 retries',
    'WebSocket',
    'connect',
  );

  // ── Message with structured data ────────────────────────────────────────

  static final LogEntry withData = _entry(
    LogLevel.info,
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

  static final LogEntry withError = () {
    final error = FormatException('Unexpected character at position 42');
    // Capture a real stack trace for realistic parsing cost.
    final stack = StackTrace.current;
    return LogEntry(
      level: LogLevel.error,
      message: 'Failed to parse API response',
      object: LogMessage(
        'Failed to parse API response',
        String,
        method: 'parseJson',
      ),
      loggerName: 'ApiClient',
      time: DateTime.now(),
      error: error,
      stackTrace: stack,
    );
  }();

  // ── Varied messages (prevents constant folding) ─────────────────────────

  static final List<LogEntry> varied = List.generate(
    100,
    (i) => _entry(
      _levels[i % _levels.length],
      'Message variant $i with some payload text',
      'Service${i % 10}',
      'method${i % 5}',
    ),
  );

  // ── Helpers ─────────────────────────────────────────────────────────────

  static final _levels = [
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];

  static LogEntry _entry(
    LogLevel level,
    String message,
    String loggerName,
    String method, {
    Object? data,
  }) {
    final logMessage = LogMessage(message, String, method: method, data: data);
    return LogEntry(
      level: level,
      message: message,
      object: logMessage,
      loggerName: loggerName,
      time: DateTime.now(),
    );
  }
}
