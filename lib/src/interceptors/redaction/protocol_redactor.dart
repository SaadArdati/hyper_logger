part of '../redacting_interceptor.dart';

/// Exact parsers for credential-bearing wire formats supported in log text.
final class _ProtocolRedactor {
  const _ProtocolRedactor(this.policy, this.replacement);

  final RedactionPolicy policy;
  final String replacement;

  String redact(String value) {
    var result = _redactHeaderLines(value);
    result = _redactUri(result) ?? result;
    result = _redactForm(result) ?? result;
    if (policy.redactRfc7468Blocks) {
      result = _redactRfc7468Blocks(result);
    }
    return result;
  }

  String _redactHeaderLines(String value) {
    if (!value.contains(':')) return value;
    final lines = value.split('\n');
    var changed = false;
    var outputLength = value.length;
    var previousFieldWasSensitive = false;
    for (var index = 0; index < lines.length; index++) {
      var line = lines[index];
      final hasCarriageReturn = line.endsWith('\r');
      if (hasCarriageReturn) line = line.substring(0, line.length - 1);

      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (previousFieldWasSensitive) {
          var contentStart = 0;
          while (contentStart < line.length &&
              (line.codeUnitAt(contentStart) == 0x20 ||
                  line.codeUnitAt(contentStart) == 0x09)) {
            contentStart++;
          }
          final redactedLine =
              '${line.substring(0, contentStart)}$replacement'
              '${hasCarriageReturn ? '\r' : ''}';
          outputLength += redactedLine.length - lines[index].length;
          if (outputLength > policy.maxStringLength) {
            throw const RedactionException(
              'redacted HTTP fields exceed the configured string limit',
            );
          }
          lines[index] = redactedLine;
          changed = true;
        }
        continue;
      }

      previousFieldWasSensitive = false;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final fieldName = line.substring(0, colon);
      if (!_isHttpToken(fieldName) ||
          !policy.sensitiveHeaderNames.contains(_asciiLowercase(fieldName))) {
        continue;
      }

      previousFieldWasSensitive = true;
      final redactedLine =
          '${line.substring(0, colon + 1)} $replacement'
          '${hasCarriageReturn ? '\r' : ''}';
      outputLength += redactedLine.length - lines[index].length;
      if (outputLength > policy.maxStringLength) {
        throw const RedactionException(
          'redacted HTTP fields exceed the configured string limit',
        );
      }
      lines[index] = redactedLine;
      changed = true;
    }
    return changed ? lines.join('\n') : value;
  }

  String? _redactUri(String value) {
    // Avoid parser allocation for ordinary prose.
    if (!value.contains('?') && !value.contains('@')) return null;

    var leading = 0;
    while (leading < value.length &&
        _isAsciiWhitespace(value.codeUnitAt(leading))) {
      leading++;
    }
    var trailing = value.length;
    while (trailing > leading &&
        _isAsciiWhitespace(value.codeUnitAt(trailing - 1))) {
      trailing--;
    }
    final core = value.substring(leading, trailing);
    final uri = Uri.tryParse(core);
    if (uri == null ||
        (!uri.hasScheme &&
            !uri.hasQuery &&
            !core.startsWith('/') &&
            !core.startsWith('//'))) {
      return null;
    }

    var sanitized = _removeUriUserInfo(core);
    sanitized = _redactParameterComponent(sanitized, isForm: false).value;
    if (sanitized == core) return null;
    if (leading + sanitized.length + value.length - trailing >
        policy.maxStringLength) {
      throw const RedactionException(
        'redacted URI exceeds the configured string limit',
      );
    }
    return '${value.substring(0, leading)}$sanitized${value.substring(trailing)}';
  }

  String? _redactForm(String value) {
    if (!value.contains('=')) return null;
    for (var index = 0; index < value.length; index++) {
      if (_isAsciiWhitespace(value.codeUnitAt(index))) return null;
    }
    final result = _redactParameterComponent(value, isForm: true);
    return result.changed ? result.value : null;
  }

  ({String value, bool changed}) _redactParameterComponent(
    String value, {
    required bool isForm,
  }) {
    final queryStart = isForm ? 0 : value.indexOf('?') + 1;
    if (!isForm && queryStart == 0) return (value: value, changed: false);
    final fragmentStart = isForm ? -1 : value.indexOf('#', queryStart);
    final queryEnd = fragmentStart < 0 ? value.length : fragmentStart;
    final raw = value.substring(queryStart, queryEnd);
    final parts = raw.split('&');
    var changed = false;
    var outputLength = value.length;
    String? encodedReplacement;
    int? encodedReplacementLength;

    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final equals = part.indexOf('=');
      final rawKey = equals < 0 ? part : part.substring(0, equals);
      late final String key;
      try {
        key = isForm
            ? Uri.decodeQueryComponent(rawKey)
            : Uri.decodeComponent(rawKey);
      } on FormatException {
        throw const RedactionException('invalid URI parameter encoding');
      }
      final isSensitive =
          policy.sensitiveQueryParameters.contains(key) ||
          (isForm && policy.sensitiveKeys.contains(key));
      if (!isSensitive) continue;
      encodedReplacementLength ??= _encodedParameterLength(
        replacement,
        isForm: isForm,
      );
      final redactedPartLength = rawKey.length + 1 + encodedReplacementLength;
      final nextOutputLength = outputLength - part.length + redactedPartLength;
      if (nextOutputLength > policy.maxStringLength) {
        throw const RedactionException(
          'redacted parameters exceed the configured string limit',
        );
      }
      encodedReplacement ??= isForm
          ? Uri.encodeQueryComponent(replacement)
          : Uri.encodeComponent(replacement);
      parts[index] = '$rawKey=$encodedReplacement';
      outputLength = nextOutputLength;
      changed = true;
    }

    if (!changed) return (value: value, changed: false);
    final sanitized = parts.join('&');
    return (
      value:
          '${value.substring(0, queryStart)}$sanitized${value.substring(queryEnd)}',
      changed: true,
    );
  }

  String _removeUriUserInfo(String value) {
    final scheme = value.indexOf(':');
    final authorityStart = value.startsWith('//')
        ? 2
        : scheme >= 0 && value.startsWith('//', scheme + 1)
        ? scheme + 3
        : -1;
    if (authorityStart < 0) return value;

    var authorityEnd = value.length;
    for (var index = authorityStart; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit == 0x2f || unit == 0x3f || unit == 0x23) {
        authorityEnd = index;
        break;
      }
    }
    final at = value.lastIndexOf('@', authorityEnd - 1);
    if (at < authorityStart) return value;
    return value.replaceRange(authorityStart, at + 1, '');
  }

  int _encodedParameterLength(String value, {required bool isForm}) {
    var length = 0;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit <= 0x7f) {
        final alphaNumeric =
            (unit >= 0x30 && unit <= 0x39) ||
            (unit >= 0x41 && unit <= 0x5a) ||
            (unit >= 0x61 && unit <= 0x7a);
        final commonUnreserved =
            unit == 0x2d || unit == 0x2e || unit == 0x5f || unit == 0x7e;
        final rfc2396Mark =
            unit == 0x21 ||
            unit == 0x2a ||
            unit == 0x27 ||
            unit == 0x28 ||
            unit == 0x29;
        final remainsLiteral =
            alphaNumeric ||
            commonUnreserved ||
            (!isForm && rfc2396Mark) ||
            (isForm && unit == 0x20);
        length += remainsLiteral ? 1 : 3;
      } else if (unit <= 0x7ff) {
        length += 6;
      } else if (unit >= 0xd800 &&
          unit <= 0xdbff &&
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) >= 0xdc00 &&
          value.codeUnitAt(index + 1) <= 0xdfff) {
        length += 12;
        index++;
      } else {
        length += 9;
      }
      if (length > policy.maxStringLength) {
        throw const RedactionException(
          'encoded replacement exceeds the configured string limit',
        );
      }
    }
    return length;
  }

  String _redactRfc7468Blocks(String value) {
    const beginPrefix = '-----BEGIN ';
    if (!value.contains(beginPrefix)) return value;
    var searchStart = 0;
    final output = StringBuffer();

    void writeSource(int start, int end) {
      if (output.length + end - start > policy.maxStringLength) {
        throw const RedactionException(
          'redacted block output exceeds the configured string limit',
        );
      }
      output.write(value.substring(start, end));
    }

    void writeReplacement() {
      if (output.length + replacement.length > policy.maxStringLength) {
        throw const RedactionException(
          'redacted block output exceeds the configured string limit',
        );
      }
      output.write(replacement);
    }

    while (true) {
      var begin = value.indexOf(beginPrefix, searchStart);
      while (begin >= 0 && !_isLineStart(value, begin)) {
        begin = value.indexOf(beginPrefix, begin + beginPrefix.length);
      }
      if (begin < 0) {
        writeSource(searchStart, value.length);
        return output.toString();
      }
      final labelEnd = value.indexOf('-----', begin + beginPrefix.length);
      if (labelEnd < 0) {
        writeSource(searchStart, value.length);
        return output.toString();
      }
      final label = value.substring(begin + beginPrefix.length, labelEnd);
      if (!_isRfc7468Label(label) || !_isBoundaryLineEnd(value, labelEnd + 5)) {
        writeSource(searchStart, begin + beginPrefix.length);
        searchStart = begin + beginPrefix.length;
        continue;
      }
      final endBoundary = '-----END $label-----';
      var end = value.indexOf(endBoundary, labelEnd + 5);
      while (end >= 0 &&
          (!_isLineStart(value, end) ||
              !_isBoundaryLineEnd(value, end + endBoundary.length))) {
        end = value.indexOf(endBoundary, end + endBoundary.length);
      }
      if (end < 0) {
        writeSource(searchStart, value.length);
        return output.toString();
      }
      writeSource(searchStart, begin);
      writeReplacement();
      searchStart = end + endBoundary.length;
    }
  }
}

