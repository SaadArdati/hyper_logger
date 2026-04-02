import 'package:stack_trace/stack_trace.dart';

typedef CallerInfo = ({String className, String methodName});

class CallerExtractor {
  static const _internalLibraries = [
    'package:hyper_logger/',
    'package:logging/',
    'dart:',
  ];

  /// Extracts caller info from a raw StackTrace.
  ///
  /// When [prebuiltChain] is provided, skips the expensive [Chain.forTrace]
  /// call. The caller (typically [ContentExtractor]) is responsible for
  /// caching the chain across parser and extractor calls.
  CallerInfo? extract(StackTrace stackTrace, {Chain? prebuiltChain}) {
    try {
      final chain =
          prebuiltChain ??
          (stackTrace is Chain ? stackTrace : Chain.forTrace(stackTrace));
      return extractFromChain(chain);
    } catch (_) {
      return null;
    }
  }

  /// Extracts caller info from a pre-parsed Chain.
  CallerInfo? extractFromChain(Chain chain) {
    try {
      for (final trace in chain.traces) {
        for (final frame in trace.frames) {
          if (_isInternalFrame(frame)) continue;
          if (frame.member == null) continue;

          final parts = frame.member!.split('.');
          if (parts.length < 2) continue;

          return (
            className: parts[0],
            methodName: parts[1].replaceAll(RegExp(r'[<>()]'), ''),
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isInternalFrame(Frame frame) {
    final library = frame.library;
    for (int i = 0; i < _internalLibraries.length; i++) {
      if (library.startsWith(_internalLibraries[i])) return true;
    }
    return false;
  }
}
