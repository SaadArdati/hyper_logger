import 'log_level.dart';
import 'log_mode.dart';

/// Configuration for a [ScopedLogger] instance.
///
/// Controls per-wrapper behavior: mode, level filtering, tagging,
/// and crash-reporting defaults.
///
/// Instances are compared by value for cache-key generation.
class LoggerOptions {
  /// Controls the operating mode for this scope. See [LogMode].
  final LogMode mode;

  /// Minimum log level for this wrapper. Messages below this level are
  /// silently dropped. `null` means no per-wrapper filtering (inherits the
  /// global level set on the root logger).
  final LogLevel? minLevel;

  /// Optional tag prepended to every message as `[tag] message`.
  /// Useful for feature-level or subsystem labeling.
  final String? tag;

  /// Default value for `skipCrashReporting` on [error] calls.
  /// Individual calls can still override this.
  final bool skipCrashReporting;

  const LoggerOptions({
    this.mode = LogMode.enabled,
    this.minLevel,
    this.tag,
    this.skipCrashReporting = false,
  });

  /// A default instance with all options at their defaults.
  static const LoggerOptions defaults = LoggerOptions();

  /// Returns a cache key string derived from all option values.
  ///
  /// Two [LoggerOptions] with identical field values produce the same key.
  /// The [typeName] is the stringified generic type from the wrapper.
  String cacheKey(String typeName) {
    return '$typeName|m=${mode.name}|l=${minLevel?.name ?? 'null'}'
        '|t=${tag ?? 'null'}|s=$skipCrashReporting';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggerOptions &&
          mode == other.mode &&
          minLevel == other.minLevel &&
          tag == other.tag &&
          skipCrashReporting == other.skipCrashReporting;

  @override
  int get hashCode => Object.hash(mode, minLevel, tag, skipCrashReporting);

  @override
  String toString() =>
      'LoggerOptions('
      'mode: $mode, '
      'minLevel: $minLevel, '
      'tag: $tag, '
      'skipCrashReporting: $skipCrashReporting)';
}
