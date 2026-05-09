import '../model/log_entry.dart';
import 'log_printer.dart';

/// A [LogPrinter] that fans each [LogEntry] out to a fixed list of child
/// printers in order.
///
/// Use this when you want the same log stream to land in more than one
/// place — typical shapes are:
///
/// - **Terminal + file**: a human-readable preset for live debugging
///   plus a [RotatingFilePrinter] for archival.
/// - **Terminal + cloud**: a developer-friendly local view plus a
///   [GcpJsonPrinter] / [AwsJsonPrinter] / [AzureJsonPrinter] for
///   production aggregation.
/// - **Primary + fallback**: the primary sink does the real work and a
///   secondary printer captures everything for diagnostics.
///
/// ```dart
/// HyperLogger.init(
///   printer: MultiPrinter([
///     LogPrinterPresets.terminal(),
///     RotatingFilePrinter(
///       baseFilePathProvider: () => '/var/log/app.log',
///       rotationConfig: FileRotationConfig.size(
///         maxBytes: 10 * 1024 * 1024,
///         maxFiles: 5,
///         compress: true,
///       ),
///     ),
///   ]),
/// );
/// ```
///
/// ### Error handling
///
/// Every child's [log] call runs even when earlier children throw —
/// one buggy sink does NOT prevent the others from receiving the entry.
/// After all children have run, if any threw, [log] re-raises a
/// [MultiPrinterError] aggregating the per-child failures (with their
/// original positions and stack traces). `HyperLogger`'s outer pipeline
/// catches this and routes it through `setPipelineErrorHandler`, so a
/// failing fan-out isn't silently lost — it's reported once via the
/// observability hook.
///
/// Per the [LogPrinter] contract, a well-behaved child doesn't throw in
/// the first place; the catch-and-aggregate is defense-in-depth, not a
/// license to ship throwing printers.
///
/// ### Composition
///
/// `MultiPrinter` composes with every other printer wrapper in the
/// package, because it just IS a [LogPrinter]:
///
/// ```dart
/// // Throttle the entire fanout as a unit:
/// ThrottledPrinter(MultiPrinter([terminal, file]), maxPerSecond: 100);
///
/// // Throttle just the remote sink, leave the file alone:
/// MultiPrinter([
///   ThrottledPrinter(remote, maxPerSecond: 50),
///   file,
/// ]);
///
/// // Nested fanouts (a fanout-of-fanouts):
/// MultiPrinter([cheap, MultiPrinter([expensive1, expensive2])]);
/// ```
///
/// ### Lifecycle
///
/// [dispose] is fanned out to every child in order. Per the
/// [LogPrinter.dispose] contract, dispose is best-effort and has no
/// listener to surface errors to, so children's dispose failures are
/// swallowed individually — a throwing child can't prevent the others
/// from cleaning up, but you won't hear about a failed dispose either.
class MultiPrinter implements LogPrinter {
  /// The unmodifiable list of child printers, in dispatch order.
  final List<LogPrinter> printers;

  /// Creates a fanout printer that delivers each entry to every printer
  /// in [printers], in the order they were given.
  ///
  /// An empty list is allowed and behaves as a silent sink — useful as
  /// a placeholder while wiring up integrations.
  MultiPrinter(List<LogPrinter> printers)
      : printers = List.unmodifiable(printers);

  @override
  void log(LogEntry entry) {
    // Indexed for-loop avoids iterator allocation on the hot path.
    // Errors are aggregated rather than swallowed so HyperLogger's
    // pipeline-error hook surfaces them: a buggy child isn't silently
    // invisible.
    List<MultiPrinterChildError>? failures;
    for (var i = 0; i < printers.length; i++) {
      try {
        printers[i].log(entry);
      } catch (e, st) {
        (failures ??= <MultiPrinterChildError>[])
            .add(MultiPrinterChildError(i, e, st));
      }
    }
    if (failures != null) {
      throw MultiPrinterError(failures);
    }
  }

  @override
  void dispose() {
    for (var i = 0; i < printers.length; i++) {
      try {
        printers[i].dispose();
      } catch (_) {
        // dispose() is best-effort and has no listener; aggregating
        // here would have nowhere to go. Swallow individually so a
        // throwing child can't prevent the rest from cleaning up.
      }
    }
  }
}

/// Thrown by [MultiPrinter.log] when one or more child printers threw
/// during dispatch.
///
/// All children still received the entry before this is thrown — the
/// fanout is best-effort delivery first, surface-the-failure second.
/// Caught by `HyperLogger`'s pipeline-error machinery and routed
/// through `setPipelineErrorHandler` (rate-limited to once per source
/// per session).
class MultiPrinterError implements Exception {
  /// Per-child failures, in the order children were invoked. Each entry
  /// carries the child's index in the [MultiPrinter.printers] list, the
  /// original error, and its stack trace.
  final List<MultiPrinterChildError> childErrors;

  MultiPrinterError(List<MultiPrinterChildError> childErrors)
      : childErrors = List.unmodifiable(childErrors);

  @override
  String toString() {
    final n = childErrors.length;
    final buf = StringBuffer(
      'MultiPrinterError: $n child printer'
      '${n == 1 ? '' : 's'} threw during log():\n',
    );
    for (final c in childErrors) {
      buf
        ..write('  [')
        ..write(c.index)
        ..write('] ')
        ..writeln(c.error);
    }
    return buf.toString().trimRight();
  }
}

/// One child printer's failure inside a [MultiPrinterError].
class MultiPrinterChildError {
  /// The position of the failed child in [MultiPrinter.printers].
  final int index;

  /// The error the child threw.
  final Object error;

  /// The stack trace captured at the throw site.
  final StackTrace stackTrace;

  const MultiPrinterChildError(this.index, this.error, this.stackTrace);
}
