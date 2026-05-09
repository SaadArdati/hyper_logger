import '../model/log_entry.dart';

/// A callback that receives a formatted log line.
typedef LogOutput = void Function(String line);

/// Base interface for all log printers.
///
/// A [LogPrinter] receives a [LogEntry] and is responsible for formatting
/// and emitting it to its destination (terminal, JSON stream, remote
/// service, etc.).
abstract class LogPrinter {
  /// Releases any resources held by this printer (timers, file
  /// handles, network sockets, etc.).
  ///
  /// Default implementation is a no-op for stateless printers.
  /// Stateful printers MUST override — for example, `ThrottledPrinter`
  /// cancels its drain timer, and `RotatingFilePrinter` schedules its
  /// async `close()` and returns immediately.
  ///
  /// `HyperLogger.init(printer: ...)` calls [dispose] on the previous
  /// printer when replacing it, so users replacing the global printer
  /// at runtime don't leak resources.
  ///
  /// Implementations should be idempotent — multiple calls must not
  /// crash. Async cleanup (e.g. file flushing) belongs on a separate
  /// `close()` method that callers explicitly await; [dispose] runs
  /// synchronously and best-effort.
  void dispose() {}

  /// Emits [entry] to this printer's destination.
  ///
  /// Implementation contract:
  /// - Synchronous. This call must not return a `Future` — the
  ///   `HyperLogger` emit path is synchronous to keep the call site
  ///   non-blocking. If you need async work (network, file rotation,
  ///   compression), schedule it off-path inside the implementation
  ///   and surface failures via your own callback (see
  ///   `RotatingFilePrinter`'s `onError`).
  /// - Must not throw. A printer that throws crashes the caller's
  ///   log site. Wrap your I/O in `try/catch` and route failures to
  ///   `stderr` or a user-supplied error hook.
  /// - No back-pressure. Drop or queue overflow yourself —
  ///   `ThrottledPrinter` is one example of a wrapper that does
  ///   exactly that.
  void log(LogEntry entry);
}
