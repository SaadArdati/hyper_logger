// Core API
//
// `hyper_logger_base.dart` re-exports `ScopedLogger` and `ScopedLoggerApi`
// via the `part 'scoped_logger.dart';` directive (round-10b refactor —
// makes `_logScoped` truly library-private).
export 'src/hyper_logger_base.dart';
export 'src/hyper_logger_mixin.dart';

// Platform / runtime detection
export 'src/platform/environment_detector.dart'
    show
        AwsEnvironment,
        AzureEnvironment,
        CiEnvironment,
        EnvironmentDetector,
        GcpEnvironment,
        HumanEnvironment,
        RuntimeEnvironment,
        TerminalCapabilities;

// Model
export 'src/model/ansi_color.dart';
export 'src/model/log_entry.dart';
export 'src/model/log_level.dart';
export 'src/model/log_message.dart';
export 'src/model/log_mode.dart';
export 'src/model/log_style.dart';
export 'src/model/logger_options.dart';

// Delegates
export 'src/delegates/crash_reporting_delegate.dart';

// Decorators
export 'src/decorators/log_decorator.dart';
export 'src/decorators/box_decorator.dart';
export 'src/decorators/emoji_decorator.dart';
export 'src/decorators/ansi_color_decorator.dart';
export 'src/decorators/timestamp_decorator.dart';
export 'src/decorators/prefix_decorator.dart';

// Printers
export 'src/printer/log_printer.dart';
export 'src/printer/composable_printer.dart';
export 'src/printer/presets.dart';
export 'src/printer/direct_printer.dart';
export 'src/printer/gcp_json_printer.dart';
export 'src/printer/aws_json_printer.dart';
export 'src/printer/azure_json_printer.dart';
export 'src/printer/rotating_file_printer.dart'
    show
        RotatingFilePrinter,
        FileRotationConfig,
        FileLineFormatter,
        FileWriterErrorHandler,
        defaultFileLineFormatter,
        defaultFileWriterErrorHandler;
export 'src/printer/throttled_printer.dart';
export 'src/printer/multi_printer.dart';

// WebConsolePrinter is not exported from the main barrel because it
// depends on dart:js_interop (web-only). It's auto-selected on web
// platforms via printer_factory_web.dart. To construct it directly
// with non-default options, import the stable sub-barrel:
//
//   import 'package:hyper_logger/web.dart';
//
// (See `lib/web.dart`.) Avoid importing from `package:hyper_logger/src/...`
// — anything under `src/` may be relocated without a major version bump.
