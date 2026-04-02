import 'package:logging/logging.dart' as logging;

import '../printer/log_printer.dart';

/// Configuration for a [HyperLoggerWrapper] instance.
///
/// Controls per-wrapper behavior: disabling, level filtering, tagging,
/// crash-reporting defaults, and optional printer overrides.
///
/// Instances are compared by value for cache-key generation.
class LoggerOptions {
  /// When `true`, every log method becomes a no-op.
  final bool disabled;

  /// Minimum log level for this wrapper. Messages below this level are
  /// silently dropped. `null` means no per-wrapper filtering (inherits the
  /// global level set on the root logger).
  final logging.Level? minLevel;

  /// Optional tag prepended to every message as `[tag] message`.
  /// Useful for feature-level or subsystem labeling.
  final String? tag;

  /// Default value for `skipCrashReporting` on [error] calls.
  /// Individual calls can still override this.
  final bool skipCrashReporting;

  /// Optional per-wrapper printer. When set, log records from this wrapper
  /// are routed to this printer instead of the global one.
  final LogPrinter? printer;

  const LoggerOptions({
    this.disabled = false,
    this.minLevel,
    this.tag,
    this.skipCrashReporting = false,
    this.printer,
  });

  /// A default instance with all options at their defaults.
  static const LoggerOptions defaults = LoggerOptions();

  /// Returns a cache key string derived from all option values.
  ///
  /// Two [LoggerOptions] with identical field values produce the same key.
  /// The [typeName] is the stringified generic type from the wrapper.
  String cacheKey(String typeName) {
    // printer identity uses hashCode since printers are stateful objects.
    final printerKey = printer != null ? printer.hashCode.toString() : 'null';
    return '$typeName|d=$disabled|l=${minLevel?.value ?? 'null'}'
        '|t=${tag ?? 'null'}|s=$skipCrashReporting|p=$printerKey';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggerOptions &&
          disabled == other.disabled &&
          minLevel == other.minLevel &&
          tag == other.tag &&
          skipCrashReporting == other.skipCrashReporting &&
          identical(printer, other.printer);

  @override
  int get hashCode => Object.hash(
    disabled,
    minLevel,
    tag,
    skipCrashReporting,
    printer != null ? identityHashCode(printer) : null,
  );

  @override
  String toString() =>
      'LoggerOptions('
      'disabled: $disabled, '
      'minLevel: $minLevel, '
      'tag: $tag, '
      'skipCrashReporting: $skipCrashReporting, '
      'printer: $printer)';
}
