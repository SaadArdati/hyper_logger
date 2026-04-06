// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

/// Example: crash reporting delegate.
///
/// Run: dart run example/crash_reporting_example.dart
///
/// Demonstrates how warning/error/fatal forward to CrashReportingDelegate.
void main() async {
  final crashReporter = FakeCrashReporter();

  HyperLogger.init(printer: LogPrinterPresets.ide());
  HyperLogger.attachServices(crashReporting: crashReporter);

  // This goes to the printer AND crash reporting.
  HyperLogger.warning<ApiClient>('Rate limit exceeded');

  // This goes to the printer AND crash reporting with error details.
  HyperLogger.error<Database>(
    'Connection failed',
    exception: StateError('pool exhausted'),
    method: 'connect',
  );

  // This always goes to crash reporting with fatal: true.
  HyperLogger.fatal<App>(
    'Unrecoverable state',
    exception: StateError('corrupt database'),
  );

  // Stopwatch logs elapsed time to the printer.
  final sw = Stopwatch()..start();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  sw.stop();
  HyperLogger.stopwatch<ApiClient>('API round-trip', sw);

  // Show what the delegate received.
  await Future<void>.delayed(Duration.zero);

  print('');
  print('--- Crash Reporter received ---');
  for (final msg in crashReporter.logs) {
    print('  log: $msg');
  }
  for (final (error, _, fatal, reason) in crashReporter.errors) {
    print('  recordError: $error (fatal: $fatal, reason: $reason)');
  }
}

/// Fake crash reporter that records calls for demonstration.
class FakeCrashReporter extends CrashReportingDelegate {
  final List<String> logs = [];
  final List<(Object, StackTrace?, bool, String?)> errors = [];

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add((error, stackTrace, fatal, reason));
  }
}

class ApiClient {}

class Database {}

class App {}
