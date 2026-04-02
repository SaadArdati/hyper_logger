import 'package:logging/logging.dart' as logging;

/// Base interface for all log printers.
///
/// A [LogPrinter] receives a fully-formed [logging.LogRecord] and is
/// responsible for formatting and emitting the log entry to its destination
/// (terminal, JSON stream, remote service, etc.).
abstract class LogPrinter {
  void log(logging.LogRecord record);
}
