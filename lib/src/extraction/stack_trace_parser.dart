import 'dart:math' show max;
import 'package:stack_trace/stack_trace.dart';

/// Parses a [StackTrace] into formatted, filtered lines with multi-column alignment.
///
/// Each line has the form:
/// ```
/// #N  member  library  line:column
/// ```
/// where each column is right-padded to the maximum width seen in the trace,
/// producing a consistently aligned table of frames.
class StackTraceParser {
  final int methodCount;
  final int? errorMethodCount;
  final List<String> excludePaths;
  final bool showAsyncGaps;

  static const _internalPaths = ['package:logging/', 'package:hyper_logger/'];

  const StackTraceParser({
    required this.methodCount,
    this.errorMethodCount,
    required this.excludePaths,
    required this.showAsyncGaps,
  });

  /// Parses a [StackTrace] into formatted, filtered lines.
  ///
  /// Returns an empty list for null input.
  /// Uses [errorMethodCount] when [isError] is true (falls back to [methodCount]
  /// when [errorMethodCount] is null). Uses [methodCount] when [isError] is false.
  ///
  /// When [prebuiltChain] is provided, skips the expensive [Chain.forTrace] call.
  /// The caller (typically [ContentExtractor]) is responsible for caching the
  /// chain across parser and extractor calls.
  List<String> parse(
    StackTrace? stackTrace, {
    bool isError = false,
    Chain? prebuiltChain,
  }) {
    if (stackTrace == null) return const [];

    final chain =
        prebuiltChain ??
        (stackTrace is Chain ? stackTrace : Chain.forTrace(stackTrace));
    final effectiveMethodCount = isError
        ? (errorMethodCount ?? methodCount)
        : methodCount;

    if (effectiveMethodCount == 0) return const [];

    final result = <String>[];
    var isFirstTrace = true;
    var globalFrameIndex = 0;

    for (int t = 0; t < chain.traces.length; t++) {
      final trace = chain.traces[t];

      // 1. Filter frames.
      final filtered = <Frame>[];
      for (int f = 0; f < trace.frames.length; f++) {
        final frame = trace.frames[f];
        if (!_shouldDiscard(frame)) {
          filtered.add(frame);
        }
      }

      if (filtered.isEmpty) continue;

      // 2. Apply method count limit.
      final frames = filtered.length > effectiveMethodCount
          ? filtered.sublist(0, effectiveMethodCount)
          : filtered;

      if (frames.isEmpty) continue;

      // 3. Add async gap separator between traces (when enabled).
      if (!isFirstTrace && showAsyncGaps) {
        result.add(
          '╔══════════════════════════════ asynchronous gap ══════════════════════════════╗',
        );
      }
      isFirstTrace = false;

      // 4. Calculate column widths for alignment.
      var maxMemberWidth = 0;
      var maxLibraryWidth = 0;
      var maxLineWidth = 0;

      for (int i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final memberLen = (frame.member ?? '<anonymous>').length;
        final libraryLen = frame.library.length;
        final locationLen = '${frame.line}:${frame.column}'.length;

        maxMemberWidth = max(maxMemberWidth, memberLen);
        maxLibraryWidth = max(maxLibraryWidth, libraryLen);
        maxLineWidth = max(maxLineWidth, locationLen);
      }

      // Add two spaces of padding between columns.
      const padding = 2;
      maxMemberWidth += padding;
      maxLibraryWidth += padding;

      // Width of the frame counter field (e.g. "10" needs 2 chars).
      final countWidth = frames.length.toString().length;

      // 5. Format each frame.
      for (int i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final member = (frame.member ?? '<anonymous>').padRight(maxMemberWidth);
        final library = frame.library.padRight(maxLibraryWidth);
        final location = '${frame.line}:${frame.column}'.padRight(maxLineWidth);

        // 6. Choose numbering scheme.
        // Per-trace when async gaps enabled, global when disabled.
        final displayCount = showAsyncGaps ? i : globalFrameIndex;

        final line =
            '#${displayCount.toString().padRight(countWidth)} $member$library$location';
        result.add(line);

        if (!showAsyncGaps) {
          globalFrameIndex++;
        }
      }
    }

    return result;
  }

  /// Returns true if [frame] should be excluded from output.
  bool _shouldDiscard(Frame frame) {
    final library = frame.library;

    // Check internal paths first.
    for (int i = 0; i < _internalPaths.length; i++) {
      if (library.startsWith(_internalPaths[i])) return true;
    }

    // Then user-configured exclude paths.
    for (int i = 0; i < excludePaths.length; i++) {
      final path = excludePaths[i];
      if (library == path || library.startsWith('$path/')) return true;
    }

    return false;
  }
}
