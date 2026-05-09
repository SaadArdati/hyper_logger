/// Web-only entry point for `hyper_logger`.
///
/// Re-exports [WebConsolePrinter] so callers can construct it directly
/// (e.g. with a custom `methodCount` or `suppressTypeNames: true`)
/// without dipping into `package:hyper_logger/src/...` imports.
///
/// The default web printer is auto-installed via
/// `printer_factory_web.dart` — only import this file when you need
/// to construct the printer with non-default options.
///
/// Cross-platform code: this file pulls in `dart:js_interop` and
/// will not compile on the VM. In a shared codebase, import it behind
/// a conditional import:
///
/// ```dart
/// import 'package:hyper_logger/hyper_logger.dart';
/// import 'package:hyper_logger/web.dart'
///     if (dart.library.io) 'web_stub.dart';
/// ```
///
/// or guard the construction site with `kIsWeb` (Flutter) /
/// `bool.fromEnvironment('dart.library.html')` (pure Dart).
library;

export 'src/printer/web_console_printer.dart' show WebConsolePrinter;
