import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../model/log_entry.dart';
import '../model/log_message.dart';
import 'log_printer.dart';
import 'logger_name_filter.dart';
import 'rotating_file_printer_stub.dart'
    if (dart.library.io) 'rotating_file_printer_io.dart'
    as impl;

/// A formatter that turns a [LogEntry] into a single line of file content
/// (no trailing newline — the printer appends one).
typedef FileLineFormatter = String Function(LogEntry entry);

/// Callback invoked by [RotatingFilePrinter] when an out-of-band error
/// (path resolution failure, IO write failure, rotation failure,
/// compression failure) occurs.
///
/// Out-of-band errors are NOT thrown — logging must never crash the app.
/// They flow through this callback so users can surface them somewhere
/// observable (telemetry, stderr, a fallback logger).
///
/// The handler may be sync or async (`FutureOr<void>`). Async failures
/// (returned futures that reject) are caught and swallowed by the
/// printer; sync throws are caught and swallowed too. Either way, a
/// buggy handler never crashes the app — but a buggy handler is also
/// invisible, so prefer to keep handlers simple.
///
/// The default callback writes a single line to `stderr`. Pass your own
/// to forward to your monitoring system, or pass a no-op to silence
/// entirely (not recommended in production).
///
/// ### Reentrancy and rate limiting
///
/// Sync handlers are invoked once per failed record — the printer
/// does not rate-limit. If your handler fans out to a network sink,
/// dedupe yourself.
///
/// Async handlers (handlers returning a `Future`) are invoked at
/// most once per handler-Future window: the next `Future` does not
/// start until the previous one settles, and any failures occurring
/// during the awaited tail are coalesced into "first error wins".
/// This intentional coalescing prevents two failure modes:
///
/// 1. A handler that routes back through a `HyperLogger` whose root
///    printer is this same `RotatingFilePrinter` (a common telemetry
///    shape) would otherwise livelock under sustained handle loss —
///    each `await` resumption fails again, fires `onError`, awaits
///    again, microtask-pumps unboundedly.
/// 2. Even without same-printer reentry, an `await sink.send(error)`
///    that's slow under a high-throughput failure storm would queue
///    one handler invocation per record, exhausting the sink.
///
/// If you need per-record visibility AND your handler does I/O, write
/// a sync handler that pushes to an internal bounded queue, and let a
/// background isolate or `runZonedGuarded` task drain it.
typedef FileWriterErrorHandler =
    FutureOr<void> Function(Object error, StackTrace? stackTrace);

