import 'dart:async';
import 'dart:collection';

import '../model/log_entry.dart';
import '../model/log_level.dart';
import 'log_printer.dart';

/// A [LogPrinter] wrapper that rate-limits output to prevent high-frequency
/// logging from choking the process or overwhelming the terminal.
///
/// Entries up to [maxPerSecond] are forwarded immediately. Once the limit is
/// hit, excess entries are queued and drained at the throttled rate. When the
/// queue exceeds [maxQueueSize], the oldest entries are dropped and a summary
/// message is printed when draining resumes.
///
/// ```dart
/// HyperLogger.init(
///   printer: ThrottledPrinter(
///     LogPrinterPresets.terminal(),
///     maxPerSecond: 30,
///   ),
/// );
/// ```
class ThrottledPrinter implements LogPrinter {
  /// The underlying printer that receives rate-limited entries.
  final LogPrinter inner;

  /// Maximum entries forwarded per second before throttling kicks in.
  final int maxPerSecond;

  /// Maximum queued entries. When exceeded, oldest entries are dropped.
  final int maxQueueSize;

  final Queue<LogEntry> _queue = Queue<LogEntry>();
  Timer? _drainTimer;
  int _countThisWindow = 0;
  int _droppedCount = 0;
  DateTime _windowStart = DateTime.now();

  ThrottledPrinter(
    this.inner, {
    this.maxPerSecond = 30,
    this.maxQueueSize = 500,
  });

  @override
  void log(LogEntry entry) {
    final now = DateTime.now();

    // Reset the window if a second has elapsed.
    if (now.difference(_windowStart).inMilliseconds >= 1000) {
      _windowStart = now;
      _countThisWindow = 0;
    }

    // Under the limit — forward immediately.
    if (_countThisWindow < maxPerSecond && _queue.isEmpty) {
      _countThisWindow++;
      inner.log(entry);
      return;
    }

    // Over the limit — queue it.
    if (_queue.length >= maxQueueSize) {
      _queue.removeFirst();
      _droppedCount++;
    }
    _queue.addLast(entry);
    _scheduleDrain();
  }

  /// Immediately flushes all queued entries, ignoring the rate limit.
  /// Useful for shutdown or crash scenarios where you want everything out.
  void flush() {
    _drainTimer?.cancel();
    _drainTimer = null;
    _emitDroppedSummary();
    while (_queue.isNotEmpty) {
      inner.log(_queue.removeFirst());
    }
  }

  void _scheduleDrain() {
    if (_drainTimer != null && _drainTimer!.isActive) return;
    _drainTimer = Timer(const Duration(milliseconds: 100), _drain);
  }

  void _drain() {
    final now = DateTime.now();
    if (now.difference(_windowStart).inMilliseconds >= 1000) {
      _windowStart = now;
      _countThisWindow = 0;
    }

    _emitDroppedSummary();

    // Drain up to the remaining budget.
    while (_queue.isNotEmpty && _countThisWindow < maxPerSecond) {
      _countThisWindow++;
      inner.log(_queue.removeFirst());
    }

    if (_queue.isNotEmpty) {
      _scheduleDrain();
    }
  }

  void _emitDroppedSummary() {
    if (_droppedCount == 0) return;
    final dropped = _droppedCount;
    _droppedCount = 0;
    _countThisWindow++;
    inner.log(
      LogEntry(
        level: LogLevel.warning,
        message: '... $dropped log entries dropped (throttled)',
        loggerName: 'ThrottledPrinter',
        time: DateTime.now(),
      ),
    );
  }
}
