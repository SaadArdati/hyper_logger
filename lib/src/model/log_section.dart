/// The semantic role of a [LogSection] within a rendered log entry.
enum SectionKind {
  /// The main human-readable message.
  message,

  /// Structured data attached to the log entry.
  data,

  /// An error or exception object.
  error,

  /// A stack trace.
  stackTrace,

  /// A timestamp string.
  timestamp,
}

/// A named group of pre-split lines that make up one part of a log entry.
///
/// [SectionRenderer]s consume [LogSection]s to produce the final output.
class LogSection {
  /// The semantic role of this section.
  final SectionKind kind;

  /// The lines belonging to this section (already split on `\n`).
  final List<String> lines;

  const LogSection(this.kind, this.lines);
}