/// A [LogPrinter] that appends formatted log entries to a file with optional
/// rotation by size or time, and optional gzip compression of rotated files.
///
/// File output is platform-gated: this printer requires `dart:io` and is
/// not available on the web. Constructing it on web throws an
/// [UnsupportedError]. On web, prefer the [WebConsolePrinter] (or capture
/// logs to memory).
///
/// ## Basic usage
///
/// ```dart
/// final filePrinter = RotatingFilePrinter(
///   baseFilePathProvider: () => '/var/log/app.log',
///   rotations: [
///     FileRotation.size(10 * 1024 * 1024), // rotate at 10 MB (continuous)
///     FileRotation.onStart(),              // also rotate on every process start
///   ],
///   retention: FileRetention(maxFiles: 5),
/// );
///
/// HyperLogger.init(printer: filePrinter);
/// ```
///
/// ## Async path resolution (Flutter, path_provider)
///
/// [baseFilePathProvider] may return a [Future] — useful with
/// `path_provider`. Records logged before the path resolves are buffered
/// in memory and flushed on the first successful resolution.
///
/// Flutter callers: depend on
/// [`path_provider`](https://pub.dev/packages/path_provider) and
/// `import 'package:path_provider/path_provider.dart';` directly —
/// `hyper_logger` does not transitively expose it.
///
/// ```dart
/// import 'package:path_provider/path_provider.dart';
///
/// final filePrinter = RotatingFilePrinter(
///   baseFilePathProvider: () async {
///     final dir = await getApplicationDocumentsDirectory();
///     return '${dir.path}/logs/app.log';
///   },
/// );
/// ```
///
/// ## Rotation
///
/// Pass a list of [FileRotation] rules; each pairs a trigger with a
/// [Cadence] (`continuous` — checked on every write — or `onStart` —
/// checked once when the file is opened). Rules compose as a union: the
/// first to fire triggers one rotation.
///
/// - Size-based: [FileRotation.size] — rotate when the file reaches the
///   configured byte threshold.
/// - Time-based: [FileRotation.daily] or [FileRotation.interval] — rotate
///   when the elapsed time (continuous) or existing-file age (onStart)
///   crosses the bound.
/// - Startup (unconditional): [FileRotation.onStart] — always rotate (or
///   `discard`) the existing file on each process start. For a
///   *conditional* startup rotation, use `size`/`interval` with
///   `cadence: Cadence.onStart`: it fires at open only if the existing
///   file already exceeds the byte threshold / age bound.
/// - With an empty `rotations` list, the printer appends forever to a
///   single file.
///
/// Rotated files are renamed to `<base>.<timestamp>.<ext>`. Retention is
/// shared across all rules via [FileRetention]: with `compress` enabled,
/// rotated files are gzipped to `<base>.<timestamp>.<ext>.gz`; `maxFiles`
/// caps the archive count and `maxAge` deletes archives older than a
/// bound, both pruned on rotation.
///
/// ## Shutdown
///
/// Call [close] when the app is shutting down to flush buffered writes and
/// release the file handle. Skipping [close] risks dropping the last few
/// entries.
///
/// ## Concurrency model
///
/// `RotatingFilePrinter` assumes a single-process owner of the
/// target file. Two processes pointed at the same path will interleave
/// bytes and race on rotation: `O_APPEND` in Dart goes through
/// `IOSink.add` / `writeFromSync`, neither of which guarantees atomic
/// append boundaries above PIPE_BUF. If you need multi-process
/// logging, give each process its own file (e.g. include the PID in
/// the path) and aggregate downstream.
abstract class RotatingFilePrinter implements LogPrinter {
  /// Creates a rotating file printer.
  ///
  /// - [baseFilePathProvider]: returns the absolute file path. May be sync
  ///   or async ([FutureOr]).
  /// - [formatter]: turns each [LogEntry] into a line of file content.
  ///   Defaults to [defaultFileLineFormatter] (`<timestamp> [LEVEL] <logger>: <message>`).
  ///   For JSON Lines output, pass a formatter built from [GcpJsonPrinter]
  ///   or [AwsJsonPrinter].
  /// - [rotations]: rotation rules (trigger × [Cadence]). Empty (the
  ///   default) means the file grows unbounded. When several rules are
  ///   given they compose as a union: continuous rules are checked on
  ///   every write and onStart rules once at open, and the FIRST rule (in
  ///   list order) to fire triggers a single rotation. List order matters
  ///   if you mix an archiving onStart rule with a discarding one
  ///   (`onStart(discard: true)`) — the earlier rule decides whether the
  ///   existing log is archived or destroyed.
  /// - [retention]: optional shared archive-retention policy (`maxFiles`,
  ///   `maxAge`, `compress`). Null keeps all archives uncompressed.
  /// - [pendingBufferSize]: maximum number of records to hold in memory
  ///   while [baseFilePathProvider] is resolving. Must be `>= 1` (a value
  ///   of 0 or less throws [ArgumentError]). Older records are dropped
  ///   FIFO once the bound is hit; a synthetic warning record is emitted
  ///   on the first successful flush so silent loss is visible.
  ///   Default: 1000.
  /// - [onError]: invoked on out-of-band errors (path resolution failure,
  ///   IO write failure, rotation failure). Defaults to a one-line
  ///   `stderr.writeln(...)` so init failures are observable. Pass a
  ///   no-op to silence (not recommended in production), or wire it into
  ///   your monitoring system.
  ///
  /// Throws [UnsupportedError] on web / non-IO platforms.
  factory RotatingFilePrinter({
    required FutureOr<String> Function() baseFilePathProvider,
    FileLineFormatter? formatter,
    List<FileRotation> rotations = const [],
    FileRetention? retention,
    int pendingBufferSize = 1000,
    FileWriterErrorHandler? onError,
  }) {
    if (pendingBufferSize < 1) {
      throw ArgumentError.value(
        pendingBufferSize,
        'pendingBufferSize',
        'must be >= 1',
      );
    }
    return impl.createRotatingFilePrinter(
      baseFilePathProvider: baseFilePathProvider,
      formatter: formatter ?? defaultFileLineFormatter,
      rotations: rotations,
      retention: retention,
      pendingBufferSize: pendingBufferSize,
      onError: onError ?? defaultFileWriterErrorHandler,
    );
  }

