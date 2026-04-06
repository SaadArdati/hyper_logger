/// Controls how a logger (global or scoped) handles log calls.
///
/// The three states are mutually exclusive:
/// - [enabled] — normal behavior: delegates fire, printer output is produced.
/// - [silent] — the crash reporting delegate still fires, but printer
///   output is suppressed. Use for noisy modules whose errors should
///   still be reported.
/// - [disabled] — complete no-op. Nothing fires, nothing is printed.
enum LogMode {
  /// Normal logging. Delegates fire and printer output is produced.
  enabled,

  /// Delegates fire but printer output is suppressed.
  silent,

  /// Complete no-op. Nothing fires, nothing is printed.
  disabled,
}
