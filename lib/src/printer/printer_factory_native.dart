import 'log_printer.dart';
import 'presets.dart';

/// Returns the best printer for the current native environment.
///
/// Uses [LogPrinterPresets.automatic] to detect Cloud Run, CI, IDE, or
/// terminal and select the appropriate printer configuration.
LogPrinter createDefaultPrinter() {
  return LogPrinterPresets.automatic();
}
