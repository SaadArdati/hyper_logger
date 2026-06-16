import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import 'rotating_file_printer.dart';

/// IO-backed factory used when `dart.library.io` is available.
RotatingFilePrinter createRotatingFilePrinter({
  required FutureOr<String> Function() baseFilePathProvider,
  required FileLineFormatter formatter,
  List<FileRotation> rotations = const [],
  FileRetention? retention,
  int pendingBufferSize = 1000,
  required FileWriterErrorHandler onError,
}) {
  return _RotatingFilePrinterIo(
    baseFilePathProvider: baseFilePathProvider,
    formatter: formatter,
    rotations: rotations,
    retention: retention,
    pendingBufferSize: pendingBufferSize,
    onError: onError,
  );
}

/// Writes a single line to stderr. Used by the default error handler.
void writeStderrLine(String line) {
  stderr.writeln(line);
}

class _RotatingFilePrinterIo implements RotatingFilePrinter {
  final FutureOr<String> Function() _pathProvider;
  final FileLineFormatter _formatter;
  final List<FileRotation> _rotations;
  final FileRetention? _retention;
  final int _pendingBufferSize;
  final FileWriterErrorHandler _onError;

  // Resolved state — null until [_initialize] completes successfully.
  String? _path;
  // Cached rotated-file matcher; compiled lazily from `_path` once.
  RegExp? _rotatedFilePattern;
  RandomAccessFile? _handle;
  int _bytesWritten = 0;
  DateTime _windowStart = clock.now();

  // Buffer for entries logged before the file is open. Bounded; FIFO drop.
  final Queue<LogEntry> _pending = Queue<LogEntry>();
  int _pendingDropped = 0;

  // Lifecycle flags.
  bool _closed = false;
  bool _initFailed = false;
  late final Future<void> _readyFuture;

  // Memoized close future — guarantees concurrent callers see the same
  // completion signal rather than the second caller resolving early
  // while the first is still tearing down.
  Future<void>? _closeFuture;

  // Compression runs off the synchronous log() path; close() / flush()
  // await this chain so users can rely on shutdown completing all gzip
  // work. Each link is a short-lived async closure; the chain's history
  // is retained until the next flush()/close() resolves it.
  Future<void> _compressionChain = Future<void>.value();

  _RotatingFilePrinterIo({
    required FutureOr<String> Function() baseFilePathProvider,
    required FileLineFormatter formatter,
    List<FileRotation> rotations = const [],
    FileRetention? retention,
    int pendingBufferSize = 1000,
    required FileWriterErrorHandler onError,
  }) : _pathProvider = baseFilePathProvider,
       _formatter = formatter,
       _rotations = rotations,
       _retention = retention,
       _pendingBufferSize = pendingBufferSize,
       _onError = onError {
    _readyFuture = _initialize();
  }

  @override
  Future<void> get ready => _readyFuture;

