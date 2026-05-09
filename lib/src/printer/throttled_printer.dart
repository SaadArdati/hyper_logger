import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

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
  DateTime _windowStart = clock.now();

  ThrottledPrinter(
    this.inner, {
    this.maxPerSecond = 30,
    this.maxQueueSize = 500,
  }) {
    if (maxPerSecond < 1) {
      throw ArgumentError.value(
        maxPerSecond,
        'maxPerSecond',
        'must be >= 1; a non-positive value would prevent the queue from '
            'ever draining',
      );
    }
    if (maxQueueSize < 1) {
      throw ArgumentError.value(
        maxQueueSize,
        'maxQueueSize',
        'must be >= 1; a non-positive value would crash on overflow drop',
      );
    }
  }

  @override
  void log(LogEntry entry) {
    final now = clock.now();

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
    _emitDroppedSummary(consumeBudget: false);
    while (_queue.isNotEmpty) {
      inner.log(_queue.removeFirst());
    }
  }

  /// Cancels the in-flight drain timer (no-op if none is scheduled)
  /// and disposes the wrapped inner printer.
  ///
  /// Round-9 audit fix (M6): without this, replacing the global
  /// printer via `HyperLogger.init(printer: ...)` would leak the
  /// drain `Timer`, which would keep firing on the orphan instance
  /// indefinitely.
  @override
  void dispose() {
    _drainTimer?.cancel();
    _drainTimer = null;
    inner.dispose();
  }

  void _scheduleDrain() {
    if (_drainTimer?.isActive ?? false) return;
    _drainTimer = Timer(const Duration(milliseconds: 100), _drain);
  }

  void _drain() {
    final now = clock.now();
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

  void _emitDroppedSummary({bool consumeBudget = true}) {
    if (_droppedCount == 0) return;
    final dropped = _droppedCount;
    _droppedCount = 0;
    // Intentional: the synthetic summary always emits, even when the
    // window is at cap. Suppressing it would hide the loss; overshoot
    // is at most one record per window.
    //
    // Round-9 audit fix (L9): when called from `flush()`, do NOT
    // consume a budget slot — `flush()` is meant to bypass the rate
    // limit entirely, and incrementing `_countThisWindow` here would
    // make the next regular log call after `flush()` hit the cap one
    // record early.
    if (consumeBudget) {
      _countThisWindow++;
    }
    inner.log(
      LogEntry(
        level: LogLevel.warning,
        message: '... $dropped log entries dropped (throttled)',
        loggerName: 'ThrottledPrinter',
        time: clock.now(),
      ),
    );
  }
}
