import '../decorators/ansi_color_decorator.dart';
import '../decorators/box_decorator.dart';
import '../decorators/emoji_decorator.dart';
import '../decorators/prefix_decorator.dart';
import '../decorators/timestamp_decorator.dart';
import '../platform/environment_detector.dart';
import 'composable_printer.dart';
import 'json_printer.dart';
import 'log_printer.dart';

/// Static factory presets for common [LogPrinter] configurations.
///
/// Each preset returns a ready-to-use [LogPrinter] for a specific environment:
///
/// | Preset      | Type                | Decorators / Config                  | Best for            |
/// |-------------|---------------------|--------------------------------------|---------------------|
/// | [automatic] | (varies)            | best-effort detection of environment | default / unknown   |
/// | [terminal]  | [ComposablePrinter] | emoji + box + color + prefix         | local dev terminal  |
/// | [ci]        | [ComposablePrinter] | timestamp + prefix                   | CI/CD log streams   |
/// | [ide]       | [ComposablePrinter] | emoji + prefix                       | IDE run console     |
/// | [cloudRun]  | [JsonPrinter]       | structured JSON per line             | Google Cloud Run    |
extension LogPrinterPresets on LogPrinter {
  /// Detects the current [RuntimeEnvironment] and returns the best printer.
  ///
  /// Detection order: Cloud Run → CI → IDE → terminal (ANSI) → plain.
  /// See [EnvironmentDetector] for details on each signal.
  ///
  /// This is the default when [HyperLogger.init] is called without an
  /// explicit printer on native platforms.
  static LogPrinter automatic({LogOutput? output}) {
    final env = const EnvironmentDetector().detect();
    return switch (env) {
      .cloudRun => cloudRun(output: output),
      .ci => ci(output: output),
      .ide => ide(output: output),
      .terminal => terminal(output: output),
      .plain => _plain(output: output),
    };
  }

  /// Creates a [ComposablePrinter] optimised for local terminal output.
  ///
  /// Applies: [EmojiDecorator] · [BoxDecorator] · [AnsiColorDecorator] ·
  /// [PrefixDecorator].
  static ComposablePrinter terminal({LogOutput? output}) =>
      ComposablePrinter(const [
        EmojiDecorator(),
        BoxDecorator(),
        AnsiColorDecorator(),
        PrefixDecorator(),
      ], output: output ?? print);

  /// Creates a [ComposablePrinter] suited for CI/CD log streams.
  ///
  /// Applies: [TimestampDecorator] · [PrefixDecorator].
  /// No colour or box so that log lines are parseable as plain text.
  /// Output format: `<ISO-8601> [LEVEL] [Class.method] Message`
  static ComposablePrinter ci({LogOutput? output}) => ComposablePrinter(const [
    TimestampDecorator(),
    PrefixDecorator(),
  ], output: output ?? print);

  /// Creates a [ComposablePrinter] suited for IDE run-console output.
  ///
  /// Applies: [EmojiDecorator] · [PrefixDecorator].
  /// Emoji gives quick visual scanning without box-drawing clutter.
  static ComposablePrinter ide({LogOutput? output}) => ComposablePrinter(const [
    EmojiDecorator(),
    PrefixDecorator(),
  ], output: output ?? print);

  /// Returns a [JsonPrinter] for Google Cloud Run structured logging.
  ///
  /// Each log entry is emitted as a single JSON object per line, compatible
  /// with Google Cloud Logging's structured log format.
  static JsonPrinter cloudRun({LogOutput? output}) =>
      JsonPrinter(output: output ?? print);

  /// Minimal preset for environments without ANSI support.
  ///
  /// Applies: [TimestampDecorator] · [EmojiDecorator] · [PrefixDecorator].
  /// Timestamps for traceability, emoji for quick scanning, no color or box.
  static ComposablePrinter _plain({LogOutput? output}) => ComposablePrinter(
    const [TimestampDecorator(), EmojiDecorator(), PrefixDecorator()],
    output: output ?? print,
  );
}