  Future<void> _initialize() async {
    try {
      final path = await _pathProvider();
      _path = path;

      final file = File(path);
      // Ensure the directory exists; otherwise openSync(append) throws.
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _handle = file.openSync(mode: FileMode.append);
      _bytesWritten = file.existsSync() ? file.lengthSync() : 0;
      // Initialize the time-rotation window from the file's last-modified
      // time when available, so a process that restarts mid-day inherits
      // the previous run's rotation cadence rather than starting a fresh
      // 24-hour window. Falls back to wall clock if mtime is unavailable.
      final now = clock.now();
      DateTime windowStart = now;
      try {
        if (file.existsSync()) {
          final mtime = file.lastModifiedSync();
          if (mtime.isBefore(windowStart)) {
            windowStart = mtime;
          }
        }
      } catch (_) {
        // mtime unavailable — fall back to wall clock.
      }
      _windowStart = windowStart;

      // Evaluate onStart rotation rules once, now that the handle is open
      // and the rotation window is seeded.
      _evaluateStartupRotations(now);

      // Drain anything buffered before path resolved. We deliberately do
      // NOT bail on _closed — close() awaits this future and expects the
      // drain to land before we tear down.
      //
      // Track aggregate drain failures so the caller can tell how
      // many entries were lost. Each per-entry `_safeOnError` after
      // the first is suppressed while an async handler is in-flight
      // (intentional coalescing to avoid handler reentrancy), so
      // without this summary the user would see one error and have
      // no signal that subsequent records were also dropped.
      final initialDropped = _drainFailures(_pending);
      if (initialDropped > 1) {
        _safeOnErrorAfterCurrentHandler(
          StateError(
            'RotatingFilePrinter: $initialDropped buffered entries '
            'failed to drain on init. With a sync onError handler '
            'each was already reported per-record; with an async '
            'handler the per-record errors were coalesced into the '
            'first-error window and this summary is the authoritative '
            'total.',
          ),
          null,
        );
      }

      // Surface a synthetic warning if entries were dropped while the
      // path was resolving — silent loss is the worst kind. The notice
      // itself goes through _writeEntry which calls _maybeRotate, so
      // under tiny maxBytes it can immediately rotate the file. That's
      // acceptable: the notice still lands somewhere on disk.
      if (_pendingDropped > 0) {
        if (_handle != null) {
          try {
            _writeEntry(_dropNotice(_pendingDropped));
          } catch (e, st) {
            _safeOnError(e, st);
          }
        } else {
          // The drain itself lost the handle (a mid-drain rotation
          // whose reopen failed), so the synthetic notice can't be
          // written. Surface the count textually via onError so the
          // FIFO drop tally isn't silently lost on top of the
          // rotation error the user already saw.
          _safeOnError(
            StateError(
              'RotatingFilePrinter: $_pendingDropped buffered entries '
              'were dropped while the file path was resolving; the '
              'synthetic drop notice could not be written because the '
              'file handle was lost mid-drain (rotation reopen likely '
              'failed)',
            ),
            null,
          );
        }
        _pendingDropped = 0;
      }
    } catch (e, st) {
      // Path resolution or file open failed. Mark terminal — subsequent
      // log() calls become true no-ops instead of churning the buffer.
      _initFailed = true;
      // Drop pending entries proactively — we can't write them, and
      // holding them indefinitely on a long-running app pins memory.
      // The total drop count is buffer survivors PLUS entries already
      // FIFO-evicted while the path was resolving (otherwise a small
      // `pendingBufferSize` + slow provider would silently undercount).
      final dropped = _pending.length + _pendingDropped;
      _pending.clear();
      _pendingDropped = 0;
      if (dropped > 0) {
        // Combine the original failure with the drop count in a single
        // onError call. The reentrancy guard would block a second call
        // under an async handler, and the drop count is part of the
        // same logical event anyway.
        _safeOnError(
          StateError(
            'RotatingFilePrinter: init failed with $dropped buffered '
            'entries — all dropped. Underlying error: $e',
          ),
          st,
        );
      } else {
        _safeOnError(e, st);
      }
    }
  }

  @override
  void log(LogEntry entry) {
    if (_closed || _initFailed) return;
    if (_handle == null) {
      // Two cases for null handle:
      // 1. Init still in flight (`_path == null`). Buffer until ready.
      // 2. Runtime handle lost — rotation failed to reopen. We have a
      //    resolved path but no live handle; try to reopen synchronously.
      //    If reopen fails, drop the entry and surface via onError —
      //    silently buffering forever would just hide the loss.
      final path = _path;
      if (path == null) {
        if (_pending.length >= _pendingBufferSize) {
          _pending.removeFirst();
          _pendingDropped++;
        }
        _pending.add(entry);
        return;
      }
      try {
        _handle = File(path).openSync(mode: FileMode.append);
        _bytesWritten = File(path).existsSync() ? File(path).lengthSync() : 0;
      } catch (e, st) {
        _safeOnError(e, st);
        return;
      }
    }
    try {
      _writeEntry(entry);
    } catch (e, st) {
      // Swallow IO errors — logging must not crash the app. Surface via
      // onError so users can observe write failures.
      _safeOnError(e, st);
    }
  }