  /// Flushes pending writes and any in-flight compressions, then closes
  /// the file handle.
  ///
  /// Idempotent and safe under concurrent callers: a second [close] call
  /// (whether sequential or concurrent) returns the same future as the
  /// first, so all callers see the same completion signal.
  ///
  /// After [close] returns, further [log] calls are silent no-ops, and
  /// further [flush] calls return immediately. Records that arrived
  /// before [close] (including those queued before the path resolved)
  /// are flushed to disk first.
  ///
  /// **Compression drain cap.** When rotated files are compressed
  /// (`FileRetention(compress: true)`), [close] drains the gzip
  /// chain up to a bounded number of iterations (100) to guarantee
  /// termination if compression itself keeps producing new work.
  /// Reaching the cap is surfaced via `onError` rather than thrown —
  /// the file handle is still closed and [close] still resolves, but
  /// some `.gz` outputs may not be on disk. In practice this only
  /// fires under sustained per-record rotation; normal workloads
  /// drain in 1–2 iterations.
  Future<void> close();

  /// Synchronously triggers `close()` for best-effort cleanup when
  /// [HyperLogger.init] replaces the global printer.
  ///
  /// For durable shutdown (flushed buffers + completed gzip
  /// compressions), users MUST await [close] — `dispose()` is
  /// fire-and-forget and returns before the file handle settles.
  @override
  void dispose() {
    // Fire-and-forget; the user is responsible for `await close()`
    // when durability matters.
    close();
  }

  /// Drains buffered entries, awaits any in-flight gzip compressions, and
  /// flushes the OS file buffer — without closing the printer.
  ///
  /// Useful as a periodic safety net (e.g. on app suspend) when you want
  /// the file to be observable from outside the process without tearing
  /// the printer down. Idempotent; calling [flush] after [close] is a
  /// silent no-op.
  Future<void> flush();

  /// Resolves once the underlying path has been resolved and the file is
  /// open (or once initialization has failed and no further writes will
  /// land).
  ///
  /// Useful in tests to wait for async path resolution before asserting
  /// on file contents.
  Future<void> get ready;
}

/// When a [FileRotation] rule's trigger condition is evaluated.
enum Cadence {
  /// Checked on every log write (rotation can happen mid-run).
  continuous,

  /// Checked exactly once, when the file is first opened.
  onStart,
}

/// A single rotation rule: a trigger condition crossed with a [Cadence].
///
/// Multiple rules can be supplied to one [RotatingFilePrinter] and compose
/// as a union — whichever fires first triggers one rotation.
///
/// Use the factory constructors — [size], [interval], [daily], [onStart].
class FileRotation {
  /// Size threshold in bytes; null unless this is a size rule.
  final int? maxBytes;

  /// Time threshold; null unless this is an interval rule. For
  /// [Cadence.continuous] it bounds elapsed time since the last rotation;
  /// for [Cadence.onStart] it bounds the existing file's last-modified age.
  final Duration? interval;

  /// When this rule's condition is evaluated.
  final Cadence cadence;

  /// Only meaningful for [onStart]: truncate/delete the existing file
  /// instead of archiving it.
  final bool discard;

  const FileRotation._({
    this.maxBytes,
    this.interval,
    required this.cadence,
    this.discard = false,
  });

  /// True only for an unconditional [onStart] rule (no size/time condition).
  /// Derived, not stored, so it cannot disagree with the other fields.
  bool get unconditional =>
      cadence == Cadence.onStart && maxBytes == null && interval == null;

  /// Rotate when the live file reaches [maxBytes] bytes.
  ///
  /// Throws [ArgumentError] if [maxBytes] is `<= 0`.
  factory FileRotation.size(
    int maxBytes, {
    Cadence cadence = Cadence.continuous,
  }) {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be > 0');
    }
    return FileRotation._(maxBytes: maxBytes, cadence: cadence);
  }

  /// Rotate when elapsed time ([Cadence.continuous]) or existing-file age
  /// ([Cadence.onStart]) reaches [interval].
  ///
  /// Throws [ArgumentError] if [interval] is `<= Duration.zero`.
  factory FileRotation.interval(
    Duration interval, {
    Cadence cadence = Cadence.continuous,
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be > Duration.zero',
      );
    }
    return FileRotation._(interval: interval, cadence: cadence);
  }

  /// Sugar for `FileRotation.interval(const Duration(days: 1))`.
  factory FileRotation.daily({Cadence cadence = Cadence.continuous}) =>
      FileRotation.interval(const Duration(days: 1), cadence: cadence);

  /// Unconditional rotation at file open. [discard] truncates/deletes the
  /// existing file instead of archiving it.
  factory FileRotation.onStart({bool discard = false}) =>
      FileRotation._(cadence: Cadence.onStart, discard: discard);
}

/// Retention policy shared across all of a printer's rotation rules.
///
/// All rules rotate the same base file into one pool of
/// `<base>.<timestamp>.<ext>[.gz]` archives, so retention is shared.
class FileRetention {
  /// Keep at most this many archives; older ones pruned. null = unlimited.
  final int? maxFiles;

