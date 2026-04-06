// ignore_for_file: avoid_print
import 'dart:io';

import 'package:hyper_logger/hyper_logger.dart';

/// Example: logging to a file using a custom LogPrinter.
///
/// Run: dart run example/file_logger_example.dart
///
/// This creates a `logs.txt` file in the current directory.
void main() {
  final logFile = File('logs.txt');
  // Clear any previous content.
  if (logFile.existsSync()) logFile.deleteSync();

  // Use the CI preset (timestamp + prefix, no ANSI codes) with file output.
  HyperLogger.init(
    printer: LogPrinterPresets.ci(
      output: (line) {
        logFile.writeAsStringSync('$line\n', mode: FileMode.append);
      },
    ),
  );

  HyperLogger.info<App>('Application started');
  HyperLogger.debug<AuthService>('Checking stored credentials');
  HyperLogger.warning<ApiClient>('Server returned 429, backing off');
  HyperLogger.error<Database>(
    'Connection lost',
    exception: SocketException('Connection refused'),
    method: 'connect',
  );

  // Read back and print to verify.
  print('Written to ${logFile.path}:');
  print('');
  print(logFile.readAsStringSync());

  // Clean up.
  logFile.deleteSync();
}

class App {}

class AuthService {}

class ApiClient {}

class Database {}
