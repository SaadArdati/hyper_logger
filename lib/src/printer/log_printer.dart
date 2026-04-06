import '../model/log_entry.dart';

/// A callback that receives a formatted log line.
typedef LogOutput = void Function(String line);

/// Base interface for all log printers.
///
/// A [LogPrinter] receives a [LogEntry] and is responsible for formatting
/// and emitting it to its destination (terminal, JSON stream, remote
/// service, etc.).
abstract class LogPrinter {
  void log(LogEntry entry);
}
