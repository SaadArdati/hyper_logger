// ignore_for_file: avoid_print
import 'dart:io';

import 'package:hyper_logger/hyper_logger.dart';

/// Example: persisting logs to disk with `RotatingFilePrinter`.
///
/// Run: dart run example/file_logger_example.dart
///
/// Demonstrates the v0.2 marquee feature: an append-only file printer
/// with size-based rotation, retention, and gzip compression of older
/// rotated files.
Future<void> main() async {
  // Use a temp dir so the example is self-cleaning.
  final tempDir = Directory.systemTemp.createTempSync('hyper_logger_example_');
  final logPath = '${tempDir.path}/app.log';

  final filePrinter = RotatingFilePrinter(
    baseFilePathProvider: () => logPath,
    rotationConfig: FileRotationConfig.size(
      maxBytes: 200, // tiny so the example actually rotates
      maxFiles: 3, // keep at most 3 rotated copies
      compress: true, // gzip rotated files
    ),
    onError: (error, stack) {
      // surface IO failures to your monitoring; default is stderr
      stderr.writeln('hyper_logger: file printer error: $error');
    },
  );

  HyperLogger.init(printer: filePrinter);

  HyperLogger.info<App>('Application started');
  HyperLogger.debug<AuthService>('Checking stored credentials');
  HyperLogger.warning<ApiClient>('Server returned 429, backing off');
  HyperLogger.error<Database>(
    'Connection lost',
    exception: const SocketException('Connection refused'),
    method: 'connect',
  );

  // Generate enough volume to actually trigger rotation.
  for (var i = 0; i < 20; i++) {
    HyperLogger.info<App>('Periodic heartbeat $i', data: {'tick': i});
  }

  // Critical: await `close()` so buffered writes hit disk and any
  // in-flight gzip compressions complete. `dispose()` (called by
  // a later `HyperLogger.init`) is best-effort fire-and-forget.
  await filePrinter.close();

  print('Logs written under ${tempDir.path}:');
  for (final f in tempDir.listSync()) {
    print('  ${f.path} (${(f.statSync().size)} bytes)');
  }
  print('');
  print('Live log contents:');
  print(File(logPath).readAsStringSync());

  // Cleanup.
  tempDir.deleteSync(recursive: true);
}

class App {}

class AuthService {}

class ApiClient {}

class Database {}
