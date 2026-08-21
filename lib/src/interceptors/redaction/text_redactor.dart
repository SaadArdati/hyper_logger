part of '../redacting_interceptor.dart';

typedef _StructuredValueRedactor =
    Object? Function(
      Object? value,
      List<String> originalPath,
      List<String> finalPath,
      _TraversalState state,
      int depth,
    );

/// Coordinates JSON decoding, protocol parsers, and literal secret matching.
final class _TextRedactor {
  _TextRedactor(this.policy, this.replacement, this._secretMatcher)
    : _protocols = _ProtocolRedactor(policy, replacement);

  final RedactionPolicy policy;
  final String replacement;
  final _SecretMatcher _secretMatcher;
  final _ProtocolRedactor _protocols;

  String redact(
    String value,
    _TraversalState state,
    List<String> originalPath,
    List<String> finalPath,
    int depth,
    _StructuredValueRedactor redactStructuredValue,
  ) {
    checkStringLength(value);

    final json = _tryRedactJson(
      value,
      state,
      originalPath,
      finalPath,
      depth,
      redactStructuredValue,
    );
    if (json != null) {
      return _finalizeJson(json);
    }

    return _redactComposedText(
      value,
      state,
      originalPath,
      finalPath,
      depth,
      redactStructuredValue,
    );
  }

  String redactKey(
    String value,
    _TraversalState state,
    List<String> originalPath,
    List<String> finalPath,
    int depth,
    _StructuredValueRedactor redactStructuredValue,
  ) {
    checkStringLength(value);
    var firstContent = -1;
    var mayContainBlock = false;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (firstContent < 0 && !_isAsciiWhitespace(unit)) firstContent = index;
      if (unit == 0x3a || unit == 0x3f || unit == 0x40 || unit == 0x3d) {
        return redact(
          value,
          state,
          originalPath,
          finalPath,
          depth,
          redactStructuredValue,
        );
      }
      if (unit == 0x2d) mayContainBlock = true;
    }
    final firstUnit = firstContent < 0 ? -1 : value.codeUnitAt(firstContent);
    if (firstUnit == 0x7b ||
        firstUnit == 0x5b ||
        firstUnit == 0x22 ||
        (mayContainBlock && value.contains('-----BEGIN '))) {
      return redact(
        value,
        state,
        originalPath,
        finalPath,
        depth,
        redactStructuredValue,
      );
    }
    final redacted = replaceLiteralSecrets(value);
    return redacted == value
        ? value
        : redact(
            redacted,
            state,
            originalPath,
            finalPath,
            depth,
            redactStructuredValue,
          );
  }

  String? _tryRedactJson(
    String value,
    _TraversalState state,
    List<String> originalPath,
    List<String> finalPath,
    int depth,
    _StructuredValueRedactor redactStructuredValue,
  ) {
    var firstContent = 0;
    while (firstContent < value.length &&
        _isAsciiWhitespace(value.codeUnitAt(firstContent))) {
      firstContent++;
    }
    if (firstContent == value.length ||
        !_canStartJson(value.codeUnitAt(firstContent))) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      final redacted = redactStructuredValue(
        decoded,
        originalPath,
        finalPath,
        state,
        depth + 1,
      );
      if (decoded is! List && decoded is! Map && redacted == decoded) {
        return value;
      }
      _checkJsonEncodedLength(redacted);
      return jsonEncode(redacted);
    } on FormatException {
      return null;
    }
  }

  String replaceLiteralSecrets(String value) {
    checkStringLength(value);
    if (_secretMatcher.isEmpty || value.isEmpty) return value;
    final redacted = _secretMatcher.replaceAll(
      value,
      replacement,
      policy.maxStringLength,
    );
    if (identical(redacted, value)) return value;
    // Replacement text and surviving neighbors can otherwise synthesize a
    // configured secret across their new boundary. Redact the complete field
    // rather than iterating, which could fail to converge.
    return _secretMatcher.containsMatch(redacted) ? replacement : redacted;
  }

  String _redactComposedText(
    String value,
    _TraversalState state,
    List<String> originalPath,
    List<String> finalPath,
    int depth,
    _StructuredValueRedactor redactStructuredValue,
  ) {
    var current = value;
    for (var pass = 0; pass < 4; pass++) {
      final next = replaceLiteralSecrets(_protocols.redact(current));
      if (next == current) return next;
      final json = _tryRedactJson(
        next,
        state,
        originalPath,
        finalPath,
        depth,
        redactStructuredValue,
      );
      if (json != null) return _finalizeJson(json);
      current = next;
    }
    throw const RedactionException(
      'redaction rules did not reach a safe fixed point',
    );
  }

  String _finalizeJson(String json) {
    if (_secretMatcher.isEmpty || !_secretMatcher.containsMatch(json)) {
      return json;
    }
    // Never splice a literal replacement into JSON grammar.
    _checkJsonEncodedLength(replacement);
    final encodedReplacement = jsonEncode(replacement);
    if (_secretMatcher.containsMatch(encodedReplacement)) {
      throw const RedactionException(
        'no valid JSON replacement can satisfy the literal policy',
      );
    }
    return encodedReplacement;
  }

  void checkStringLength(String value) {
    if (value.length > policy.maxStringLength) {
      throw const RedactionException('string exceeds the configured limit');
    }
  }

  void _checkJsonEncodedLength(Object? value) {
    var length = 0;

    void add(int amount) {
      length += amount;
      if (length > policy.maxStringLength) {
        throw const RedactionException(
          'redacted JSON exceeds the configured string limit',
        );
      }
    }

    void visit(Object? current) {
      switch (current) {
        case null:
          add(4);
        case final bool value:
          add(value ? 4 : 5);
        case final num value:
          add(value.toString().length);
        case final String value:
          add(2);
          for (var index = 0; index < value.length; index++) {
            final unit = value.codeUnitAt(index);
            final isLeadSurrogate = unit >= 0xd800 && unit <= 0xdbff;
            final isTrailSurrogate = unit >= 0xdc00 && unit <= 0xdfff;
            final isPaired =
                (isLeadSurrogate &&
                    index + 1 < value.length &&
                    value.codeUnitAt(index + 1) >= 0xdc00 &&
                    value.codeUnitAt(index + 1) <= 0xdfff) ||
                (isTrailSurrogate &&
                    index > 0 &&
                    value.codeUnitAt(index - 1) >= 0xd800 &&
                    value.codeUnitAt(index - 1) <= 0xdbff);
            if ((isLeadSurrogate || isTrailSurrogate) && !isPaired) {
              add(6);
            } else if (unit == 0x22 || unit == 0x5c) {
              add(2);
            } else if (unit == 0x08 ||
                unit == 0x09 ||
                unit == 0x0a ||
                unit == 0x0c ||
                unit == 0x0d) {
              add(2);
            } else {
              add(unit <= 0x1f ? 6 : 1);
            }
          }
        case final List<Object?> value:
          add(2);
          for (var index = 0; index < value.length; index++) {
            if (index > 0) add(1);
            visit(value[index]);
          }
        case final Map<Object?, Object?> value:
          add(2);
          var index = 0;
          for (final entry in value.entries) {
            if (index++ > 0) add(1);
            visit(entry.key);
            add(1);
            visit(entry.value);
          }
        case _:
          throw const RedactionException(
            'redacted JSON contains an unsupported value',
          );
      }
    }

    visit(value);
  }
}

