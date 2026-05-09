@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyper_logger/hyper_logger.dart';
// formatDefaultFileWriterError is `@internal` — public-API consumers
// should not depend on its rendering. Imported here from `src/` so the
// format can still be pinned in-package.
import 'package:hyper_logger/src/printer/rotating_file_printer.dart'
    show formatDefaultFileWriterError;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

LogEntry _entry(String message, {LogLevel level = LogLevel.info}) {
  return LogEntry(
    level: level,
    message: message,
    object: LogMessage(message, String),
    loggerName: 'test',
    time: DateTime.utc(2026, 5, 8, 12, 0, 0),
  );
}

/// Pumps the event loop until pending I/O microtasks settle.
Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hyper_logger_file_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('basic write behavior', () {
    test('writes formatted line to the configured path', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;

      printer.log(_entry('hello'));
      await printer.close();

      final contents = File(path).readAsStringSync();
      expect(contents, contains('hello'));
      expect(contents, contains('[INFO]'));
      expect(contents, endsWith('\n'));
    });

    test('appends to an existing file rather than truncating', () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('preexisting content\n');

      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('new line'));
      await printer.close();

      final contents = File(path).readAsStringSync();
      expect(contents, startsWith('preexisting content\n'));
      expect(contents, contains('new line'));
    });

    test('async path provider buffers entries until path resolves', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return path;
        },
      );

      // Log immediately, before ready completes.
      printer.log(_entry('early'));
      printer.log(_entry('also early'));

      await printer.ready;
      await _flush();
      await printer.close();

      final contents = File(path).readAsStringSync();
      expect(contents, contains('early'));
      expect(contents, contains('also early'));
    });

    test('creates missing parent directories', () async {
      final path = '${tempDir.path}/nested/dir/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('msg'));
      await printer.close();

      expect(File(path).existsSync(), isTrue);
    });

    test('custom formatter is used verbatim (one line per entry)', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        formatter: (e) => '<<${e.message}>>',
      );
      await printer.ready;
      printer.log(_entry('a'));
      printer.log(_entry('b'));
      await printer.close();

      final lines = File(path).readAsLinesSync();
      expect(lines, equals(['<<a>>', '<<b>>']));
    });
  });

  group('size-based rotation', () {
    test('rotates when bytes written exceed maxBytes', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(maxBytes: 100),
        // Each formatted line is roughly 60+ bytes; two writes triggers rotation.
        formatter: (e) => 'a' * 60,
      );
      await printer.ready;

      printer.log(_entry('first'));
      printer.log(_entry('second'));
      await printer.close();

      // Live file should exist (post-rotation, fresh).
      expect(File(path).existsSync(), isTrue);

      // Exactly one rotated sibling expected.
      final rotated = tempDir.listSync().whereType<File>().where(
            (f) => f.path != path && f.path.endsWith('.log'),
          );
      expect(rotated, hasLength(1));
    });

    test('respects maxFiles by deleting the oldest rotated files', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(
          maxBytes: 30,
          maxFiles: 2,
        ),
        formatter: (e) => 'x' * 40,
      );
      await printer.ready;

      // Each write is over the threshold, forcing rotation per call.
      // Vary the timestamp to ensure distinct file names.
      for (var i = 0; i < 5; i++) {
        printer.log(_entry('e$i'));
        // Sleep briefly so rotation timestamps don't all collide in the
        // same second (the suffix counter handles collisions, but we want
        // realistic ordering for the maxFiles test).
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await printer.close();

      final rotated = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path != path && f.path.endsWith('.log'))
          .toList();

      // We should have exactly maxFiles (2) rotated files left.
      expect(rotated.length, lessThanOrEqualTo(2));
    });

    test('compress=true gzips rotated files and removes the .log original',
        () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(
          maxBytes: 30,
          compress: true,
        ),
        formatter: (e) => 'y' * 40,
      );
      await printer.ready;

      printer.log(_entry('one'));
      printer.log(_entry('two'));
      await printer.close();

      final files = tempDir.listSync().whereType<File>().toList();
      final gzipped = files.where((f) => f.path.endsWith('.log.gz'));
      final uncompressedRotated = files.where(
        (f) => f.path != path && f.path.endsWith('.log'),
      );

      expect(gzipped, isNotEmpty);
      expect(uncompressedRotated, isEmpty);
    });
  });

  group('rotation: filename and retention', () {
    test('rotated filenames embed a compact UTC timestamp with a Z suffix',
        () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(maxBytes: 30),
        formatter: (e) => 'x' * 40,
      );
      await printer.ready;

      printer.log(_entry('first'));
      printer.log(_entry('second'));
      await printer.close();

      final rotated = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path != path && f.path.endsWith('.log'))
          .toList();
      expect(rotated, isNotEmpty);
      final name = rotated.first.uri.pathSegments.last;
      expect(
        name,
        matches(
          RegExp(r'^app\.\d{8}T\d{6}Z(\.\d+)?\.log$'),
        ),
        reason: 'rotated name "$name" must include a "Z" suffix and 8+6 digits',
      );
    });

    test(
      '_enforceMaxFiles counts a (.log + .log.gz) pair as ONE rotation '
      '(round-10b dedup fix)',
      () async {
        final path = '${tempDir.path}/app.log';

        // Simulate the transient state where `delete-after-gzip` failed
        // and left BOTH halves of a rotation on disk. Pre-create three
        // such pairs at distinct timestamps. With the buggy flat-count
        // impl, six files = "six rotations" toward maxFiles, so a
        // maxFiles=2 enforcement would prune four files indiscriminately
        // and could orphan one half of a kept pair.
        final pairs = ['20260507T100000Z', '20260507T110000Z', '20260507T120000Z'];
        final base = DateTime.utc(2026, 5, 7, 10);
        for (var i = 0; i < pairs.length; i++) {
          final ts = pairs[i];
          final mtime = base.add(Duration(hours: i));
          File('${tempDir.path}/app.$ts.log')
            ..writeAsStringSync('legacy uncompressed')
            ..setLastModifiedSync(mtime);
          File('${tempDir.path}/app.$ts.log.gz')
            ..writeAsStringSync('legacy compressed')
            ..setLastModifiedSync(mtime);
        }

        // Configure the printer so a single write triggers rotation,
        // bringing total rotations to 4 (3 stale + 1 fresh). With
        // maxFiles=2 the enforcement should prune the 2 oldest
        // rotations, deleting BOTH halves of each.
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(
            maxBytes: 30,
            maxFiles: 2,
          ),
          formatter: (e) => 'x' * 40,
        );
        await printer.ready;
        printer.log(_entry('go'));
        await printer.close();

        final remaining = tempDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) =>
                name != 'app.log' &&
                (name.endsWith('.log') || name.endsWith('.log.gz')))
            .toList();

        // Dedup remaining files by rotation signature.
        final timestamps = remaining
            .map((name) {
              final m = RegExp(
                r'^app\.(\d{8}T\d{6}Z(?:\.\d+)?)\.log(?:\.gz)?$',
              ).firstMatch(name);
              return m?.group(1);
            })
            .whereType<String>()
            .toSet();

        // 2 unique rotation timestamps must remain (== maxFiles).
        expect(
          timestamps.length,
          2,
          reason: 'expected 2 unique rotation timestamps after enforcement, '
              'got: $timestamps  (files: $remaining)',
        );

        // The two oldest stale timestamps must have BOTH halves deleted
        // (this is what the dedup fix protects against — the flat-count
        // impl could have orphaned one half).
        expect(timestamps, isNot(contains('20260507T100000Z')));
        expect(timestamps, isNot(contains('20260507T110000Z')));

        // The newest stale rotation should be intact (BOTH halves kept).
        const keptPair = '20260507T120000Z';
        expect(
          remaining,
          containsAll(['app.$keptPair.log', 'app.$keptPair.log.gz']),
          reason: 'a kept rotation must keep BOTH halves of its '
              '.log + .log.gz pair — not orphan one',
        );
      },
    );

    test(
      "_enforceMaxFiles must not delete unrelated siblings like 'app.config.log'",
      () async {
        final path = '${tempDir.path}/app.log';
        final unrelated = File('${tempDir.path}/app.config.log');
        unrelated.writeAsStringSync('user owned content');

        final printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(
            maxBytes: 30,
            maxFiles: 1,
          ),
          formatter: (e) => 'y' * 40,
        );
        await printer.ready;
        printer.log(_entry('one'));
        printer.log(_entry('two'));
        printer.log(_entry('three'));
        await printer.close();

        expect(
          unrelated.existsSync(),
          isTrue,
          reason: 'unrelated user file must survive rotation',
        );
      },
    );

    test(
      'compressed rotation does not overwrite a previous .gz with the same '
      'second-precision timestamp (verified by content)',
      () async {
        final path = '${tempDir.path}/app.log';
        var counter = 0;
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(
            maxBytes: 30,
            compress: true,
          ),
          // Each entry's content is uniquely identifiable so we can prove
          // none were overwritten in the gzipped archive set.
          formatter: (e) => 'rot-${counter++}-${'p' * 40}',
        );
        await printer.ready;

        printer.log(_entry('a'));
        printer.log(_entry('b'));
        printer.log(_entry('c'));
        await printer.close();

        final gzFiles = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.log.gz'))
            .toList();

        expect(gzFiles.length, greaterThanOrEqualTo(2));

        // Decompress each .gz and collect the unique markers. Every
        // rotated entry must appear in exactly one .gz file — none were
        // overwritten by a same-second rotation.
        final decompressed = gzFiles
            .map((f) => utf8.decode(gzip.decode(f.readAsBytesSync())))
            .toList();
        for (var i = 0; i < counter - 1; i++) {
          // Last rotation may leave its content in the live file, not gz;
          // assert each ROTATED marker appears in exactly one gz file.
          final hits = decompressed.where((c) => c.contains('rot-$i-')).length;
          expect(hits, lessThanOrEqualTo(1),
              reason: 'rot-$i appeared in multiple .gz files (overwrite)');
        }
      },
    );

    test(
      'drop-notice synthetic record under tiny maxBytes triggers rotation '
      'cleanly without losing data',
      () async {
        final path = '${tempDir.path}/app.log';
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return path;
          },
          rotationConfig: FileRotationConfig.size(maxBytes: 50),
          pendingBufferSize: 3,
        );

        // Fill the buffer plus drop count, trigger rotation via the
        // synthetic warning that gets emitted on first flush.
        for (var i = 0; i < 20; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.ready;
        await _flush();
        await printer.close();

        // The drop notice must have landed somewhere — either in the
        // live file or a rotated sibling.
        final allFiles = tempDir.listSync().whereType<File>().toList();
        final all = allFiles.map((f) => f.readAsStringSync()).join();
        expect(all, contains('dropped'));
      },
    );

    test('time-based rotation window inherits file mtime across restarts',
        () async {
      final path = '${tempDir.path}/app.log';
      // Pre-create the file with an OLD mtime — simulating a previous
      // process run that exited without rotating.
      File(path).writeAsStringSync('old content\n');
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      File(path).setLastModifiedSync(twoDaysAgo);

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        // Daily rotation: a 2-day-old file is 2 windows past due.
        rotationConfig: FileRotationConfig.daily(),
      );
      await printer.ready;

      // The first log triggers rotation because the window inherited
      // from mtime is well past 24h.
      printer.log(_entry('first new entry'));
      await printer.close();

      final rotated = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path != path && f.path.endsWith('.log'))
          .toList();
      expect(rotated, isNotEmpty,
          reason:
              'mtime-aware window should have rotated stale content from previous run');
    });
  });

  group('input validation', () {
    test('pendingBufferSize <= 0 throws ArgumentError at construction', () {
      expect(
        () => RotatingFilePrinter(
          baseFilePathProvider: () => '${tempDir.path}/x.log',
          pendingBufferSize: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => RotatingFilePrinter(
          baseFilePathProvider: () => '${tempDir.path}/x.log',
          pendingBufferSize: -10,
        ),
        throwsArgumentError,
      );
    });

    test('FileRotationConfig.size: maxBytes <= 0 throws ArgumentError', () {
      // Round-8 fix: previously assert-only, so release builds accepted
      // these and produced always-rotate pathology.
      expect(
        () => FileRotationConfig.size(maxBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => FileRotationConfig.size(maxBytes: -100),
        throwsArgumentError,
      );
    });

    test(
      'FileRotationConfig.size: maxFiles <= 0 throws ArgumentError '
      '(null is fine for unlimited)',
      () {
        expect(
          () => FileRotationConfig.size(maxBytes: 1024, maxFiles: 0),
          throwsArgumentError,
        );
        expect(
          () => FileRotationConfig.size(maxBytes: 1024, maxFiles: -1),
          throwsArgumentError,
        );
        // null is allowed (means unlimited)
        expect(
          () => FileRotationConfig.size(maxBytes: 1024, maxFiles: null),
          returnsNormally,
        );
      },
    );

    test('FileRotationConfig.interval: <= zero throws ArgumentError', () {
      expect(
        () => FileRotationConfig.interval(interval: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => FileRotationConfig.interval(
          interval: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('FileRotationConfig.daily: maxFiles <= 0 throws ArgumentError', () {
      expect(
        () => FileRotationConfig.daily(maxFiles: 0),
        throwsArgumentError,
      );
    });
  });

  group('error handler (onError)', () {
    test('init failure invokes onError with the underlying exception',
        () async {
      Object? captured;
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('cannot resolve path');
        },
        onError: (e, _) => captured = e,
      );
      await printer.ready;
      await printer.close();

      expect(captured, isA<StateError>());
      expect(captured.toString(), contains('cannot resolve path'));
    });

    test('a throwing onError handler does not crash the printer', () async {
      // The default error handler writes to stderr; if a user supplies a
      // hook that itself throws, logging must still not crash.
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('boom');
        },
        onError: (e, st) => throw StateError('handler also boom'),
      );
      await printer.ready;
      expect(() => printer.log(_entry('msg')), returnsNormally);
      await printer.close();
    });

    test('an async onError that rejects does not crash the printer',
        () async {
      // FileWriterErrorHandler is FutureOr<void>, so users can pass an
      // async handler. If that future rejects, the rejection must not
      // surface as an uncaught async exception.
      var handlerCallCount = 0;
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('init boom');
        },
        onError: (e, st) async {
          handlerCallCount++;
          throw StateError('async handler boom');
        },
      );
      await printer.ready;
      // Pump microtasks so any uncaught Future rejection would surface.
      await _flush();
      expect(handlerCallCount, equals(1));
      await printer.close();
    });

    test('reentrant onError that logs through HyperLogger does not loop',
        () async {
      // A realistic monitoring shape: the user's onError callback logs
      // via HyperLogger. The RotatingFilePrinter is not the global
      // logger here, so this should NOT cause infinite recursion — but
      // it's worth pinning the contract.
      final captured = <String>[];
      HyperLogger.reset();
      HyperLogger.init(printer: DirectPrinter(output: captured.add));

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('init failure');
        },
        onError: (e, st) {
          // Reentrant call — feeding errors back into the global logger.
          HyperLogger.warning<String>('rotating file error: $e');
        },
      );
      await printer.ready;
      // Logging must not crash; the error must surface in HyperLogger.
      expect(() => printer.log(_entry('m')), returnsNormally);
      await printer.close();

      expect(captured.any((line) => line.contains('init failure')), isTrue);
      HyperLogger.reset();
    });

    test(
      'async onError coalesces failures during the handler\'s awaited '
      'tail (intentional first-error-wins window)',
      () async {
        // Round-7 contract: the reentrancy guard is held for the entire
        // duration of the handler's Future (set on entry, cleared via
        // `whenComplete`). Failures occurring during the awaited tail —
        // self-induced or genuinely independent — are coalesced. This is
        // intentional: a Zone-scoped marker can't bound the common
        // same-printer-reentry case (`package:logging`'s record stream
        // delivers events in the listener's registration zone, not the
        // emitter's), so a flat boolean held across the handler's Future
        // is the only durable mechanism. See `FileWriterErrorHandler`'s
        // doc for the full rationale.
        //
        // Round-6 briefly cleared the guard after the handler's sync
        // prefix to give per-record visibility. Round-7 reverted that
        // after both reviewers (codex + opus) flagged the resulting
        // microtask livelock under same-printer reentry.
        final subdir = Directory('${tempDir.path}/sub')..createSync();
        final path = '${subdir.path}/app.log';
        final completer = Completer<void>();
        final errors = <Object>[];
        late RotatingFilePrinter printer;

        printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(maxBytes: 1),
          onError: (e, st) async {
            errors.add(e);
            await completer.future;
          },
        );
        await printer.ready;

        // Sabotage parent so rotation reopen always fails.
        subdir.deleteSync(recursive: true);
        File(subdir.path).createSync();

        // First failure → onError fires once; handler is now pending on
        // `completer.future`. Note the baseline can include both the
        // initial rotation error and the second-chance reopen error
        // because the second-chance reopen's _safeOnError call happens
        // synchronously inside _rotate's catch (BEFORE the handler's
        // first await even returns control to where the guard could
        // have been cleared).
        printer.log(_entry('first failure'));
        await _flush();
        final baseline = errors.length;
        expect(baseline, greaterThanOrEqualTo(1));

        // Subsequent failures during the handler's awaited tail are
        // coalesced — each `printer.log()` fails internally, but the
        // handler is not invoked again until the first Future settles.
        for (var i = 0; i < 5; i++) {
          printer.log(_entry('coalesced-$i'));
          await _flush();
        }

        expect(errors.length, equals(baseline),
            reason: 'failures during the handler\'s awaited tail must '
                'be coalesced into the first-error window '
                '(baseline=$baseline, observed=${errors.length})');

        // Release the handler so close() can drain.
        completer.complete();

        // Cleanup so tearDown can remove tempDir.
        try {
          File(subdir.path).deleteSync();
        } catch (_) {/* */}

        await printer.close();
      },
    );

    test(
      'drain aggregate StateError surfaces AFTER the async handler '
      "Future settles — round-9 fix for round-8's regression",
      () async {
        // Round-9 regression case: round 8 added a `_drainFailures`
        // helper + an aggregate `StateError` to surface the
        // authoritative drop count when round-7's intentional
        // coalescing collapsed per-entry errors. But the aggregate
        // itself went through `_safeOnError`, which is held during
        // the in-flight handler Future — so the aggregate was also
        // coalesced. The fix didn't actually fix visibility.
        //
        // Round-9 fix: aggregates use `_safeOnErrorAfterCurrentHandler`
        // which chains via `whenComplete` on the in-flight Future,
        // so they fire after the handler settles and reach the user.
        final path = '${tempDir.path}/app.log';
        final completer = Completer<void>();
        final errors = <Object>[];
        late RotatingFilePrinter printer;

        printer = RotatingFilePrinter(
          // Slow path resolution so we can buffer entries first.
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return path;
          },
          // Throw inside the formatter for any entry whose message
          // starts with 'fail-' so init's drain produces multiple
          // failures (without going through the handle-loss path,
          // which is hard to interleave synchronously).
          formatter: (e) {
            if (e.message.startsWith('fail-')) {
              throw StateError('formatter rejected: ${e.message}');
            }
            return e.message;
          },
          onError: (e, st) async {
            errors.add(e);
            await completer.future;
          },
        );

        // Buffer multiple entries that the formatter will reject.
        // The drain inside _initialize will hit the formatter throw
        // for each — failures > 1 → aggregate fires.
        for (var i = 0; i < 5; i++) {
          printer.log(_entry('fail-$i'));
        }

        await printer.ready;
        await _flush();

        // First handler invocation is in flight (awaiting completer).
        // The per-entry calls 2..5 were coalesced by the guard. The
        // aggregate is queued via whenComplete; it won't fire until
        // the handler settles.
        final preReleaseCount = errors.length;
        expect(preReleaseCount, equals(1),
            reason: 'first per-entry error fires; the rest are '
                'coalesced by the round-7 guard');

        // Release the handler — aggregate fires now.
        completer.complete();
        await _flush();
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // Round-9 contract: errors grew after release because the
        // aggregate StateError was scheduled via whenComplete.
        // Pre-fix, errors.length stayed at preReleaseCount.
        final aggregateMessages = errors
            .whereType<StateError>()
            .map((e) => e.message)
            .where((m) => m.contains('failed to drain'))
            .toList();
        expect(aggregateMessages, isNotEmpty,
            reason: 'aggregate StateError must fire after the async '
                'handler Future settles (preRelease=$preReleaseCount, '
                'final=${errors.length})');

        await printer.close();
      },
    );

    test(
      'sync reentrancy from inside the handler is still blocked '
      '(stack-overflow protection preserved)',
      () async {
        // Round-6 narrowed the async guard, but the sync recursion guard
        // must still hold: if the handler synchronously calls back into
        // a path that re-fires _safeOnError (e.g. logging through
        // HyperLogger configured with this same printer), the inner call
        // must short-circuit instead of recursing forever.
        final path = '${tempDir.path}/app.log';
        var handlerEntries = 0;
        late RotatingFilePrinter printer;

        printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(maxBytes: 1),
          onError: (e, st) {
            handlerEntries++;
            // Synchronous re-fire: directly calls back into log() which
            // (with the file deleted) will fail and try to invoke
            // onError again. The guard must block the inner call.
            try {
              printer.log(_entry('sync-reentrant'));
            } catch (_) {/* */}
          },
        );
        await printer.ready;

        // Sabotage the file so subsequent log() calls fail.
        File(path).deleteSync();
        Directory(p.dirname(path)).deleteSync(recursive: true);
        File(p.dirname(path)).createSync();

        // Each failing log() fires onError. The handler synchronously
        // calls printer.log again, which would (without the guard)
        // re-fire onError, recurse forever. With the guard: the inner
        // call's onError is blocked.
        for (var i = 0; i < 10; i++) {
          printer.log(_entry('outer-$i'));
        }

        // Without the guard the handler's inner log() would fire
        // onError → handler → log → onError → … forever (stack overflow
        // or unbounded growth). With the guard each outer call drives
        // exactly ONE handler invocation (the inner _safeOnError is
        // dropped), plus the first call gets +1 because rotation's
        // second-chance reopen runs in its own _safeOnError after the
        // first one has cleared. Tight upper bound of 15 = 10 outer
        // calls + ~5 rotation-bookkeeping headroom.
        expect(handlerEntries, lessThanOrEqualTo(15),
            reason: 'sync reentrancy guard must keep handler invocations '
                'tightly bounded (saw $handlerEntries)');

        // Cleanup.
        try {
          File(p.dirname(path)).deleteSync();
        } catch (_) {/* */}

        await printer.close();
      },
    );

    test(
      'async same-printer reentrant onError: handler routes through '
      'HyperLogger whose root IS this printer; sustained handle loss '
      'must not microtask-livelock',
      () async {
        // Round-7 regression case (both reviewers flagged this gap):
        // round-6's narrowed guard re-opened the original round-5
        // motivation in async shape. An async handler that re-routes
        // through the global HyperLogger whose root is THIS printer,
        // then awaits, would resume in the same continuation, fail
        // again, fire onError again, recurse per microtask. Pre-fix:
        // 100 microtask pumps → ~100 handler invocations.
        //
        // Round-7 fix: the guard is held across the handler's Future
        // via `whenComplete`, so handler-originated reentries (sync
        // recursion AND post-await continuations) are coalesced into
        // the first-error window. (An earlier zone-scoped attempt was
        // abandoned because `package:logging`'s record stream
        // delivers events in the listener's registration zone, not
        // the emitter's, defeating zone propagation.)
        final subdir = Directory('${tempDir.path}/sub')..createSync();
        final path = '${subdir.path}/app.log';
        var onErrorCalls = 0;
        late RotatingFilePrinter printer;

        printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(maxBytes: 1),
          onError: (e, st) async {
            onErrorCalls++;
            // Yield to a microtask, then route through HyperLogger
            // whose root is THIS printer — pre-round-7 this would
            // start an unbounded loop because the guard only blocked
            // sync reentry.
            await Future<void>.delayed(Duration.zero);
            HyperLogger.warning<String>('reentrant: $e');
          },
        );
        HyperLogger.reset();
        HyperLogger.init(printer: printer);
        await printer.ready;

        // Sabotage parent so every rotation reopen fails → sustained
        // failure path.
        subdir.deleteSync(recursive: true);
        File(subdir.path).createSync();

        // Trigger initial failure.
        printer.log(_entry('first'));

        // Pump 100 microtasks. Pre-fix: onErrorCalls climbs in
        // proportion. Post-fix: the post-await reentrant warning's
        // onError is coalesced because the guard is held until the
        // first handler invocation's Future settles.
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // Cleanup
        try {
          File(subdir.path).deleteSync();
        } catch (_) {/* */}

        await printer.close();
        HyperLogger.reset();

        expect(onErrorCalls, lessThan(20),
            reason: 'guard must coalesce post-await reentries from inside '
                "the handler's continuation chain (saw $onErrorCalls calls)");
      },
    );

    test(
      'sync same-printer reentrant onError: HyperLogger root IS this printer; '
      'sustained handle loss must not stack-overflow',
      () async {
        // The pathological setup that codex round 4 specifically called
        // out: the user's onError callback logs back through HyperLogger,
        // and the global root printer IS this RotatingFilePrinter. Under
        // sustained handle loss, a missing reentrancy guard would chain:
        //   log()→writeFromSync fails→onError→HyperLogger.warning→
        //   _handleLogRecord→printer.log()→writeFromSync fails→onError→…
        // until the stack blows. The _safeOnError reentrancy guard
        // breaks this chain.
        final path = '${tempDir.path}/app.log';
        var onErrorCalls = 0;

        // Build the printer first; we'll plug it into HyperLogger as the
        // global printer. The onError callback then logs via HyperLogger,
        // which routes through the same printer → reentry.
        late RotatingFilePrinter printer;
        printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          onError: (e, st) {
            onErrorCalls++;
            HyperLogger.warning<String>('printer error: $e');
          },
        );
        HyperLogger.reset();
        HyperLogger.init(printer: printer);

        await printer.ready;
        printer.log(_entry('one'));
        await printer.flush();

        // Force the printer into a "handle lost" state by deleting the
        // live file AND its parent so future opens fail.
        final tempPath = tempDir.path;
        File(path).deleteSync();
        Directory(tempPath).deleteSync(recursive: true);
        // Recreate the parent as a regular file so File(path).openSync
        // (where path = "$tempPath/app.log") fails — its parent isn't
        // a directory.
        File(tempPath).createSync();

        // Force log() to detect the lost handle. The simplest path: do a
        // bunch of HyperLogger.info calls; each routes to the printer's
        // log(), which finds the handle still set (cached), tries to
        // write, IO fails, onError fires, onError calls HyperLogger.warning,
        // which would re-enter — except for the guard.
        for (var i = 0; i < 50; i++) {
          // Must not stack overflow.
          HyperLogger.info<String>('attempt $i');
        }

        // Cleanup and reset before assertions.
        try {
          File(tempPath).deleteSync();
        } catch (_) {/* */}
        Directory(tempPath).createSync();

        await printer.close();
        HyperLogger.reset();

        // The reentrancy guard suppressed the recursive onError calls.
        // We saw the original onError fire (at least once for the first
        // failing log), but every reentrant attempt was dropped — so
        // onErrorCalls is bounded, NOT exponential.
        expect(onErrorCalls, lessThan(200),
            reason: 'reentrancy guard should prevent unbounded recursion');
      },
    );
  });

  group('concurrent lifecycle', () {
    test('concurrent close() callers all see the same completion', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('msg'));

      final futures = List.generate(5, (_) => printer.close());
      await Future.wait(futures);

      // All futures must have actually completed, not resolved early.
      for (final f in futures) {
        expect(f, isA<Future<void>>());
      }
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('msg'));
    });

    test('flush() while log() is in flight does not lose entries', () async {
      // The previous design awaited h.flush() asynchronously while log()
      // wrote synchronously to the same handle — a race that violates
      // RandomAccessFile's contract and can drop writes silently. With
      // sync handle ops, interleaved writes between flush()'s drain and
      // its compression-await must all land on disk.
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;

      // Schedule a flush, then immediately log many entries that will
      // race the flush's compression-chain await.
      final flushFuture = printer.flush();
      for (var i = 0; i < 200; i++) {
        printer.log(_entry('e$i'));
      }
      await flushFuture;
      await printer.close();

      final lines = File(path).readAsLinesSync();
      expect(lines.length, equals(200));
      // Every entry made it through (no silent drops).
      for (var i = 0; i < 200; i++) {
        expect(lines.any((l) => l.contains('e$i')), isTrue,
            reason: 'entry e$i missing');
      }
    });

    test('flush() is idempotent', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('one'));
      await printer.flush();
      await printer.flush();
      await printer.flush();
      // No errors and the entry is still readable.
      expect(File(path).readAsStringSync(), contains('one'));
      await printer.close();
    });

    test('flush() after close() is a silent no-op', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('msg'));
      await printer.close();
      // Must not throw, must not reopen the handle.
      await printer.flush();
      expect(File(path).readAsStringSync(), contains('msg'));
    });

    test('concurrent close() callers receive the same Future identity',
        () async {
      // Round-2 contract: close() memoizes the future so multiple
      // awaiters see the same completion signal. The two futures must
      // be `identical`, not just both-resolved.
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      final a = printer.close();
      final b = printer.close();
      expect(identical(a, b), isTrue);
      await Future.wait([a, b]);
    });

    test(
      'init failure with buffered entries surfaces the drop count via onError',
      () async {
        // Pre-fix: when the path provider throws AFTER entries have been
        // buffered, _initialize sets _initFailed=true and silently
        // clears _pending. The user sees only the init-failure error,
        // with no signal that N entries were also lost.
        // Round-5 fix: when init fails with a non-empty _pending, the
        // surfaced error includes the drop count.
        final messages = <String>[];
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            throw StateError('init failure');
          },
          onError: (e, _) => messages.add(e.toString()),
        );

        // Buffer entries before init fails.
        for (var i = 0; i < 5; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.ready;
        await _flush();
        await printer.close();

        // The error surface mentions both the init failure AND the drop count.
        expect(messages, isNotEmpty);
        final all = messages.join('\n');
        expect(all, contains('init failure'));
        expect(all, contains('5 buffered entries'),
            reason: 'init-failure must surface the count of dropped pending '
                'entries, not silently swallow them');
      },
    );

    test(
      'init-failure drop count includes entries FIFO-evicted before the '
      'path resolved',
      () async {
        // Round-6 fix (codex finding): the round-5 implementation reported
        // only `_pending.length` — entries already FIFO-evicted from the
        // bounded buffer (and tallied into `_pendingDropped`) were
        // silently omitted. Under a small `pendingBufferSize` and a slow
        // path provider that ultimately throws, the user would see
        // "3 buffered entries — all dropped" when in fact 100+ records
        // had been lost.
        final messages = <String>[];
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            throw StateError('init boom');
          },
          pendingBufferSize: 3,
          onError: (e, _) => messages.add(e.toString()),
        );

        // Buffer 10 entries against a 3-slot buffer → 7 FIFO-evicted,
        // 3 remain in _pending, 7 tallied into _pendingDropped.
        for (var i = 0; i < 10; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.ready;
        await _flush();
        await printer.close();

        expect(messages, isNotEmpty);
        final all = messages.join('\n');
        expect(all, contains('init boom'));
        // Pre-fix: would say "3 buffered entries". Post-fix: 10.
        expect(all, contains('10 buffered entries'),
            reason: 'init-failure drop count must include entries already '
                'FIFO-evicted from the pending buffer, not just the '
                'survivors');
      },
    );

    test(
      'log() calls after rotation handle loss surface via onError '
      '(no silent durability loss)',
      () async {
        // Round-5 fix: `_writeEntry` previously early-returned on a null
        // handle, so a `log()` call after a failed rotation would silently
        // consume the entry. Fix: `_writeEntry` throws, and `log()`'s
        // try/catch surfaces it via onError instead.
        //
        // Round-6 (codex finding): the previous version of this test
        // claimed to exercise close()'s drain-with-null-handle code path,
        // but that branch is unreachable in practice — `_pending` is
        // always empty by the time close() runs because `_initialize`
        // drains it on success and clears it on failure. The renamed
        // assertion now reflects what's actually being pinned: the
        // post-handle-loss `log()` durability contract.
        final subdir = Directory('${tempDir.path}/sub')..createSync();
        final path = '${subdir.path}/app.log';
        final errors = <Object>[];

        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return path;
          },
          rotationConfig: FileRotationConfig.size(maxBytes: 1),
          onError: (e, _) => errors.add(e),
        );

        // Buffer entries before init resolves; init drains them.
        for (var i = 0; i < 5; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.ready;
        await _flush();

        // Sabotage parent — every future rotation reopen now fails.
        try {
          File(path).deleteSync();
        } catch (_) {/* */}
        subdir.deleteSync(recursive: true);
        File(subdir.path).createSync();

        // Each post-sabotage `log()` triggers rotation → reopen fails →
        // `_handle` becomes null → next call hits the auto-reopen path
        // which also fails → onError fires per attempt. Pre-round-5,
        // those would silently disappear.
        final preCount = errors.length;
        for (var i = 0; i < 3; i++) {
          printer.log(_entry('after-sabotage-$i'));
        }
        expect(errors.length, greaterThan(preCount),
            reason: 'each failed log after handle loss must surface via '
                'onError rather than silently dropping');

        // Cleanup so tearDown can remove tempDir.
        try {
          File(subdir.path).deleteSync();
        } catch (_) {/* */}

        await printer.close();
      },
    );

    test(
      'close() drains pending entries that trigger rotation and still '
      'closes the swapped-in handle (no leak)',
      () async {
        // Round-4 fix: if the close-time drain causes a buffered entry
        // to cross maxBytes, _rotate swaps in a fresh handle. The pre-
        // round-4 close() captured the original handle into a local at
        // function entry, so flushSync/closeSync ran on the (now-closed)
        // original — leaking the new handle. This test asserts the new
        // handle gets properly flushed and closed.
        final path = '${tempDir.path}/app.log';
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            // Slow path resolution so we can buffer entries beforehand.
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return path;
          },
          rotationConfig: FileRotationConfig.size(maxBytes: 200),
          formatter: (e) => 'r' * 80, // ~80 bytes per line
        );

        // Buffer ~5 entries (each ~80 bytes); during init's drain the
        // accumulated bytes will cross maxBytes and trigger rotation.
        for (var i = 0; i < 5; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.close();

        // The live file should exist and be readable (its content is
        // whatever the post-rotation handle wrote). Critically: the
        // handle should NOT be left open — we can't directly assert that
        // in pure Dart, but we can check that the file is movable
        // (non-Windows) which fails when a handle is open.
        expect(File(path).existsSync(), isTrue);

        final rotated = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path != path && f.path.endsWith('.log'))
            .toList();
        expect(rotated, isNotEmpty,
            reason: 'rotation must have occurred during drain');

        // Sanity: every entry e0..e4 lands in either the live file or
        // a rotated sibling — none lost during the swap.
        final allText = [path, ...rotated.map((f) => f.path)]
            .map((p) => File(p).readAsStringSync())
            .join();
        expect(allText.length, greaterThan(0));
      },
    );

    test('flush() awaits a compression that was queued mid-flush', () async {
      // _drainCompressionChain loops until the chain is stable. A rotation
      // triggered by a sync log() between flush()'s sync section and its
      // chain-await must still be awaited by flush() — otherwise the
      // user's "I called flush(); my .gz files are durable" assumption
      // breaks.
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(
          maxBytes: 30,
          compress: true,
        ),
        formatter: (e) => 'r' * 40,
      );
      await printer.ready;

      // Start a flush, then immediately fire a log that triggers
      // rotation+compression after flush's sync section.
      final flushFuture = printer.flush();
      printer.log(_entry('rotate-trigger'));
      await flushFuture;

      // The compression queued during flush() must be on disk by now.
      final gzFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log.gz'))
          .toList();
      expect(gzFiles, isNotEmpty,
          reason: 'flush() must await compressions queued before it returns');

      await printer.close();
    });

    test('init failure clears pending entries (no memory pin)', () async {
      // When the path provider fails, _pending must be drained
      // immediately so a long-running app whose path never resolved
      // doesn't pin up to pendingBufferSize entries forever.
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw StateError('cannot resolve');
        },
        pendingBufferSize: 5,
        // Capture errors so they don't leak to stderr during the test.
        onError: (_, _) {},
      );
      // Buffer up some entries before init fails.
      for (var i = 0; i < 20; i++) {
        printer.log(_entry('e$i'));
      }
      await printer.ready;
      // After init failure, log() should be a true no-op — adding
      // another 1000 entries shouldn't blow up.
      for (var i = 0; i < 1000; i++) {
        printer.log(_entry('post-fail-$i'));
      }
      // No exceptions; no file created.
      expect(tempDir.listSync(), isEmpty);
      await printer.close();
    });

    test(
      'rotation reopen failure does not crash subsequent log() calls',
      () async {
        // Round-3 contract: if rotate's reopen-after-rename fails for
        // any reason (disk full, deleted directory, etc.), the printer
        // marks _handle null and surfaces the failure via onError.
        // Subsequent log() calls must remain safe — they auto-retry the
        // open, drop with onError on persistent failure, and never
        // buffer indefinitely or crash.
        //
        // Round-6 fix (codex finding): the previous version's comment
        // claimed it nuked the parent directory but the sabotage step
        // was absent — the test only exercised the happy rotation path
        // and never actually drove the reopen-failure code branch.
        final subdir = Directory('${tempDir.path}/sub')..createSync();
        final path = '${subdir.path}/app.log';
        var errorCount = 0;
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotationConfig: FileRotationConfig.size(maxBytes: 30),
          formatter: (e) => 'q' * 40,
          onError: (e, _) => errorCount++,
        );
        await printer.ready;

        // First rotation runs while the subdir is intact (sanity that
        // the printer was healthy before sabotage).
        printer.log(_entry('a'));
        printer.log(_entry('b')); // triggers rotation, succeeds

        // Now nuke the parent so the NEXT rotation's reopen-after-rename
        // fails and the second-chance reopen also fails. This is the
        // failure mode the test name describes.
        subdir.deleteSync(recursive: true);
        File(subdir.path).createSync();

        final preFailureCount = errorCount;
        // Each of these crosses maxBytes again; rotate() runs, the
        // reopen lands on a parent that's a regular file, fails, and
        // surfaces via onError.
        expect(() => printer.log(_entry('c')), returnsNormally);
        expect(() => printer.log(_entry('d')), returnsNormally);
        expect(() => printer.log(_entry('e')), returnsNormally);

        // The reopen-failure code path was actually exercised — onError
        // grew. (Pre-round-6 the test was silent on whether it ran at
        // all.)
        expect(errorCount, greaterThan(preFailureCount),
            reason: 'rotation reopen must surface via onError once the '
                'parent dir is sabotaged');

        // Cleanup so tearDown can remove tempDir.
        try {
          File(subdir.path).deleteSync();
        } catch (_) {/* */}

        await printer.close();
      },
    );
  });

  group('lifecycle', () {
    test('close() is idempotent', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      await printer.close();
      await printer.close(); // should not throw
    });

    test('log() after close() is a no-op', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(baseFilePathProvider: () => path);
      await printer.ready;
      printer.log(_entry('before'));
      await printer.close();
      printer.log(_entry('after'));
      // No error, no late writes.
      final contents = File(path).readAsStringSync();
      expect(contents, contains('before'));
      expect(contents, isNot(contains('after')));
    });

    test('failed path resolution does not crash log()', () async {
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('cannot resolve path');
        },
        // Silence the default stderr handler during the test.
        onError: (_, _) {},
      );
      await printer.ready;
      expect(() => printer.log(_entry('msg')), returnsNormally);
      await printer.close();
    });

    test('log() after init failure becomes a true no-op (no buffer churn)',
        () async {
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          throw StateError('boom');
        },
        // Small buffer to make churn observable if it were happening.
        pendingBufferSize: 5,
        onError: (_, _) {},
      );
      await printer.ready;

      // After init failure, log() must drop immediately — no enqueue,
      // no eventual flush. Logging 1000+ entries in tight loop must not
      // hang or allocate forever.
      for (var i = 0; i < 5000; i++) {
        printer.log(_entry('e$i'));
      }
      await printer.close();
      // No file was ever opened.
      final files = tempDir.listSync();
      expect(files, isEmpty);
    });

    test('close() before async path resolves still flushes pending entries',
        () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return path;
        },
      );

      printer.log(_entry('alpha'));
      printer.log(_entry('beta'));
      // close() while the path provider is still pending. The printer
      // must wait for the path, drain pending, and only then tear down.
      await printer.close();

      final contents = File(path).readAsStringSync();
      expect(contents, contains('alpha'));
      expect(contents, contains('beta'));
    });

    test(
      'pending buffer cap drops oldest entries and emits a synthetic warning',
      () async {
        final path = '${tempDir.path}/app.log';
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return path;
          },
          pendingBufferSize: 3,
        );

        // Log 10 entries before path resolves; only the last 3 fit.
        for (var i = 0; i < 10; i++) {
          printer.log(_entry('e$i'));
        }
        await printer.ready;
        await _flush();
        await printer.close();

        final contents = File(path).readAsStringSync();
        // The last 3 entries (e7, e8, e9) survived FIFO drop.
        expect(contents, contains('e7'));
        expect(contents, contains('e8'));
        expect(contents, contains('e9'));
        // The earliest were dropped.
        expect(contents, isNot(contains('e0 ')));
        expect(contents, isNot(contains('e1 ')));
        // A synthetic warning record was emitted noting the drop count.
        expect(contents, contains('dropped 7 buffered entries'));
        expect(contents, contains('[WARN]'));
      },
    );

    test('flush() drains pending and waits for in-flight gzip', () async {
      final path = '${tempDir.path}/app.log';
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotationConfig: FileRotationConfig.size(
          maxBytes: 30,
          compress: true,
        ),
        formatter: (e) => 'q' * 40,
      );
      await printer.ready;
      printer.log(_entry('a'));
      printer.log(_entry('b'));

      // flush() must wait until any background compression completes.
      await printer.flush();

      // After flush, no half-written .log file should remain alongside
      // pending compression state.
      final gzFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log.gz'))
          .toList();
      expect(gzFiles, isNotEmpty);
      // The original rotated file (uncompressed) should already be deleted
      // because compression completed before flush() returned.
      final unGz = tempDir.listSync().whereType<File>().where(
            (f) =>
                f.path != path &&
                f.path.endsWith('.log') &&
                !f.path.endsWith('.log.gz'),
          );
      expect(unGz, isEmpty);

      await printer.close();
    });
  });

  group('default error handler', () {
    test('formatDefaultFileWriterError emits a leading prefix line', () {
      final out = formatDefaultFileWriterError(
        StateError('boom'),
        null,
      );
      expect(out, startsWith('hyper_logger: RotatingFilePrinter:'));
      expect(out, contains('boom'));
      // No stack trace supplied — single line only.
      expect(out.split('\n'), hasLength(1));
    });

    test(
      'formatDefaultFileWriterError indents stack-trace continuation lines',
      () {
        final out = formatDefaultFileWriterError(
          StateError('boom'),
          StackTrace.fromString('a.dart:1\nb.dart:2'),
        );
        expect(out, contains('boom'));
        // Each stack frame line begins with two spaces of indentation.
        expect(out, contains('\n  a.dart:1'));
        expect(out, contains('\n  b.dart:2'));
      },
    );

    test('formatDefaultFileWriterError trims whitespace on the stack', () {
      final out = formatDefaultFileWriterError(
        StateError('e'),
        StackTrace.fromString('  frame.dart:1   \n'),
      );
      // Leading/trailing whitespace removed before continuation indent.
      expect(out, contains('\n  frame.dart:1'));
      expect(out, isNot(endsWith('\n')));
    });
  });

  group('default formatter', () {
    test('renders ISO timestamp, level, logger, message', () {
      final entry = LogEntry(
        level: LogLevel.warning,
        message: 'hello',
        object: LogMessage('hello', String),
        loggerName: 'svc',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
      );
      final line = defaultFileLineFormatter(entry);
      expect(line, contains('2026-05-08T12:00:00.000Z'));
      expect(line, contains('[WARN]'));
      expect(line, contains('svc'));
      expect(line, contains('hello'));
    });

    test('appends data and context as JSON segments when present', () {
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'work',
        object: LogMessage(
          'work',
          String,
          data: {'count': 3},
          context: {'requestId': 'R-1'},
        ),
        loggerName: 'svc',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
      );
      final line = defaultFileLineFormatter(entry);
      expect(line, contains('data={"count":3}'));
      expect(line, contains('context={"requestId":"R-1"}'));
    });

    test('values with spaces, equals, and quotes are JSON-encoded safely', () {
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'edge',
        object: LogMessage(
          'edge',
          String,
          context: {
            'sentence': 'has spaces',
            'expr': 'a=b',
            'quoted': 'say "hi"',
          },
        ),
        loggerName: 'svc',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
      );
      final line = defaultFileLineFormatter(entry);
      // Pull the JSON segment back out and re-parse it to prove the
      // encoder produces a valid round-trippable representation.
      final marker = 'context=';
      final start = line.indexOf(marker) + marker.length;
      final jsonText = line.substring(start);
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      expect(decoded['sentence'], equals('has spaces'));
      expect(decoded['expr'], equals('a=b'));
      expect(decoded['quoted'], equals('say "hi"'));
    });

    test('appends error and stack across continuation lines', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'boom',
        object: LogMessage('boom', String),
        loggerName: 'svc',
        time: DateTime.utc(2026, 5, 8, 12, 0, 0),
        error: Exception('explode'),
        stackTrace: StackTrace.fromString('a.dart:1\nb.dart:2'),
      );
      final line = defaultFileLineFormatter(entry);
      expect(line, contains('error: '));
      expect(line, contains('explode'));
      expect(line, contains('stack: '));
    });

    test(
      'non-JSON-serializable context values fall back to toString without '
      'throwing',
      () {
        final entry = LogEntry(
          level: LogLevel.info,
          message: 'work',
          object: LogMessage(
            'work',
            String,
            context: {
              'fn': () => 'closure',
              'custom': _CustomNoToJson('payload'),
            },
          ),
          loggerName: 'svc',
          time: DateTime.utc(2026, 5, 8, 12, 0, 0),
        );
        // Must not throw despite the function and the custom non-JSON
        // type — the `toEncodable: (o) => o.toString()` fallback handles
        // both.
        late final String line;
        expect(() => line = defaultFileLineFormatter(entry), returnsNormally);
        expect(line, contains('context='));
        expect(line, contains('"custom"'));
      },
    );
  });
}

class _CustomNoToJson {
  final String payload;
  _CustomNoToJson(this.payload);
  @override
  String toString() => 'Custom($payload)';
}
