import '../model/log_entry.dart';
import 'log_printer.dart';

/// The simplest possible [LogPrinter]: prints each record's message text
/// directly using [output], with no formatting, decoration, or colour.
///
/// Useful as a fallback or for environments where formatted output is
/// unavailable or undesirable. The [output] callback defaults to [print] and
/// can be replaced in tests.
class DirectPrinter implements LogPrinter {
  /// Sink for formatted output. Defaults to [print].
  final LogOutput output;

  const DirectPrinter({this.output = print});

  @override
  void log(LogEntry entry) {
    output(entry.message);
  }
}