void _rejectDuplicateJsonKeys(String source, int maxDepth) =>
    _JsonKeyScanner(source, maxDepth).scan();

/// Finds ambiguous duplicate object members after [jsonDecode] validates input.
final class _JsonKeyScanner {
  _JsonKeyScanner(this.source, this.maxDepth);

  final String source;
  final int maxDepth;
  var _index = 0;

  void scan() => _scanValue(0);

  void _scanValue(int depth) {
    if (depth > maxDepth) {
      throw const RedactionException('maximum redaction depth exceeded');
    }
    _skipWhitespace();
    switch (source.codeUnitAt(_index)) {
      case 0x7b: // {
        _scanObject(depth);
      case 0x5b: // [
        _scanArray(depth);
      case 0x22: // "
        _scanString();
      default:
        while (_index < source.length) {
          final unit = source.codeUnitAt(_index);
          if (_isAsciiWhitespace(unit) ||
              unit == 0x2c ||
              unit == 0x5d ||
              unit == 0x7d) {
            return;
          }
          _index++;
        }
    }
  }

  void _scanObject(int depth) {
    _index++;
    _skipWhitespace();
    if (source.codeUnitAt(_index) == 0x7d) {
      _index++;
      return;
    }
    final keys = <String>{};
    while (true) {
      final start = _index;
      _scanString();
      final key = jsonDecode(source.substring(start, _index))! as String;
      if (!keys.add(key)) {
        throw const RedactionException('duplicate environment JSON key');
      }
      _skipWhitespace();
      _index++; // colon; input was already validated by jsonDecode.
      _scanValue(depth + 1);
      _skipWhitespace();
      if (source.codeUnitAt(_index) == 0x7d) {
        _index++;
        return;
      }
      _index++; // comma
      _skipWhitespace();
    }
  }

  void _scanArray(int depth) {
    _index++;
    _skipWhitespace();
    if (source.codeUnitAt(_index) == 0x5d) {
      _index++;
      return;
    }
    while (true) {
      _scanValue(depth + 1);
      _skipWhitespace();
      if (source.codeUnitAt(_index) == 0x5d) {
        _index++;
        return;
      }
      _index++; // comma
      _skipWhitespace();
    }
  }

  void _scanString() {
    _index++;
    while (true) {
      final unit = source.codeUnitAt(_index++);
      if (unit == 0x5c) {
        _index++;
      } else if (unit == 0x22) {
        return;
      }
    }
  }

  void _skipWhitespace() {
    while (_index < source.length &&
        _isAsciiWhitespace(source.codeUnitAt(_index))) {
      _index++;
    }
  }
}
