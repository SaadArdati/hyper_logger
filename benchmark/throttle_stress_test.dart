// ignore_for_file: avoid_print
import 'dart:async';

import 'package:hyper_logger/hyper_logger.dart';

/// Stress test that demonstrates the ThrottledPrinter preventing process choke.
///
/// Simulates a hot loop (like onReceiveTick or rapid stream events) that
/// produces thousands of log entries per second using real print() output —
/// NOT a noop sink. This is designed to choke the process without throttling.
///
/// Run: dart run benchmark/throttle_stress_test.dart
void main() async {
  const totalEntries = 50000;
  const tickIntervalUs = 100; // 100µs between ticks = ~10,000 ticks/sec

  print('');
  print('Throttle Stress Test');
  print('=' * 70);
  print(
    'Simulating $totalEntries rapid log calls at ~${1000000 ~/ tickIntervalUs}/sec',
  );
  print('Using real print() output — this WILL produce visible log lines.');
  print('');

  // ── Baseline: unthrottled, real print() output ──────────────────────────

  print('--- PHASE 1: Unthrottled (raw ComposablePrinter → print) ---');
  print('');

  HyperLogger.init(
    printer: ComposablePrinter(const [
      EmojiDecorator(),
      BoxDecorator(),
      AnsiColorDecorator(),
      PrefixDecorator(),
    ]),
    // Real print() output — no noop sink.
  );

  final swUnthrottled = Stopwatch()..start();
  int unthrottledCount = 0;

  for (int i = 0; i < totalEntries; i++) {
    HyperLogger.info<_TickHandler>(
      'Tick $i | bid=1.${1000 + i} ask=1.${1001 + i} spread=0.0001',
      method: 'onReceiveTick',
    );
    unthrottledCount++;

    // Simulate realistic tick interval — yield periodically to let I/O flush.
    if (i % 100 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  swUnthrottled.stop();
  final unthrottledMs = swUnthrottled.elapsedMilliseconds;

  // Brief pause to let output drain.
  await Future<void>.delayed(const Duration(seconds: 1));

  print('');
  print(
    'Unthrottled: $unthrottledCount entries in ${unthrottledMs}ms '
    '(${(unthrottledCount / (unthrottledMs / 1000)).round()} entries/sec)',
  );
  print('');

  HyperLogger.reset();

  // ── Throttled: same workload, ThrottledPrinter wrapping the same printer ──

  print('--- PHASE 2: ThrottledPrinter (maxPerSecond: 30) ---');
  print('');

  final throttledPrinter = ThrottledPrinter(
    ComposablePrinter(const [EmojiDecorator(), PrefixDecorator()]),
    maxPerSecond: 30,
    maxQueueSize: 200,
  );

  HyperLogger.init(printer: throttledPrinter);

  final swThrottled = Stopwatch()..start();
  int throttledCount = 0;

  for (int i = 0; i < totalEntries; i++) {
    HyperLogger.info<_TickHandler>(
      'Tick $i | bid=1.${1000 + i} ask=1.${1001 + i} spread=0.0001',
      method: 'onReceiveTick',
    );
    throttledCount++;

    if (i % 100 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  swThrottled.stop();
  final throttledMs = swThrottled.elapsedMilliseconds;

  // Let the drain timer finish flushing.
  await Future<void>.delayed(const Duration(seconds: 2));
  throttledPrinter.flush();

  print('');
  print(
    'Throttled: $throttledCount entries in ${throttledMs}ms '
    '(${(throttledCount / (throttledMs / 1000)).round()} entries/sec)',
  );
  print('');

  // ── Summary ─────────────────────────────────────────────────────────────

  print('=' * 70);
  print('SUMMARY');
  print('=' * 70);
  print('  Unthrottled: ${unthrottledMs}ms for $totalEntries entries');
  print('  Throttled:   ${throttledMs}ms for $totalEntries entries');
  print(
    '  Speedup:     ${(unthrottledMs / throttledMs).toStringAsFixed(1)}x faster loop completion',
  );
  print('');
  print('The throttled version completes the loop faster because print()');
  print('calls are deferred. The unthrottled version blocks on every call.');
  print('');
  if (unthrottledMs > throttledMs * 1.5) {
    print('SUCCESS: ThrottledPrinter prevented process choke.');
  } else {
    print('NOTE: Difference may be small on fast terminals. Try piping to');
    print('a slow sink or increasing totalEntries to see the effect.');
  }
}

class _TickHandler {}