  /// Delete archives older than this. null = no age limit.
  final Duration? maxAge;

  /// If true, rotated files are gzipped to `<name>.gz`. Independent of
  /// pruning: with only `compress` set (no `maxFiles`/`maxAge`), archives
  /// are gzipped but never deleted.
  final bool compress;

  /// Throws [ArgumentError] if [maxFiles] `<= 0` or [maxAge] `<= zero`
  /// (use null for "no limit").
  // Not const: the constructor throws ArgumentError on invalid bounds, which
  // a const initializer-list assert cannot do. The printer's `retention`
  // parameter therefore defaults to null (= keep all) rather than a const value.
  FileRetention({this.maxFiles, this.maxAge, this.compress = false}) {
    if (maxFiles != null && maxFiles! <= 0) {
      throw ArgumentError.value(maxFiles, 'maxFiles', 'must be > 0 or null');
    }
    if (maxAge != null && maxAge! <= Duration.zero) {
      throw ArgumentError.value(
        maxAge,
        'maxAge',
        'must be > Duration.zero or null',
      );
    }
  }
}

/// Default file line formatter:
/// `<ISO-8601 timestamp> [LEVEL] <logger>: <message>`, with optional
/// ` data=<JSON>` and ` context=<JSON>` segments appended inline and
/// `error`/`stackTrace` on indented continuation lines.
///
/// `data` and `context` are serialized via `dart:convert`'s [JsonEncoder]
/// (with non-encodable objects falling back to `toString`), so values with
/// spaces, equals signs, quotes, or nested structures are encoded
/// unambiguously without any per-character escape logic in this package.
///
/// For machine-parseable output across the entire line, prefer
/// [GcpJsonPrinter] or [AwsJsonPrinter] passed via the `formatter`
/// parameter.
String defaultFileLineFormatter(LogEntry entry) {
  final buf = StringBuffer()
    ..write(entry.time.toUtc().toIso8601String())
    ..write(' [')
    ..write(entry.level.label)
    ..write('] ');
  // Drop the placeholder logger name (`dynamic` / `Object` / `Null`)
  // that appears when a static `HyperLogger.<level>(...)` is called
  // without `<T>`, otherwise every line would be prefixed with
  // `dynamic:`.
  if (!isGenericLoggerName(entry.loggerName)) {
    buf
      ..write(entry.loggerName)
      ..write(': ');
  }
  buf.write(entry.message);

  final obj = entry.object;
  if (obj is LogMessage) {
    final data = obj.data;
    if (data != null) {
      buf
        ..write(' data=')
        ..write(_jsonEncoder.convert(data));
    }
    final ctx = obj.context;
    if (ctx != null && ctx.isNotEmpty) {
      buf
        ..write(' context=')
        ..write(_jsonEncoder.convert(ctx));
    }
  }

  final err = entry.error;
  if (err != null) {
    buf.write('\n  error: ');
    buf.write(err);
  }

  final st = entry.stackTrace;
  if (st != null) {
    buf.write('\n  stack: ');
    buf.write(st.toString().trim().replaceAll('\n', '\n         '));
  }

  return buf.toString();
}

final _jsonEncoder = JsonEncoder((o) => o.toString());

/// Default [FileWriterErrorHandler]: writes the error (and its stack
/// trace, if provided) to stderr.
///
/// Format: a leading `hyper_logger: RotatingFilePrinter: <error>` line,
/// followed by the stack trace on continuation lines (each prefixed with
/// two spaces) when one is supplied. Skipping the stack would lose the
/// closure-throwing call site for `baseFilePathProvider` failures and
/// similar wrapped errors.
///
/// Falls back to silent if even stderr is unavailable (e.g. detached
/// background isolate) — logging must never crash the app.
void defaultFileWriterErrorHandler(Object error, StackTrace? stackTrace) {
  try {
    impl.writeStderrLine(formatDefaultFileWriterError(error, stackTrace));
  } catch (_) {
    // Last-resort silent fallback.
  }
}

/// Pure formatting helper for [defaultFileWriterErrorHandler]'s output.
///
/// Internal API. Exposed only so tests within this package can pin
/// the rendering without intercepting `stderr` (which has a sprawling
/// platform-specific stub surface). The exact output format is not part
/// of the package's public contract and may change without a major
/// version bump — do not depend on it from downstream code.
@internal
String formatDefaultFileWriterError(Object error, StackTrace? stackTrace) {
  final buf = StringBuffer('hyper_logger: RotatingFilePrinter: ')..write(error);
  if (stackTrace != null) {
    buf
      ..write('\n  ')
      ..write(stackTrace.toString().trim().replaceAll('\n', '\n  '));
  }
  return buf.toString();
}
