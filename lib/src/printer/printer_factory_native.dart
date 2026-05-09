import 'log_printer.dart';
import 'presets.dart';

/// Returns the best printer for the current native environment.
///
/// Uses [LogPrinterPresets.automatic] to detect GCP, AWS, Azure, CI,
/// or human-readable output (capability-tuned terminal/IDE/pipe) and
/// select the appropriate printer configuration.
LogPrinter createDefaultPrinter() {
  return LogPrinterPresets.automatic();
}
