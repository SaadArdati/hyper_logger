import 'log_printer.dart';
import 'web_console_printer.dart';

/// Returns the web-optimized printer that uses Chrome DevTools console APIs.
LogPrinter createDefaultPrinter() {
  return WebConsolePrinter();
}
