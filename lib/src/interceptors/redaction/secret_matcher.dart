part of '../redacting_interceptor.dart';

/// Reverse Aho-Corasick matcher preserving leftmost-longest replacement.
final class _SecretMatcher {
  _SecretMatcher(Iterable<String> secrets) {
    for (final secret in secrets) {
      _isEmpty = false;
      var node = _root;
      for (var index = secret.length - 1; index >= 0; index--) {
        final unit = secret.codeUnitAt(index);
        node = node.children.putIfAbsent(unit, _SecretNode.new);
      }
      node.matchLength = secret.length;
    }
    _buildFailureLinks();
  }

  final _SecretNode _root = _SecretNode();
  var _isEmpty = true;

  bool get isEmpty => _isEmpty;

  void _buildFailureLinks() {
    _root.failure = _root;
    final queue = ListQueue<_SecretNode>();
    for (final child in _root.children.values) {
      child
        ..failure = _root
        ..longestOutputLength = child.matchLength;
      queue.add(child);
    }

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      for (final edge in node.children.entries) {
        final unit = edge.key;
        final child = edge.value;
        var fallback = node.failure!;
        while (!identical(fallback, _root) &&
            !fallback.children.containsKey(unit)) {
          fallback = fallback.failure!;
        }
        child.failure = fallback.children[unit] ?? _root;
        final inheritedLength = child.failure!.longestOutputLength;
        child.longestOutputLength = child.matchLength > inheritedLength
            ? child.matchLength
            : inheritedLength;
        queue.add(child);
      }
    }
  }

  _SecretNode _advance(_SecretNode state, int unit) {
    var current = state;
    var next = current.children[unit];
    while (next == null && !identical(current, _root)) {
      current = current.failure!;
      next = current.children[unit];
    }
    return next ?? _root;
  }

  bool containsMatch(String value) {
    if (_isEmpty || value.isEmpty) return false;
    var state = _root;
    for (var index = value.length - 1; index >= 0; index--) {
      state = _advance(state, value.codeUnitAt(index));
      if (state.longestOutputLength > 0) return true;
    }
    return false;
  }

  String replaceAll(String value, String replacement, int maxOutputLength) {
    Uint32List? matchLengths;
    var state = _root;
    for (
      var reverseIndex = value.length - 1;
      reverseIndex >= 0;
      reverseIndex--
    ) {
      state = _advance(state, value.codeUnitAt(reverseIndex));
      final matchLength = state.longestOutputLength;
      if (matchLength > 0) {
        (matchLengths ??= Uint32List(value.length))[reverseIndex] = matchLength;
      }
    }
    if (matchLengths == null) return value;

    var outputLength = 0;
    var index = 0;
    while (index < value.length) {
      final matchLength = matchLengths[index];
      if (matchLength == 0) {
        outputLength++;
        index++;
      } else {
        outputLength += replacement.length;
        index += matchLength;
      }
      if (outputLength > maxOutputLength) {
        throw const RedactionException(
          'redaction output exceeds the configured string limit',
        );
      }
    }

    final output = StringBuffer();
    var unchangedStart = 0;
    index = 0;
    while (index < value.length) {
      final matchLength = matchLengths[index];
      if (matchLength == 0) {
        index++;
        continue;
      }
      output
        ..write(value.substring(unchangedStart, index))
        ..write(replacement);
      index += matchLength;
      unchangedStart = index;
    }
    output.write(value.substring(unchangedStart));
    return output.toString();
  }
}

final class _SecretNode {
  final Map<int, _SecretNode> children = {};
  _SecretNode? failure;
  int matchLength = 0;
  int longestOutputLength = 0;
}