  /// Drains [queue] through [_writeEntry], counting per-entry failures.
  /// Each failure still routes through [_safeOnError] for live
  /// observability; the returned count exists so callers can surface a
  /// summary after the loop. With an async onError handler, all
  /// per-entry errors after the first are coalesced by the handler
  /// guard ("first error wins" live signal); the aggregate makes the
  /// total visible.
  int _drainFailures(Queue<LogEntry> queue) {
    var failures = 0;
    while (queue.isNotEmpty) {
      try {
        _writeEntry(queue.removeFirst());
      } catch (e, st) {
        failures++;
        _safeOnError(e, st);
      }
    }
    return failures;
  }

  void _writeEntry(LogEntry entry) {
    final handle = _handle;
    if (handle == null) {
      // Throw rather than silently early-return so the calling drain
      // loop's try/catch surfaces this via onError. Silent
      // consumption would let mid-drain rotation-reopen failures
      // violate close()'s durability contract. log() never reaches
      // this branch (its auto-reopen path either sets _handle or
      // returns before calling _writeEntry).
      throw StateError(
        'RotatingFilePrinter: write attempted with null handle — '
        'rotation reopen likely failed; entry dropped',
      );
    }

    final line = '${_formatter(entry)}\n';
    final bytes = utf8.encode(line);
    handle.writeFromSync(bytes);
    _bytesWritten += bytes.length;

    _maybeRotate();
  }

  /// Checks every [Cadence.continuous] rule against the shared rotation
  /// window and rotates once if any fires.
  ///
  /// Continuous rules share the single `_bytesWritten` / `_windowStart`
  /// window state: the first rule to fire triggers one rotation, and
  /// `_rotate` resets BOTH counters — so the most sensitive rule always
  /// wins and rules do not have independent windows. A single rule may set
  /// both `maxBytes` and `interval`; the two checks below are evaluated as
  /// OR (either condition fires), so the fall-through between them is
  /// intentional.
  void _maybeRotate() {
    if (_rotations.isEmpty) return;

    final now = clock.now();
    var due = false;
    for (final rule in _rotations) {
      if (rule.cadence != Cadence.continuous) continue;
      if (rule.maxBytes != null && _bytesWritten >= rule.maxBytes!) {
        due = true;
        break;
      }
      if (rule.interval != null &&
          now.difference(_windowStart) >= rule.interval!) {
        due = true;
        break;
      }
    }
    if (due) _rotate(now);
  }

