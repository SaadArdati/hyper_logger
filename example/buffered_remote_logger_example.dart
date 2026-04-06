// ignore_for_file: avoid_print
import 'dart:async';

import 'package:hyper_logger/hyper_logger.dart';

/// Example: a buffered remote log printer that batches entries and
/// "uploads" them periodically.
///
/// Run: dart run example/buffered_remote_logger_example.dart
///
/// This demonstrates how to build a custom [LogPrinter] that queues entries
/// and flushes them in batches — useful for production apps that send logs
/// to a remote service.
void main() async {
  final remotePrinter = BufferedRemotePrinter(
    batchSize: 3,
    onFlush: (batch) {
      // In a real app, this would be an HTTP POST to your log ingestion service.
      print('[REMOTE FLUSH] Sending ${batch.length} entries:');
      for (final entry in batch) {
        print(
          '  ${entry.level.label} | ${entry.loggerName} | ${entry.message}',
        );
      }
      print('');
    },
  );

  HyperLogger.init(printer: remotePrinter);

  // Log several entries. The buffer flushes every 3.
  HyperLogger.info<App>('Application started');
  HyperLogger.debug<AuthService>('Checking credentials');
  HyperLogger.info<AuthService>('User authenticated');
  // ^ Batch of 3 flushed here.

  HyperLogger.warning<ApiClient>('Slow response (2.3s)');
  HyperLogger.error<Database>('Query timeout', method: 'fetchUsers');
  // Only 2 in buffer — not yet at batchSize.

  // Flush remaining on shutdown.
  remotePrinter.flush();

  // Give async operations time to complete.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('Done.');
}

/// A custom [LogPrinter] that buffers entries and flushes in batches.
///
/// Real-world usage would replace [onFlush] with an HTTP client call.
class BufferedRemotePrinter implements LogPrinter {
  final int batchSize;
  final void Function(List<LogEntry> batch) onFlush;
  final List<LogEntry> _buffer = [];

  BufferedRemotePrinter({this.batchSize = 50, required this.onFlush});

  @override
  void log(LogEntry entry) {
    _buffer.add(entry);
    if (_buffer.length >= batchSize) {
      flush();
    }
  }

  void flush() {
    if (_buffer.isEmpty) return;
    final batch = List<LogEntry>.of(_buffer);
    _buffer.clear();
    onFlush(batch);
  }
}

class App {}

class AuthService {}

class ApiClient {}

class Database {}
