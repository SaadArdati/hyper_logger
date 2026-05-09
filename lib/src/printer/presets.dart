import '../decorators/ansi_color_decorator.dart';
import '../decorators/box_decorator.dart';
import '../decorators/emoji_decorator.dart';
import '../decorators/prefix_decorator.dart';
import '../decorators/timestamp_decorator.dart';
import '../platform/environment_detector.dart';
import 'aws_json_printer.dart';
import 'azure_json_printer.dart';
import 'composable_printer.dart';
import 'gcp_json_printer.dart';
import 'log_printer.dart';

/// Static factory presets for common [LogPrinter] configurations.
///
/// | Preset      | Type                | When                                     |
/// |-------------|---------------------|------------------------------------------|
/// | [automatic] | (varies)            | best-effort detection of the environment |
/// | [human]     | [ComposablePrinter] | terminal/console output, capability-tuned|
/// | [terminal]  | [ComposablePrinter] | shorthand for a real terminal            |
/// | [ci]        | [ComposablePrinter] | CI/CD log streams (grep-friendly)        |
/// | [gcp]       | [GcpJsonPrinter]    | Google Cloud Logging                     |
/// | [aws]       | [AwsJsonPrinter]    | AWS CloudWatch / Lambda                  |
/// | [azure]     | [AzureJsonPrinter]  | Azure App Service / Functions / Container Apps |
extension LogPrinterPresets on LogPrinter {
  /// Detects the current [RuntimeEnvironment] and returns the best printer.
  ///
  /// Detection order: GCP → AWS → Azure → CI → human (capability-
  /// tuned). See [EnvironmentDetector] for details on each signal.
  ///
  /// This is the default when [HyperLogger.init] is called without an
  /// explicit printer on native platforms.
  ///
  /// The `default` arm exists because [RuntimeEnvironment] is no
  /// longer `sealed` — a future leaf added in a later release would
  /// otherwise produce a non-exhaustive switch. We fall back to a
  /// human preset built from the current stdout's capabilities, which
  /// is a reasonable best-effort for unknown environments.
  static LogPrinter automatic({LogOutput? output}) {
    final env = const EnvironmentDetector().detect();
    return switch (env) {
      GcpEnvironment() => gcp(output: output),
      AwsEnvironment() => aws(output: output),
      AzureEnvironment() => azure(output: output),
      CiEnvironment() => ci(output: output),
      HumanEnvironment(:final capabilities) => human(
        capabilities,
        output: output,
      ),
      _ => human(EnvironmentDetector.detectCapabilities(), output: output),
    };
  }

  /// Builds a human-readable preset by composing decorators based on
  /// the supplied [TerminalCapabilities].
  ///
  /// Composition rules (from the orthogonal capability bits):
  /// - Box drawing is added when both [TerminalCapabilities.ansi]
  ///   and [TerminalCapabilities.tty] are true (a real, ANSI-capable
  ///   terminal). Box edges depend on stable line widths, which IDE
  ///   Run Consoles and piped output don't reliably provide. The box's
  ///   `lineLength` honors [TerminalCapabilities.width] when present
  ///   so wide and narrow terminals both get appropriately-sized
  ///   borders; otherwise falls back to 120 columns.
  /// - ANSI color is added whenever [TerminalCapabilities.ansi] is
  ///   true. Works in any ANSI sink, including IDE Run Consoles.
  /// - Inline timestamp is added when [TerminalCapabilities.ansi]
  ///   is `false`. Without ANSI we usually have no host UI showing the
  ///   time per row (piped to file, low-feature shell), so embedding
  ///   the timestamp inline is the only way to keep it. With ANSI the
  ///   host (terminal scroll-back, IDE column) tracks time itself.
  /// - Emoji and prefix are always present.
  ///
  /// Pass an explicit [TerminalCapabilities] to override what
  /// [EnvironmentDetector.detectCapabilities] would have produced —
  /// useful when piping to a sink whose capabilities differ from
  /// stdout's.
  static ComposablePrinter human(
    TerminalCapabilities capabilities, {
    LogOutput? output,
  }) {
    final useBox = capabilities.ansi && capabilities.tty;
    final useColor = capabilities.ansi;
    final useTimestamp = !capabilities.ansi;
    // Clamp the width to a sane minimum so a pathological terminal reporting
    // `terminalColumns: 1` (or 0) doesn't produce degenerate borders. The
    // clamp leaves enough room for box characters + the level prefix + at
    // least a few chars of message.
    final boxWidth = (capabilities.width ?? 120).clamp(40, 1024);

    return ComposablePrinter([
      if (useTimestamp) const TimestampDecorator(),
      const EmojiDecorator(),
      if (useBox) BoxDecorator(lineLength: boxWidth),
      if (useColor) const AnsiColorDecorator(),
      const PrefixDecorator(),
    ], output: output ?? print);
  }

  /// Shorthand for a full real-terminal preset:
  /// `human(TerminalCapabilities(ansi: true, tty: true))`.
  ///
  /// Applies: [EmojiDecorator] · [BoxDecorator] · [AnsiColorDecorator] ·
  /// [PrefixDecorator].
  static ComposablePrinter terminal({LogOutput? output}) =>
      human(const TerminalCapabilities(ansi: true, tty: true), output: output);

  /// CI/CD preset — `<ISO-8601> [LEVEL] [Class.method] Message`.
  ///
  /// Applies: [TimestampDecorator] · [PrefixDecorator]. No color or
  /// box so log lines are parseable as plain text by `grep`/CI viewers.
  static ComposablePrinter ci({LogOutput? output}) => ComposablePrinter(const [
    TimestampDecorator(),
    PrefixDecorator(),
  ], output: output ?? print);

  /// Returns a [GcpJsonPrinter] for Google Cloud Logging structured output.
  ///
  /// Use on Cloud Run, GKE, App Engine, and Cloud Functions where stdout is
  /// parsed as structured logs.
  static GcpJsonPrinter gcp({LogOutput? output}) =>
      GcpJsonPrinter(output: output ?? print);

  /// Returns an [AwsJsonPrinter] for AWS CloudWatch Logs.
  ///
  /// Use on Lambda, ECS, EKS, and EC2 instances configured to ship stdout
  /// to CloudWatch.
  static AwsJsonPrinter aws({LogOutput? output}) =>
      AwsJsonPrinter(output: output ?? print);

  /// Returns an [AzureJsonPrinter] for Azure Application Insights' `traces`
  /// table — `severityLevel` (numeric), `message`, `time`, and a nested
  /// `customDimensions` map for context.
  ///
  /// Use on Azure App Service, Functions, and Container Apps where
  /// stdout is scraped by Container Insights / the OpenTelemetry log
  /// exporter / a custom-log-file data collector and routed into
  /// Application Insights. See the [AzureJsonPrinter] dartdoc for the
  /// exact field shape and KQL query patterns.
  static AzureJsonPrinter azure({LogOutput? output}) =>
      AzureJsonPrinter(output: output ?? print);
}
