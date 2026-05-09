/// Whether a [LogEntry.loggerName] is a generic placeholder produced by
/// calling a static `HyperLogger.<level>(...)` without a type argument.
///
/// `T = dynamic | Object | Null` all flow through `T.toString()` into
/// `loggerName`, and would surface as `"logger":"dynamic"` (etc.) in
/// JSON output and the file formatter — useless noise that suggests
/// the package is broken. The cloud printers and the default file
/// formatter use this helper to drop the field when there's nothing
/// meaningful to put in it.
///
/// Round-9 fix: previously each printer rendered the raw `loggerName`
/// even when it was the placeholder.
bool isGenericLoggerName(String name) {
  return name == 'dynamic' || name == 'Object' || name == 'Null';
}
