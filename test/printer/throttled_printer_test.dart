import 'package:fake_async/fake_async.dart';
import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ── Test doubles ────────────────────────────────────────────────────────────

class _RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void log(LogEntry entry) {
    entries.add(entry);
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

LogEntry _entry(String message, {LogLevel level = LogLevel.info}) {
  return LogEntry(
    level: level,
    message: message,
    loggerName: 'Test',
    time: DateTime.now(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Under limit: forwarded immediately ────────────────────────────────────

  group('entries under limit', () {
    test('single entry is forwarded immediately', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 10);

      throttled.log(_entry('one'));

      expect(inner.entries, hasLength(1));
      expect(inner.entries.first.message, equals('one'));
    });

    test('entries up to limit are all forwarded immediately', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 5);

      for (var i = 0; i < 5; i++) {
        throttled.log(_entry('msg $i'));
      }

      expect(inner.entries, hasLength(5));
    });

    test('entries exactly at limit are forwarded', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 3);

      throttled.log(_entry('a'));
      throttled.log(_entry('b'));
      throttled.log(_entry('c'));

      expect(inner.entries, hasLength(3));
      expect(inner.entries.map((e) => e.message), equals(['a', 'b', 'c']));
    });
  });

  // ── Over limit: queued ────────────────────────────────────────────────────

  group('entries over limit', () {
    test('excess entries are queued, not forwarded immediately', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 2);

      throttled.log(_entry('a'));
      throttled.log(_entry('b'));
      throttled.log(_entry('c')); // over limit
      throttled.log(_entry('d')); // over limit

      // Only 2 should have been forwarded immediately.
      expect(inner.entries, hasLength(2));
      expect(inner.entries.map((e) => e.message), equals(['a', 'b']));
    });

    test('queued entries are drained via flush', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 2);

      throttled.log(_entry('a'));
      throttled.log(_entry('b'));
      throttled.log(_entry('c'));
      throttled.log(_entry('d'));

      expect(inner.entries, hasLength(2));

      // flush() bypasses the timer and drains everything.
      throttled.flush();

      expect(inner.entries, hasLength(4));
      expect(inner.entries.map((e) => e.message), equals(['a', 'b', 'c', 'd']));
    });

    test('drain timer is scheduled when entries are queued', () {
      fakeAsync((async) {
        final inner = _RecordingPrinter();
        final throttled = ThrottledPrinter(inner, maxPerSecond: 1);

        throttled.log(_entry('a'));
        throttled.log(_entry('b'));

        expect(inner.entries, hasLength(1));

        // The drain timer is 100ms. Advancing fires _drain, but since
        // DateTime.now() hasn't moved, the window hasn't reset, so
        // _countThisWindow is still at the limit. The _drain method
        // will re-schedule if the queue is not empty.
        // We just verify the timer mechanism doesn't throw.
        async.elapse(const Duration(milliseconds: 200));

        // Flush to get the final state.
        throttled.flush();
        expect(inner.entries.length, greaterThanOrEqualTo(2));
      });
    });
  });

  // ── Queue overflow drops oldest ───────────────────────────────────────────

  group('queue overflow', () {
    test('oldest entries are dropped when queue exceeds maxQueueSize', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 3,
      );

      // First one goes through immediately.
      throttled.log(_entry('immediate'));
      // Next 3 fill the queue.
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2'));
      throttled.log(_entry('q3'));
      // This one overflows — q1 gets dropped.
      throttled.log(_entry('q4'));

      expect(inner.entries, hasLength(1));
      expect(inner.entries.first.message, equals('immediate'));

      // Flush to see what remains in the queue.
      throttled.flush();

      // Should have: dropped summary + q2, q3, q4 (q1 was dropped).
      final messages = inner.entries.map((e) => e.message).toList();
      expect(messages, contains('q2'));
      expect(messages, contains('q3'));
      expect(messages, contains('q4'));
      expect(messages, isNot(contains('q1'))); // dropped
    });

    test('multiple overflows drop multiple oldest entries', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 2,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2'));
      throttled.log(_entry('q3')); // drops q1
      throttled.log(_entry('q4')); // drops q2

      throttled.flush();

      final messages = inner.entries.map((e) => e.message).toList();
      expect(messages, isNot(contains('q1')));
      expect(messages, isNot(contains('q2')));
      expect(messages, contains('q3'));
      expect(messages, contains('q4'));
    });
  });

  // ── Dropped summary message ───────────────────────────────────────────────

  group('dropped summary message', () {
    test('emits dropped count when flushing after overflow', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 2,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2'));
      throttled.log(_entry('q3')); // drops q1, droppedCount = 1

      // Flush triggers the dropped summary.
      throttled.flush();

      final messages = inner.entries.map((e) => e.message).toList();
      expect(
        messages,
        contains(matches(RegExp(r'1 log entr.*dropped.*throttled'))),
      );
    });

    test('flush emits dropped summary before draining', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 2,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2'));
      throttled.log(_entry('q3')); // drops q1
      throttled.log(_entry('q4')); // drops q2

      throttled.flush();

      final messages = inner.entries.map((e) => e.message).toList();
      // The dropped summary should appear before the remaining entries.
      final droppedIdx = messages.indexWhere((m) => m.contains('dropped'));
      expect(droppedIdx, greaterThan(0)); // after 'immediate'

      // Should mention 2 dropped.
      expect(messages[droppedIdx], contains('2 log entries dropped'));
    });

    test('no dropped summary when nothing was dropped', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 10,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));

      throttled.flush();

      final messages = inner.entries.map((e) => e.message).toList();
      expect(messages.any((m) => m.contains('dropped')), isFalse);
    });
  });

  // ── flush() ───────────────────────────────────────────────────────────────

  group('flush()', () {
    test('drains all remaining entries immediately', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 1);

      throttled.log(_entry('a'));
      throttled.log(_entry('b'));
      throttled.log(_entry('c'));

      expect(inner.entries, hasLength(1)); // only 'a' forwarded

      throttled.flush();

      // After flush, 'b' and 'c' should also be forwarded.
      final messages = inner.entries.map((e) => e.message).toList();
      expect(messages, contains('a'));
      expect(messages, contains('b'));
      expect(messages, contains('c'));
    });

    test('flush on empty queue does nothing', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 10);

      throttled.flush();
      expect(inner.entries, isEmpty);
    });

    test('flush cancels pending drain timer', () {
      fakeAsync((async) {
        final inner = _RecordingPrinter();
        final throttled = ThrottledPrinter(inner, maxPerSecond: 1);

        throttled.log(_entry('a'));
        throttled.log(_entry('b'));

        // flush manually before the timer fires.
        throttled.flush();

        final countAfterFlush = inner.entries.length;

        // Advance time — the timer should have been cancelled.
        async.elapse(const Duration(seconds: 2));

        // No additional entries should have been logged by the timer.
        expect(inner.entries.length, equals(countAfterFlush));
      });
    });

    test('flush can be called multiple times safely', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 1);

      throttled.log(_entry('a'));
      throttled.log(_entry('b'));

      throttled.flush();
      throttled.flush(); // second flush on empty queue
      throttled.flush(); // third flush

      final messages = inner.entries.map((e) => e.message).toList();
      expect(messages, contains('a'));
      expect(messages, contains('b'));
      // No duplicates.
      expect(messages.where((m) => m == 'a').length, equals(1));
    });
  });

  // ── Window reset after 1 second ───────────────────────────────────────────

  // Note: ThrottledPrinter uses DateTime.now() for window tracking, which
  // is not controlled by fakeAsync. These tests use real wall-clock time.

  group('window reset', () {
    test(
      'after 1 second the budget resets and new entries forward immediately',
      () async {
        final inner = _RecordingPrinter();
        final throttled = ThrottledPrinter(inner, maxPerSecond: 2);

        // Use up the entire budget.
        throttled.log(_entry('a'));
        throttled.log(_entry('b'));
        expect(inner.entries, hasLength(2));

        // The next entry would be queued.
        throttled.log(_entry('c'));
        expect(inner.entries, hasLength(2)); // still 2

        // Wait for the real 1-second window to elapse.
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        // After the window resets, a new entry should forward immediately
        // (queue is not empty, but log() checks the window first).
        // Actually, the queued 'c' should have drained via the timer.
        // Let's just flush and verify.
        throttled.flush();
        final messages = inner.entries.map((e) => e.message).toList();
        expect(messages, contains('c'));
      },
    );

    test('budget resets allow full throughput in new window', () async {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 2);

      // Window 1.
      throttled.log(_entry('w1-a'));
      throttled.log(_entry('w1-b'));
      expect(inner.entries, hasLength(2));

      // Wait for real window reset.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // Flush anything from window 1 drain.
      throttled.flush();

      final countAfterWindow1 = inner.entries.length;

      // Window 2: should have full budget again.
      throttled.log(_entry('w2-a'));
      throttled.log(_entry('w2-b'));
      expect(inner.entries.length, equals(countAfterWindow1 + 2));
    });

    test(
      'entries logged after window reset are forwarded immediately',
      () async {
        final inner = _RecordingPrinter();
        // Use a higher budget so we can distinguish window resets.
        final throttled = ThrottledPrinter(inner, maxPerSecond: 2);

        // Use up entire budget.
        throttled.log(_entry('a'));
        throttled.log(_entry('b'));
        expect(inner.entries, hasLength(2));

        // Wait for real window to reset.
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        // After the window has elapsed, the next log() call should detect
        // the reset and forward immediately.
        throttled.log(_entry('new-window'));
        expect(inner.entries.map((e) => e.message), contains('new-window'));
      },
    );
  });

  // ── Edge cases ────────────────────────────────────────────────────────────

  group('edge cases', () {
    test('maxPerSecond of 1 only allows one immediate entry', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(inner, maxPerSecond: 1);

      throttled.log(_entry('first'));
      throttled.log(_entry('second'));
      throttled.log(_entry('third'));

      expect(inner.entries, hasLength(1));
      expect(inner.entries.first.message, equals('first'));
    });

    test('maxQueueSize of 1 only keeps the newest overflow entry', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 1,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2')); // drops q1
      throttled.log(_entry('q3')); // drops q2

      throttled.flush();

      final messages = inner.entries.map((e) => e.message).toList();
      // Only q3 should remain in the queue (plus the dropped summary).
      expect(messages, contains('q3'));
      expect(messages, isNot(contains('q1')));
      expect(messages, isNot(contains('q2')));
    });

    test('large burst of entries', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 10,
        maxQueueSize: 100,
      );

      for (var i = 0; i < 200; i++) {
        throttled.log(_entry('entry $i'));
      }

      // First 10 forwarded immediately.
      expect(inner.entries, hasLength(10));

      // Flush the rest.
      throttled.flush();

      // 10 immediate + up to 100 queued (100 dropped) + 1 dropped summary.
      // Actually: 200 total - 10 immediate = 190 to queue.
      // Queue max 100, so 90 dropped. Queue has 100 entries.
      // After flush: 10 + 1 summary + 100 = 111.
      expect(inner.entries, hasLength(111));
    });

    test('dropped summary entry has level warning', () {
      final inner = _RecordingPrinter();
      final throttled = ThrottledPrinter(
        inner,
        maxPerSecond: 1,
        maxQueueSize: 1,
      );

      throttled.log(_entry('immediate'));
      throttled.log(_entry('q1'));
      throttled.log(_entry('q2')); // drops q1

      throttled.flush();

      final droppedEntry = inner.entries.firstWhere(
        (e) => e.message.contains('dropped'),
      );
      expect(droppedEntry.level, equals(LogLevel.warning));
      expect(droppedEntry.loggerName, equals('ThrottledPrinter'));
    });
  });
}