bool _isAsciiWhitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

bool _canStartJson(int unit) =>
    unit == 0x7b || // {
    unit == 0x5b || // [
    unit == 0x22 || // "
    unit == 0x2d || // -
    (unit >= 0x30 && unit <= 0x39) || // 0-9
    unit == 0x74 || // true
    unit == 0x66 || // false
    unit == 0x6e; // null

bool _isLineStart(String value, int index) =>
    index == 0 ||
    value.codeUnitAt(index - 1) == 0x0a ||
    value.codeUnitAt(index - 1) == 0x0d;

bool _isBoundaryLineEnd(String value, int index) {
  while (index < value.length) {
    final unit = value.codeUnitAt(index);
    if (unit != 0x20 && unit != 0x09) break;
    index++;
  }
  return index == value.length ||
      value.codeUnitAt(index) == 0x0d ||
      value.codeUnitAt(index) == 0x0a;
}

bool _isRfc7468Label(String value) {
  if (value.isEmpty) return true;
  var previousWasSeparator = true;
  for (final unit in value.codeUnits) {
    final isLabelCharacter =
        (unit >= 0x21 && unit <= 0x2c) || (unit >= 0x2e && unit <= 0x7e);
    if (isLabelCharacter) {
      previousWasSeparator = false;
      continue;
    }
    final isSeparator = unit == 0x20 || unit == 0x2d;
    if (!isSeparator || previousWasSeparator) return false;
    previousWasSeparator = true;
  }
  return !previousWasSeparator;
}
