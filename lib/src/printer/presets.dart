import 'package:meta/meta.dart';

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
///
/// Every preset takes an `output` sink; the [ComposablePrinter]-backed ones
/// ([automatic], [human], [terminal], [ci]) also forward that class's
/// tuning parameters.
final class LogPrinterPresets {
  const LogPrinterPresets._();

  /// Detects the current [RuntimeEnvironment] and returns the best printer.
  ///
  /// Detection order: GCP → AWS → Azure → CI → human. See
  /// [EnvironmentDetector] for the signal behind each. This is the
  /// default when [HyperLogger.init] is called without an explicit
  /// printer on native platforms.
  ///
  /// {@macro hyper_logger.presets.tuning} Only the [ci] and [human]
  /// arms use them; the cloud arms emit a raw `stackTrace.toString()`
  /// and have no extraction pipeline to tune.
  static LogPrinter automatic({
    LogOutput? output,
    int methodCount = ComposablePrinter.defaultMethodCount,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    bool? suppressTypeNames,
  }) {
    ComposablePrinter buildHuman(TerminalCapabilities capabilities) => human(
      capabilities,
      output: output,
      methodCount: methodCount,
      errorMethodCount: errorMethodCount,
      excludePaths: excludePaths,
      showAsyncGaps: showAsyncGaps,
      suppressTypeNames: suppressTypeNames,
    );

    final env = _cachedEnvironment ??= const EnvironmentDetector().detect();
    return switch (env) {
      GcpEnvironment() => gcp(output: output),
      AwsEnvironment() => aws(output: output),
      AzureEnvironment() => azure(output: output),
      CiEnvironment() => ci(
        output: output,
        methodCount: methodCount,
        errorMethodCount: errorMethodCount,
        excludePaths: excludePaths,
        showAsyncGaps: showAsyncGaps,
        suppressTypeNames: suppressTypeNames,
      ),
      HumanEnvironment(:final capabilities) => buildHuman(capabilities),
      // [RuntimeEnvironment] isn't `sealed`, so a leaf added in a later
      // release would otherwise make this switch non-exhaustive.
      _ => buildHuman(EnvironmentDetector.detectCapabilities()),
    };
  }

  /// Cached [EnvironmentDetector.detect] result. The environment can't
  /// change over a process's lifetime, so repeat [automatic] calls
  /// reuse the first detection.
  static RuntimeEnvironment? _cachedEnvironment;

  /// Resets the cached environment-detection result. Test-only: tests
  /// that toggle `GCP_PROJECT`, `AWS_REGION`, etc. to exercise the
  /// dispatch matrix must clear the cache between permutations.
  @visibleForTesting
  static void resetEnvironmentCache() {
    _cachedEnvironment = null;
  }

  /// Builds a human-readable preset by composing decorators from the
  /// supplied [TerminalCapabilities]. Emoji and prefix are always on;
  /// the rest follow the capability bits:
  ///
  /// | Decorator | Added when   | Why                                     |
  /// |-----------|--------------|-----------------------------------------|
  /// | box       | `ansi && tty`| Borders need a stable line width, which IDE consoles and pipes don't provide. Sized from [TerminalCapabilities.width], else 120. |
  /// | color     | `ansi`       | Any ANSI sink renders it, IDE consoles included. |
  /// | timestamp | `!ansi`      | Without ANSI there's usually no host UI showing the time per row, so it has to travel inline. |
  ///
  /// Pass an explicit [TerminalCapabilities] when the sink's
  /// capabilities differ from stdout's (what
  /// [EnvironmentDetector.detectCapabilities] measures).
  ///
  /// {@template hyper_logger.presets.tuning}
  /// [methodCount], [errorMethodCount], [excludePaths], [showAsyncGaps],
  /// and [suppressTypeNames] pass straight through to the
  /// [ComposablePrinter] constructor, which documents each.
  /// {@endtemplate}
  static ComposablePrinter human(
    TerminalCapabilities capabilities, {
    LogOutput? output,
    int methodCount = ComposablePrinter.defaultMethodCount,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    bool? suppressTypeNames,
  }) {
    final useBox = capabilities.ansi && capabilities.tty;
    final useColor = capabilities.ansi;
    final useTimestamp = !capabilities.ansi;
    // A terminal reporting `terminalColumns: 1` (or 0) would otherwise
    // produce degenerate borders. The floor leaves room for the box
    // characters, the level prefix, and a few chars of message.
    final boxWidth = (capabilities.width ?? 120).clamp(40, 1024);

    return ComposablePrinter(
      [
        if (useTimestamp) const TimestampDecorator(),
        const EmojiDecorator(),
        if (useBox) BoxDecorator(lineLength: boxWidth),
        if (useColor) const AnsiColorDecorator(),
        const PrefixDecorator(),
      ],
      output: output ?? print,
      methodCount: methodCount,
      errorMethodCount: errorMethodCount,
      excludePaths: excludePaths,
      showAsyncGaps: showAsyncGaps,
      suppressTypeNames: suppressTypeNames,
    );
  }

  /// Shorthand for `human(TerminalCapabilities(ansi: true, tty: true))`:
  /// [EmojiDecorator] · [BoxDecorator] · [AnsiColorDecorator] ·
  /// [PrefixDecorator].
  ///
  /// {@macro hyper_logger.presets.tuning}
  static ComposablePrinter terminal({
    LogOutput? output,
    int methodCount = ComposablePrinter.defaultMethodCount,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    bool? suppressTypeNames,
  }) => human(
    const TerminalCapabilities(ansi: true, tty: true),
    output: output,
    methodCount: methodCount,
    errorMethodCount: errorMethodCount,
    excludePaths: excludePaths,
    showAsyncGaps: showAsyncGaps,
    suppressTypeNames: suppressTypeNames,
  );

  /// CI/CD preset — `<ISO-8601> [LEVEL] [Class.method] Message`.
  ///
  /// [TimestampDecorator] · [PrefixDecorator]. No color or box, so lines
  /// stay parseable by `grep` and CI log viewers.
  ///
  /// {@macro hyper_logger.presets.tuning}
  static ComposablePrinter ci({
    LogOutput? output,
    int methodCount = ComposablePrinter.defaultMethodCount,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    bool? suppressTypeNames,
  }) => ComposablePrinter(
    const [TimestampDecorator(), PrefixDecorator()],
    output: output ?? print,
    methodCount: methodCount,
    errorMethodCount: errorMethodCount,
    excludePaths: excludePaths,
    showAsyncGaps: showAsyncGaps,
    suppressTypeNames: suppressTypeNames,
  );

  /// Structured JSON for Google Cloud Logging. Use on Cloud Run, GKE,
  /// App Engine, and Cloud Functions, where stdout is parsed as
  /// structured logs. See [GcpJsonPrinter] for the field shape.
  static GcpJsonPrinter gcp({LogOutput? output}) =>
      GcpJsonPrinter(output: output ?? print);

  /// Structured JSON for AWS CloudWatch Logs. Use on Lambda, ECS, EKS,
  /// and EC2 instances shipping stdout to CloudWatch. See
  /// [AwsJsonPrinter] for the field shape.
  static AwsJsonPrinter aws({LogOutput? output}) =>
      AwsJsonPrinter(output: output ?? print);

  /// Structured JSON for Azure Application Insights' `traces` table. Use
  /// on App Service, Functions, and Container Apps, where stdout is
  /// scraped into Application Insights. See [AzureJsonPrinter] for the
  /// field shape and KQL query patterns.
  static AzureJsonPrinter azure({LogOutput? output}) =>
      AzureJsonPrinter(output: output ?? print);
}