  void _rotate(DateTime now) {
    final path = _path;
    final handle = _handle;
    if (path == null || handle == null) return;

    try {
      handle.flushSync();
      handle.closeSync();
      _handle = null;

      final rotatedPath = _rotatedFilePath(path, now);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) {
        file.renameSync(rotatedPath);
        if (_retention?.compress ?? false) {
          _scheduleCompression(rotatedPath);
        }
      }

      _enforceRetention(path, now);

      _handle = File(path).openSync(mode: FileMode.append);
      _bytesWritten = 0;
      _windowStart = now;
    } catch (e, st) {
      // If rotation fails partway, try to reopen the live path so logging
      // can continue. The live file may have been moved (rename succeeded
      // but a later step failed) — `openSync(append)` will recreate it.
      //
      // `_safeOnError` may invoke a sync handler that routes through
      // this same printer's `log()` (or the sync prefix of an async
      // one), which itself runs the auto-reopen path when `_handle ==
      // null && _path != null`. If that reopen wins first, our
      // subsequent `openSync` would overwrite `_handle` and leak the
      // handler-opened file descriptor. Gate the recovery reopen on
      // `_handle == null` so the already-recovered fd is preserved.
      _safeOnError(e, st);
      if (_handle == null) {
        try {
          _handle = File(path).openSync(mode: FileMode.append);
          _bytesWritten = File(path).existsSync() ? File(path).lengthSync() : 0;
          _windowStart = now;
        } catch (e2, st2) {
          _safeOnError(e2, st2);
        }
      } else {
        // The reentrant handler's auto-reopen already restored the
        // handle. Sync up `_bytesWritten` to whatever's on disk and
        // reset the rotation window so we don't immediately rotate
        // again on the next write.
        _bytesWritten = File(path).existsSync() ? File(path).lengthSync() : 0;
        _windowStart = now;
      }
    }
  }

  /// Evaluates [Cadence.onStart] rules once, against the existing file on
  /// disk. If any fires, performs a single startup rotation (archive, or
  /// discard for `onStart(discard: true)`). Called from [_initialize] after
  /// the handle is open and before buffered entries drain.
  void _evaluateStartupRotations(DateTime now) {
    final path = _path;
    if (path == null) return;

    final file = File(path);
    if (!file.existsSync()) return;
    final fileLength = file.lengthSync();
    if (fileLength == 0) return;

    FileRotation? firing;
    for (final rule in _rotations) {
      if (rule.cadence != Cadence.onStart) continue;
      if (rule.unconditional) {
        firing = rule;
        break;
      }
      if (rule.maxBytes != null && fileLength >= rule.maxBytes!) {
        firing = rule;
        break;
      }
      if (rule.interval != null) {
        DateTime? mtime;
        try {
          mtime = file.lastModifiedSync();
        } catch (_) {
          mtime = null;
        }
        if (mtime != null && now.difference(mtime) >= rule.interval!) {
          firing = rule;
          break;
        }
      }
    }

    if (firing == null) return;
    if (firing.discard) {
      _startupDiscard(now);
    } else {
      _rotate(now);
    }
  }

  /// Startup `discard` action: closes the handle, deletes the existing file
  /// (no archive), and reopens a fresh empty file. Mirrors [_rotate]'s
  /// recovery semantics on failure.
  void _startupDiscard(DateTime now) {
    final path = _path;
    final handle = _handle;
    if (path == null || handle == null) return;

    try {
      handle.flushSync();
      handle.closeSync();
      _handle = null;

      final file = File(path);
      if (file.existsSync()) file.deleteSync();

      _handle = File(path).openSync(mode: FileMode.append);
      _bytesWritten = 0;
      _windowStart = now;
    } catch (e, st) {
      // Mirrors _rotate's recovery: _safeOnError may invoke a handler that
      // routes back through log() and auto-reopens the handle. Gate the
      // recovery reopen on `_handle == null` so an already-recovered fd
      // isn't leaked; otherwise sync `_bytesWritten` to disk so the
      // pending drain doesn't immediately over-rotate on stale state.
      _safeOnError(e, st);
      if (_handle == null) {
        try {
          _handle = File(path).openSync(mode: FileMode.append);
          _bytesWritten = 0;
          _windowStart = now;
        } catch (e2, st2) {
          _safeOnError(e2, st2);
        }
      } else {
        _bytesWritten = File(path).existsSync() ? File(path).lengthSync() : 0;
        _windowStart = now;
      }
    }
  }

  /// Builds a rotated file name like `app.20260508T120000Z.log`. Adds a
  /// `.<n>` numeric suffix if the timestamp collides with an existing file
  /// (rapid rotation under tiny size limits). When compression is enabled,
  /// also checks for a `.gz` sibling so previously-gzipped rotations can't
  /// be overwritten by a second rotation in the same second.
  String _rotatedFilePath(String basePath, DateTime now) {
    final dir = p.dirname(basePath);
    final ext = p.extension(basePath);
    final stem = p.basenameWithoutExtension(basePath);
    final ts = _compactUtcTimestamp(now);
    final compress = _retention?.compress ?? false;

    String candidate(int? counter) {
      final suffix = counter == null ? '' : '.$counter';
      return p.join(dir, '$stem.$ts$suffix$ext');
    }

    bool taken(String c) {
      if (File(c).existsSync()) return true;
      if (compress && File('$c.gz').existsSync()) return true;
      return false;
    }

    var c = candidate(null);
    if (!taken(c)) return c;

    var n = 1;
    while (taken(candidate(n))) {
      n++;
    }
    return candidate(n);
  }

  /// `2026-05-08T12:00:00.000Z` → `20260508T120000Z`. Built explicitly so
  /// no part of the ISO string (microseconds, the trailing `Z`) is lost.
  ///
  /// Asserts the year fits in 4 digits — years > 9999 would break the
  /// `\d{8}` (year+month+day) regex used by [_enforceRetention]. Practically
  /// irrelevant for any clock you might encounter, but the assertion makes
  /// the contract explicit.
  static String _compactUtcTimestamp(DateTime t) {
    final u = t.toUtc();
    assert(
      u.year >= 0 && u.year <= 9999,
      'rotation filename requires a 4-digit year; got ${u.year}',
    );
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    final mm = u.minute.toString().padLeft(2, '0');
    final ss = u.second.toString().padLeft(2, '0');
    return '$y$m${d}T$hh$mm${ss}Z';
  }

  /// Parses the UTC time from a rotation signature like
  /// `.20260508T120000Z` or `.20260508T120000Z.3`. Returns null if the
  /// signature doesn't contain a parseable timestamp.
  static DateTime? _parseSignatureTime(String signature) {
    // Anchored at the signature's leading dot (always `.<ts>` from
    // `_rotatedFilePattern`) so a future prefix can't shift the match.
    final m = RegExp(
      r'^\.(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z',
    ).firstMatch(signature);
    if (m == null) return null;
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  /// Schedules `srcPath` for streaming gzip compression off the sync
  /// `log()` path. Compressions are serialized so that two rotations in
  /// quick succession don't fight over the same buffers; [close] and
  /// [flush] await the chain.
  ///
  /// On failure, both the partial `.gz` and the original `.log` are left
  /// intact, the partial `.gz` is deleted (so it can't be confused for a
  /// real archive), and the error is surfaced via `onError`. The next
  /// rotation's `_enforceRetention` sweep will eventually prune the
  /// uncompressed survivor by age.
  void _scheduleCompression(String srcPath) {
    _compressionChain = _compressionChain.then((_) async {
      final gzPath = '$srcPath.gz';
      try {
        final src = File(srcPath);
        if (!src.existsSync()) return;
        final dst = File(gzPath).openWrite();
        await src.openRead().transform(gzip.encoder).pipe(dst);
        // pipe() closes dst.
        try {
          src.deleteSync();
        } catch (e, st) {
          _safeOnError(e, st);
        }
      } catch (e, st) {
        _safeOnError(e, st);
        // Best-effort cleanup of any partial .gz — a half-written gzip
        // file is worse than no file at all (would fail decompression
        // and clutter the rotation directory).
        try {
          final partial = File(gzPath);
          if (partial.existsSync()) partial.deleteSync();
        } catch (_) {
          /* */
        }
      }
    });
  }

  /// Prunes rotated archives that violate the [FileRetention] policy:
  /// deletes any archive older than `maxAge`, then deletes oldest archives
  /// until at most `maxFiles` remain. Both null => no-op.
  ///
  /// Files are grouped by rotation signature (`<ts>(.<n>)?`) so a
  /// `.log + .log.gz` pair from the same rotation counts as one rotation.
  /// Age is taken from the filename timestamp (reliable across copy/touch),
  /// falling back to filesystem mtime when a name doesn't parse.
  void _enforceRetention(String basePath, DateTime now) {
    final retention = _retention;
    if (retention == null) return;
    final maxFiles = retention.maxFiles;
    final maxAge = retention.maxAge;
    if (maxFiles == null && maxAge == null) return;

    try {
      final dir = Directory(p.dirname(basePath));
      if (!dir.existsSync()) return;

      final pattern = _rotatedFilePattern ??= RegExp(
        '^${RegExp.escape(p.basenameWithoutExtension(basePath))}'
        r'(\.\d{8}T\d{6}Z(?:\.\d+)?)' // group 1: rotation signature
        '${RegExp.escape(p.extension(basePath))}'
        r'(\.gz)?$',
      );

      // Group files by rotation signature so .log + .log.gz pairs from
      // the same rotation count as ONE rotation.
      final groups = <String, List<File>>{};
      for (final f in dir.listSync().whereType<File>()) {
        final m = pattern.firstMatch(p.basename(f.path));
        if (m == null) continue;
        final sig = m.group(1)!;
        groups.putIfAbsent(sig, () => []).add(f);
      }

      // Resolve each group's time: prefer the filename timestamp, fall
      // back to mtime. Stat once per group.
      final stamped = <(List<File>, DateTime)>[
        for (final entry in groups.entries)
          (
            entry.value,
            _parseSignatureTime(entry.key) ??
                entry.value.first.statSync().modified,
          ),
      ]..sort((a, b) => a.$2.compareTo(b.$2));

      // Helper to delete a whole group; returns false if a delete fails.
      bool deleteGroup(List<File> g) {
        for (final f in g) {
          try {
            f.deleteSync();
          } catch (e, st) {
            _safeOnError(e, st);
            return false;
          }
        }
        return true;
      }

      // Phase 1: age-based pruning. The predicate has a side effect: it
      // deletes the group's files and returns whether the delete succeeded.
      // Returning false on a failed delete deliberately KEEPS the group in
      // `stamped` (so phase 2 can still attempt count-based pruning on it)
      // — do not "simplify" this to a pure isBefore() check.
      if (maxAge != null) {
        final cutoff = now.subtract(maxAge);
        stamped.removeWhere((s) {
          if (s.$2.isBefore(cutoff)) {
            return deleteGroup(s.$1);
          }
          return false;
        });
      }

      // Phase 2: count-based pruning (oldest first). Abort on the first
      // failed delete — the filesystem may be in trouble and retrying would
      // just spam onError.
      if (maxFiles != null) {
        while (stamped.length > maxFiles) {
          final oldest = stamped.removeAt(0);
          if (!deleteGroup(oldest.$1)) break;
        }
      }
    } catch (e, st) {
      _safeOnError(e, st);
    }
  }

  /// Synthesizes a record explaining how many entries were dropped while
  /// the path was resolving. Emitted once after the path resolves.
  LogEntry _dropNotice(int dropped) {
    return LogEntry(
      level: LogLevel.warning,
      message:
          'RotatingFilePrinter: dropped $dropped buffered entries while '
          'waiting for the file path to resolve (buffer size: '
          '$_pendingBufferSize)',
      object: LogMessage(
        'RotatingFilePrinter: dropped $dropped buffered entries while '
        'waiting for the file path to resolve',
        Object,
        data: {'dropped': dropped, 'bufferSize': _pendingBufferSize},
      ),
      loggerName: 'RotatingFilePrinter',
      time: clock.now(),
    );
  }

  /// Reentrancy guard for [_safeOnError]. Held for the entire
  /// duration of the user's onError invocation — synchronously while
  /// the handler runs to its first `await`, then through the handler's
  /// awaited tail until the returned Future settles (cleared via
  /// `whenComplete`).
  ///
  /// This is intentional coalescing under sustained failure with an
  /// async handler. The trade-off is documented on
  /// [FileWriterErrorHandler]: only the first error per handler-Future
  /// window is reported; subsequent failures during the awaited tail
  /// (independent or self-induced) are coalesced. Coalescing is
  /// deliberately preferred over per-failure visibility because:
  ///
  /// 1. Same-printer reentry under sustained failure would
  ///    livelock. A common shape is `onError: (e) async { await
  ///    sink.send(e); }` where `sink.send` ultimately routes through
  ///    a `HyperLogger` whose root printer IS this `RotatingFilePrinter`.
  ///    Under handle loss, every `sink.send` fails → fires `onError` →
  ///    awaits → resumes → fails → ... unbounded microtask pump. With
  ///    the guard held, the cycle is bounded by the user's handler
  ///    Future settling.
  /// 2. Stream-routed reentry escapes zone-scoped guards.
  ///    `package:logging`'s record stream delivers events in the
  ///    listener's registration zone, not the emitter's, so a
  ///    [Zone]-based marker doesn't propagate. A flat boolean held
  ///    across the Future is the only mechanism that catches every
  ///    routing path.
  /// 3. Production telemetry sinks dedupe their own input. Most
  ///    callers wiring `onError` into telemetry already collapse
  ///    bursts; per-record fan-out would multiply that work without
  ///    adding signal.
  ///
  /// If you need per-record visibility, use a sync handler (the guard
  /// is still cleared synchronously when a sync handler returns) or
  /// hand off to a bounded queue consumer that yields immediately.
  bool _inSafeOnError = false;

  /// Tracks the most-recent in-flight async handler `Future`, if any.
  ///
  /// Used by [_safeOnErrorAfterCurrentHandler] so a drain-failure
  /// summary fires *after* an in-flight async handler settles. Without
  /// this hop the summary would route through `_safeOnError` while
  /// [_inSafeOnError] is still held, get coalesced like the per-entry
  /// calls, and silently disappear exactly when it was needed most.
  Future<void>? _currentHandlerFuture;

  /// Calls the user-supplied error handler; if THAT throws (synchronously
  /// or asynchronously), swallow it. Logging must never crash the app,
  /// even if the user's hook is buggy.
  void _safeOnError(Object error, [StackTrace? stackTrace]) {
    if (_inSafeOnError) {
      // Reentry from anywhere — sync recursion within the handler's
      // call stack OR an independent/self-feedback failure during the
      // handler's awaited tail. Drop silently. See the doc on
      // [_inSafeOnError] for the rationale.
      return;
    }
    _inSafeOnError = true;

    Future<void>? completion;
    try {
      final result = _onError(error, stackTrace);
      if (result is Future) {
        completion = result;
      }
    } catch (_) {
      // Sync throw from a `void`-typed handler — swallow.
    }

    if (completion == null) {
      // Sync handler — clear immediately. No in-flight Future to
      // track for aggregate scheduling.
      _inSafeOnError = false;
      _currentHandlerFuture = null;
    } else {
      // Async handler — keep the guard up until the handler's Future
      // settles. `whenComplete` runs whether the future resolves or
      // rejects; `catchError` on the resulting future swallows any
      // rejection so it never surfaces as uncaught.
      _currentHandlerFuture = completion;
      completion
          .whenComplete(() {
            _inSafeOnError = false;
            // Only clear the tracked Future if it's still the same one
            // we just awaited; a reentrant aggregate may have replaced
            // it with a fresh handler invocation.
            if (identical(_currentHandlerFuture, completion)) {
              _currentHandlerFuture = null;
            }
          })
          .catchError((_) {
            /* swallow */
          });
    }
  }

  /// Variant of [_safeOnError] for aggregate summaries that need
  /// to reach the user even when per-record errors were coalesced by
  /// the in-flight async handler.
  ///
  /// If no async handler is currently in flight, this is exactly
  /// [_safeOnError]. If one IS in flight, the aggregate is chained
  /// via `whenComplete` so it fires after the handler settles and
  /// the guard clears, surfacing the summary as its own onError
  /// invocation.
  void _safeOnErrorAfterCurrentHandler(Object error, StackTrace? stackTrace) {
    final pending = _currentHandlerFuture;
    if (pending == null) {
      _safeOnError(error, stackTrace);
      return;
    }
    pending
        .whenComplete(() {
          // Best-effort: if a fresh handler started between this
          // registration and the current Future settling, fire anyway.
          // The aggregate is informational; an extra microtask hop is
          // fine.
          _safeOnError(error, stackTrace);
        })
        .catchError((_) {
          /* swallow */
        });
  }

  @override
  Future<void> flush() async {
    if (_closed) return; // Post-close flush is a documented no-op.
    // Wait for path resolution before draining.
    await _readyFuture;
    if (_handle != null) {
      final flushDropped = _drainFailures(_pending);
      if (flushDropped > 1) {
        _safeOnErrorAfterCurrentHandler(
          StateError(
            'RotatingFilePrinter: $flushDropped buffered entries '
            'failed to drain during flush(). With a sync onError '
            'handler each was already reported per-record; with an '
            'async handler the per-record errors were coalesced and '
            'this summary is the authoritative total.',
          ),
          null,
        );
      }
      // Re-read the handle after drain: a buffered entry's _writeEntry
      // could have crossed maxBytes and triggered _rotate, which closes
      // the original handle and opens a new one. Using a stale captured
      // reference would (a) flush a closed handle (error) and (b) leak
      // the new handle.
      final live = _handle;
      if (live != null) {
        try {
          live.flushSync();
        } catch (e, st) {
          _safeOnError(e, st);
        }
      }
    }
    await _drainCompressionChain();
  }

  @override
  Future<void> close() {
    return _closeFuture ??= _doClose();
  }

  @override
  void dispose() {
    // Best-effort sync trigger; for durable shutdown users should
    // explicitly `await close()`. See [LogPrinter.dispose] dartdoc.
    close();
  }

  Future<void> _doClose() async {
    _closed = true;
    // Wait for path resolution (success or failure) so we don't tear down
    // before _initialize has had a chance to drain pending entries.
    await _readyFuture;

    if (_handle != null) {
      // Drain any entries that arrived between _initialize's drain and
      // this close — close() is the user's last guarantee.
      final closeDropped = _drainFailures(_pending);
      if (closeDropped > 1) {
        _safeOnErrorAfterCurrentHandler(
          StateError(
            'RotatingFilePrinter: $closeDropped buffered entries '
            'failed to drain during close(). With a sync onError '
            'handler each was already reported per-record; with an '
            'async handler the per-record errors were coalesced and '
            'this summary is the authoritative total.',
          ),
          null,
        );
      }
      // Re-read the handle after drain: a buffered entry's _writeEntry
      // may have triggered _rotate, swapping in a fresh handle. Closing
      // the original captured reference would leak the new one. Each
      // sync op is in its own try/catch so a failed flush doesn't
      // prevent close, or vice versa.
      final live = _handle;
      if (live != null) {
        try {
          live.flushSync();
        } catch (e, st) {
          _safeOnError(e, st);
        }
        try {
          live.closeSync();
        } catch (e, st) {
          _safeOnError(e, st);
        }
      }
    }
    _handle = null;
    _pending.clear();

    // Wait for any in-flight compressions before returning.
    await _drainCompressionChain();
  }

  /// Awaits `_compressionChain` repeatedly until no new compression has
  /// been queued mid-await. This guards against the (rare) case where a
  /// rotation triggered by a synchronous `log()` after the await reads
  /// the field swaps in a fresh chain that the original `await` would
  /// have missed.
  ///
  /// Bounded at [_drainCompressionChainMaxIterations]: under a sustained
  /// rotation cascade (sync `log()` triggering a fresh compression on
  /// every cycle), the loop would otherwise never terminate. After the
  /// cap, we surface via `onError` and return — better to return a
  /// slightly-incomplete flush than to deadlock the caller. In practice
  /// users stop logging before flush/close, so the cap is essentially
  /// never hit.
  Future<void> _drainCompressionChain() async {
    for (var i = 0; i < _drainCompressionChainMaxIterations; i++) {
      final snapshot = _compressionChain;
      await snapshot;
      if (identical(snapshot, _compressionChain)) return;
    }
    _safeOnError(
      StateError(
        'RotatingFilePrinter: _drainCompressionChain exhausted '
        '$_drainCompressionChainMaxIterations iterations — sustained '
        'rotation under flush/close is preventing the chain from '
        'settling. Returning without awaiting further compressions.',
      ),
      null,
    );
  }
}

/// Cap for [_drainCompressionChain]'s loop. Picked to be high enough that
/// a normal flush/close completes well within (typically 1–2 iterations)
/// while bounded enough that a pathological tight rotation loop can't
/// deadlock the caller. Exposed as a top-level constant so tests can
/// reason about it; not configurable via the public API (a user hitting
/// this should reduce their log rate or rotation aggressiveness, not
/// raise the cap).
const int _drainCompressionChainMaxIterations = 100;
