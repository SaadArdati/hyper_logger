// ignore_for_file: avoid_print
/// Benchmark comparing String.split('\n') alternatives for single-line messages.
///
/// Context: In a logging hot path, most messages are single-line. Calling
/// `message.split('\n')` unconditionally allocates a new `List<String>` with one
/// element even when there's nothing to split. This benchmark measures
/// alternatives.
///
/// Run: dart run benchmark/split_alternatives_benchmark.dart
void main() {
  print('');
  print('String.split("\\n") alternatives benchmark');
  print('=' * 80);
  print('');
  print(
    'Config: $_kWarmup warmup, $_kSamples samples x '
    '$_kIterationsPerSample iterations',
  );
  print('');

  // ═══════════════════════════════════════════════════════════════════════════
  // Test messages
  // ═══════════════════════════════════════════════════════════════════════════

  const singleLine = 'User logged in successfully';
  const multiLine = 'Line 1\nLine 2\nLine 3';
  const longSingleLine =
      'GET /api/v2/accounts/12345/positions HTTP/1.1 200 OK '
      'Content-Type: application/json; charset=utf-8 '
      'X-Request-Id: abc-def-ghi-jkl-mno-pqr-stu-vwx';
  const longMultiLine =
      'Request failed:\n'
      '  URL: https://api.example.com/v2/accounts/12345\n'
      '  Status: 500\n'
      '  Body: {"error":"internal","message":"something went wrong"}\n'
      '  Duration: 1234ms';

  int sink = 0; // prevent DCE

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. BASELINE: String.split('\n')
  // ═══════════════════════════════════════════════════════════════════════════

  _header('1. Baseline: String.split("\\n")');

  _bench('split() — single-line (27 chars)', () {
    return () {
      final parts = singleLine.split('\n');
      sink += parts.length;
    };
  });

  _bench('split() — multi-line (3 lines)', () {
    return () {
      final parts = multiLine.split('\n');
      sink += parts.length;
    };
  });

  _bench('split() — long single-line (168 chars)', () {
    return () {
      final parts = longSingleLine.split('\n');
      sink += parts.length;
    };
  });

  _bench('split() — long multi-line (5 lines)', () {
    return () {
      final parts = longMultiLine.split('\n');
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. APPROACH A: contains() guard + split()
  //    if (!msg.contains('\n')) return [msg]; else return msg.split('\n');
  // ═══════════════════════════════════════════════════════════════════════════

  _header('2. Approach A: contains() guard + split()');

  _bench('contains-guard — single-line (27 chars)', () {
    return () {
      final parts = _splitContainsGuard(singleLine);
      sink += parts.length;
    };
  });

  _bench('contains-guard — multi-line (3 lines)', () {
    return () {
      final parts = _splitContainsGuard(multiLine);
      sink += parts.length;
    };
  });

  _bench('contains-guard — long single-line (168 chars)', () {
    return () {
      final parts = _splitContainsGuard(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('contains-guard — long multi-line (5 lines)', () {
    return () {
      final parts = _splitContainsGuard(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. APPROACH B: indexOf() loop + substring()
  //    Manual scanning with indexOf, collecting substrings.
  // ═══════════════════════════════════════════════════════════════════════════

  _header('3. Approach B: indexOf() loop + substring()');

  _bench('indexOf-loop — single-line (27 chars)', () {
    return () {
      final parts = _splitIndexOf(singleLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-loop — multi-line (3 lines)', () {
    return () {
      final parts = _splitIndexOf(multiLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-loop — long single-line (168 chars)', () {
    return () {
      final parts = _splitIndexOf(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-loop — long multi-line (5 lines)', () {
    return () {
      final parts = _splitIndexOf(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. APPROACH C: indexOf() with early return for single-line
  //    Check indexOf first; if -1, return unmodifiable singleton.
  // ═══════════════════════════════════════════════════════════════════════════

  _header('4. Approach C: indexOf() early return + split() fallback');

  _bench('indexOf-early-return — single-line (27 chars)', () {
    return () {
      final parts = _splitIndexOfEarlyReturn(singleLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-early-return — multi-line (3 lines)', () {
    return () {
      final parts = _splitIndexOfEarlyReturn(multiLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-early-return — long single-line (168 chars)', () {
    return () {
      final parts = _splitIndexOfEarlyReturn(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('indexOf-early-return — long multi-line (5 lines)', () {
    return () {
      final parts = _splitIndexOfEarlyReturn(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. APPROACH D: codeUnitAt() manual scan
  //    Lowest-level: scan code units, collect substrings.
  // ═══════════════════════════════════════════════════════════════════════════

  _header('5. Approach D: codeUnitAt() manual scan');

  _bench('codeUnitAt-scan — single-line (27 chars)', () {
    return () {
      final parts = _splitCodeUnitAt(singleLine);
      sink += parts.length;
    };
  });

  _bench('codeUnitAt-scan — multi-line (3 lines)', () {
    return () {
      final parts = _splitCodeUnitAt(multiLine);
      sink += parts.length;
    };
  });

  _bench('codeUnitAt-scan — long single-line (168 chars)', () {
    return () {
      final parts = _splitCodeUnitAt(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('codeUnitAt-scan — long multi-line (5 lines)', () {
    return () {
      final parts = _splitCodeUnitAt(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. APPROACH E: Cached singleton list (re-use for single-line)
  //    Pre-allocate a reusable list; only create a new one for multi-line.
  // ═══════════════════════════════════════════════════════════════════════════

  _header('6. Approach E: indexOf guard + const singleton wrapper');

  _bench('singleton-wrap — single-line (27 chars)', () {
    return () {
      final parts = _splitSingletonWrap(singleLine);
      sink += parts.length;
    };
  });

  _bench('singleton-wrap — multi-line (3 lines)', () {
    return () {
      final parts = _splitSingletonWrap(multiLine);
      sink += parts.length;
    };
  });

  _bench('singleton-wrap — long single-line (168 chars)', () {
    return () {
      final parts = _splitSingletonWrap(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('singleton-wrap — long multi-line (5 lines)', () {
    return () {
      final parts = _splitSingletonWrap(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. MICRO-BENCHMARKS: Individual operations
  // ═══════════════════════════════════════════════════════════════════════════

  _header('7. Micro-benchmarks: individual operations');

  _bench('contains("\\n") — single-line (27 chars)', () {
    return () {
      if (singleLine.contains('\n')) sink++;
      sink++;
    };
  });

  _bench('indexOf("\\n") — single-line (27 chars)', () {
    return () {
      if (singleLine.contains('\n')) sink++;
      sink++;
    };
  });

  _bench('contains("\\n") — long single-line (168 chars)', () {
    return () {
      if (longSingleLine.contains('\n')) sink++;
      sink++;
    };
  });

  _bench('indexOf("\\n") — long single-line (168 chars)', () {
    return () {
      if (longSingleLine.contains('\n')) sink++;
      sink++;
    };
  });

  _bench('[msg] list literal — allocation cost', () {
    return () {
      final list = [singleLine];
      sink += list.length;
    };
  });

  _bench('List.unmodifiable([msg]) — allocation cost', () {
    return () {
      final list = List<String>.unmodifiable([singleLine]);
      sink += list.length;
    };
  });

  _bench('List.filled(1, msg) — allocation cost', () {
    return () {
      final list = List<String>.filled(1, singleLine);
      sink += list.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. WINNER VARIANT: indexOf guard + list literal (no unmodifiable)
  // ═══════════════════════════════════════════════════════════════════════════

  _header('8. Best approach: indexOf guard + [s] list literal');

  _bench('best — single-line (27 chars)', () {
    return () {
      final parts = _splitBest(singleLine);
      sink += parts.length;
    };
  });

  _bench('best — multi-line (3 lines)', () {
    return () {
      final parts = _splitBest(multiLine);
      sink += parts.length;
    };
  });

  _bench('best — long single-line (168 chars)', () {
    return () {
      final parts = _splitBest(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('best — long multi-line (5 lines)', () {
    return () {
      final parts = _splitBest(longMultiLine);
      sink += parts.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. VARIANT: Same as best but returning List.filled(1, s)
  // ═══════════════════════════════════════════════════════════════════════════

  _header('9. Variant: indexOf guard + List.filled(1, s)');

  _bench('filled — single-line (27 chars)', () {
    return () {
      final parts = _splitFilled(singleLine);
      sink += parts.length;
    };
  });

  _bench('filled — multi-line (3 lines)', () {
    return () {
      final parts = _splitFilled(multiLine);
      sink += parts.length;
    };
  });

  _bench('filled — long single-line (168 chars)', () {
    return () {
      final parts = _splitFilled(longSingleLine);
      sink += parts.length;
    };
  });

  _bench('filled — long multi-line (5 lines)', () {
    return () {
      final parts = _splitFilled(longMultiLine);
      sink += parts.length;
    };
  });

  print('');
  print('=' * 80);
  print('Done. Sink: $sink (prevents dead-code elimination)');
}

// ── Split implementations ────────────────────────────────────────────────────

/// Approach A: Guard with contains(), fall back to split().
List<String> _splitContainsGuard(String s) {
  if (!s.contains('\n')) return [s];
  return s.split('\n');
}

/// Approach B: Manual indexOf loop.
List<String> _splitIndexOf(String s) {
  final result = <String>[];
  int start = 0;
  int idx;
  while ((idx = s.indexOf('\n', start)) != -1) {
    result.add(s.substring(start, idx));
    start = idx + 1;
  }
  result.add(s.substring(start));
  return result;
}

/// Approach C: indexOf early return for single-line, split() for multi-line.
List<String> _splitIndexOfEarlyReturn(String s) {
  if (!s.contains('\n')) return [s];
  return s.split('\n');
}

/// Approach D: Manual codeUnitAt scan.
List<String> _splitCodeUnitAt(String s) {
  const int newline = 0x0A; // '\n'
  final len = s.length;
  final result = <String>[];
  int start = 0;
  for (int i = 0; i < len; i++) {
    if (s.codeUnitAt(i) == newline) {
      result.add(s.substring(start, i));
      start = i + 1;
    }
  }
  result.add(s.substring(start));
  return result;
}

/// Approach E: indexOf guard + unmodifiable singleton wrapper for single-line.
/// Avoids allocating a growable list for the common single-line case.
List<String> _splitSingletonWrap(String s) {
  if (!s.contains('\n')) {
    return List<String>.unmodifiable([s]);
  }
  return s.split('\n');
}

/// Best approach: indexOf guard + simple list literal.
/// Combines the fastest guard (indexOf) with the cheapest allocation ([s]).
List<String> _splitBest(String s) {
  if (!s.contains('\n')) return [s];
  return s.split('\n');
}

/// Variant: indexOf guard + List.filled for fixed-size allocation.
List<String> _splitFilled(String s) {
  if (!s.contains('\n')) return List<String>.filled(1, s);
  return s.split('\n');
}

// ── Benchmark infrastructure ─────────────────────────────────────────────────

const int _kWarmup = 500;
const int _kSamples = 30;
const int _kIterationsPerSample = 50000;

void _header(String title) {
  print('');
  print('-- $title ${'─' * (76 - title.length).clamp(0, 76)}');
  print('');
  print(
    '  ${'Name'.padRight(56)} '
    '${'median'.padLeft(8)} '
    '${'mean'.padLeft(8)} '
    '${'min'.padLeft(8)} '
    '${'ops/sec'.padLeft(12)}',
  );
  print('  ${'─' * 96}');
}

void _bench(String name, void Function() Function() setupFn) {
  final fn = setupFn();

  for (int i = 0; i < _kWarmup; i++) {
    fn();
  }

  final durations = <double>[];
  final sw = Stopwatch();

  for (int s = 0; s < _kSamples; s++) {
    sw
      ..reset()
      ..start();
    for (int i = 0; i < _kIterationsPerSample; i++) {
      fn();
    }
    sw.stop();
    durations.add((sw.elapsedMicroseconds * 1000) / _kIterationsPerSample);
  }

  durations.sort();
  final median = durations[durations.length ~/ 2];
  final mean = durations.reduce((a, b) => a + b) / durations.length;
  final min = durations.first;
  final opsPerSec = (1e9 / median).round();

  print(
    '  ${name.padRight(56)} '
    '${_fmtNs(median).padLeft(8)} '
    '${_fmtNs(mean).padLeft(8)} '
    '${_fmtNs(min).padLeft(8)} '
    '${_fmtOps(opsPerSec).padLeft(12)}',
  );
}

String _fmtNs(double ns) {
  if (ns >= 1e6) return '${(ns / 1e6).toStringAsFixed(1)}ms';
  if (ns >= 1e3) return '${(ns / 1e3).toStringAsFixed(1)}us';
  return '${ns.toStringAsFixed(0)}ns';
}

String _fmtOps(int ops) {
  if (ops >= 1e6) return '${(ops / 1e6).toStringAsFixed(2)}M';
  if (ops >= 1e3) return '${(ops / 1e3).toStringAsFixed(1)}K';
  return '$ops';
}
