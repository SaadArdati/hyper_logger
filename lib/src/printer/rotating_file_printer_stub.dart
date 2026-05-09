import 'dart:async';

import 'rotating_file_printer.dart';

/// Web stub. The IO implementation is selected on platforms that support
/// `dart:io`; this throws on web because filesystem writes aren't available.
RotatingFilePrinter createRotatingFilePrinter({
  required FutureOr<String> Function() baseFilePathProvider,
  required FileLineFormatter formatter,
  FileRotationConfig? rotationConfig,
  int pendingBufferSize = 1000,
  required FileWriterErrorHandler onError,
}) {
  throw UnsupportedError(
    'RotatingFilePrinter requires dart:io and is not available on the web. '
    'On web, use WebConsolePrinter or capture entries with a custom in-memory printer.',
  );
}

/// Web stub for stderr — there's no stderr in a browser, so silently no-op.
/// The default error handler in `rotating_file_printer.dart` already wraps
/// the call in `try/catch` for safety.
void writeStderrLine(String line) {
  // No-op on web.
}
