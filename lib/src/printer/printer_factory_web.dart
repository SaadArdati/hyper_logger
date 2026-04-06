import 'log_printer.dart';
import 'web_console_printer.dart';

/// Returns the web-optimized printer that uses Chrome DevTools console APIs.
/// WebConsolePrinter uses browser console APIs directly, so the output
/// callback is not applicable. Return it as-is.
LogPrinter createDefaultPrinter() {
  return WebConsolePrinter();
}
