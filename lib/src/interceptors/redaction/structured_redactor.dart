part of '../redacting_interceptor.dart';

/// Bounded, cycle-aware traversal of supported structured log values.
final class _StructuredRedactor {
  _StructuredRedactor(this.policy, this.replacement, this._text);

  final RedactionPolicy policy;
  final String replacement;
  final _TextRedactor _text;

  LogEntry? redactEntry(LogEntry entry) {
    try {
      final state = _TraversalState(policy);
      final message = _redactEntryText(entry.message, state);
      final object = switch (entry.object) {
        final LogMessage value => _redactLogMessage(value, message, state),
        final Object value => _redactValue(value, const [], const [], state, 1),
        null => null,
      };

      return entry.copyWith(
        message: message,
        object: () => object,
        loggerName: _redactEntryText(entry.loggerName, state),
        error: () => entry.error == null
            ? null
            : _redactValue(entry.error, const [], const [], state, 1),
        stackTrace: () => entry.stackTrace == null
            ? null
            : StackTrace.fromString(
                _redactEntryText(entry.stackTrace.toString(), state),
              ),
        tag: () =>
            entry.tag == null ? null : _redactEntryText(entry.tag!, state),
      );
    } catch (_) {
      return null;
    }
  }

  Object? redactObject(Object? value, {String? key}) {
    final path = key == null ? const <String>[] : <String>[key];
    return _redactValue(value, path, path, _TraversalState(policy), 0);
  }

  String redactText(String value) => _text.redact(
    value,
    _TraversalState(policy),
    const [],
    const [],
    0,
    _redactValue,
  );

  LogMessage _redactLogMessage(
    LogMessage message,
    String canonicalMessage,
    _TraversalState state,
  ) {
    state.visit(1);
    return message.copyWith(
      message: canonicalMessage,
      type: _redactType(message.type, state, 2),
      data: () => _redactValue(message.data, const [], const [], state, 2),
      method: () => message.method == null
          ? null
          : _redactEntryText(message.method!, state, 2),
      callerStackTrace: () => message.callerStackTrace == null
          ? null
          : StackTrace.fromString(
              _redactEntryText(message.callerStackTrace.toString(), state, 2),
            ),
      context: () => message.context == null
          ? null
          : _redactValue(message.context!, const [], const [], state, 2)
                as Map<String, Object?>,
      scopeTag: () => message.scopeTag == null
          ? null
          : _redactEntryText(message.scopeTag!, state, 2),
    );
  }

  Type _redactType(Type value, _TraversalState state, int depth) {
    final rendered = value.toString();
    final safe = _redactEntryText(rendered, state, depth);
    if (safe == rendered) return value;

    const placeholder = Object;
    final placeholderName = placeholder.toString();
    if (_redactEntryText(placeholderName, state, depth) != placeholderName) {
      throw const RedactionException(
        'safe LogMessage.type placeholder is also sensitive',
      );
    }
    return placeholder;
  }

  String _redactEntryText(
    String value,
    _TraversalState state, [
    int depth = 0,
  ]) {
    state.visit(depth);
    return _text.redact(value, state, const [], const [], depth, _redactValue);
  }

  Object? _redactValue(
    Object? value,
    List<String> originalPath,
    List<String> finalPath,
    _TraversalState state,
    int depth,
  ) {
    state.visit(depth);
    final originalIsSensitive =
        originalPath.isNotEmpty &&
        (policy.isSensitiveKey(originalPath.last) ||
            policy.isSensitivePath(originalPath));
    if (originalIsSensitive ||
        (!identical(finalPath, originalPath) &&
            finalPath.isNotEmpty &&
            (policy.isSensitiveKey(finalPath.last) ||
                policy.isSensitivePath(finalPath)))) {
      return replacement;
    }

    return switch (value) {
      null => null,
      final num value => _redactScalar(value, value.toString()),
      final bool value => _redactScalar(value, value.toString()),
      final String value => _text.redact(
        value,
        state,
        originalPath,
        finalPath,
        depth,
        _redactValue,
      ),
      final Uri value => _text.redact(
        value.toString(),
        state,
        originalPath,
        finalPath,
        depth,
        _redactValue,
      ),
      final DateTime value => _redactScalar(value, value.toString()),
      final Duration value => _redactScalar(value, value.toString()),
      final StackTrace value => StackTrace.fromString(
        _text.redact(
          value.toString(),
          state,
          originalPath,
          finalPath,
          depth,
          _redactValue,
        ),
      ),
      final BigInt value => _redactScalar(value, value.toString()),
      final Enum value => _redactEnum(value),
      final TypedData _ => replacement,
      final Map<Object?, Object?> value => _redactMap(
        value,
        originalPath,
        finalPath,
        state,
        depth,
      ),
      final List<Object?> value => _redactList(
        value,
        originalPath,
        finalPath,
        state,
        depth,
      ),
      final Set<Object?> value => _redactSet(
        value,
        originalPath,
        finalPath,
        state,
        depth,
      ),
      final Object value => _redactUnknown(
        value,
        originalPath,
        finalPath,
        state,
        depth,
      ),
    };
  }

  Object _redactScalar(Object value, String rendered) {
    _text.checkStringLength(rendered);
    final safe = _text.replaceLiteralSecrets(rendered);
    return safe == rendered ? value : replacement;
  }

  String _redactEnum(Enum value) {
    final rendered = value.name;
    _text.checkStringLength(rendered);
    return _text.replaceLiteralSecrets(rendered);
  }

  Map<String, Object?> _redactMap(
    Map<Object?, Object?> value,
    List<String> originalPath,
    List<String> finalPath,
    _TraversalState state,
    int depth,
  ) {
    state.enter(value, depth, value.length);
    try {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final rawKey = entry.key;
        if (rawKey is! String) {
          throw const RedactionException(
            'structured maps must use string keys',
          );
        }
        final safeKey = _text.redactKey(
          rawKey,
          state,
          originalPath,
          finalPath,
          depth,
          _redactValue,
        );
        if (result.containsKey(safeKey)) {
          throw const RedactionException(
            'redaction produced duplicate structured keys',
          );
        }
        final originalChildPath = <String>[...originalPath, rawKey];
        final finalChildPath =
            identical(finalPath, originalPath) && safeKey == rawKey
            ? originalChildPath
            : <String>[...finalPath, safeKey];
        result[safeKey] = _redactValue(
          entry.value,
          originalChildPath,
          finalChildPath,
          state,
          depth + 1,
        );
      }
      return result;
    } finally {
      state.leave(value);
    }
  }

  List<Object?> _redactList(
    List<Object?> value,
    List<String> originalPath,
    List<String> finalPath,
    _TraversalState state,
    int depth,
  ) {
    state.enter(value, depth, value.length);
    try {
      return <Object?>[
        for (var index = 0; index < value.length; index++)
          _redactIndexedValue(
            value[index],
            originalPath,
            finalPath,
            index,
            state,
            depth + 1,
          ),
      ];
    } finally {
      state.leave(value);
    }
  }

  List<Object?> _redactSet(
    Set<Object?> value,
    List<String> originalPath,
    List<String> finalPath,
    _TraversalState state,
    int depth,
  ) {
    state.enter(value, depth, value.length);
    try {
      final result = <Object?>[];
      var index = 0;
      for (final item in value) {
        result.add(
          _redactIndexedValue(
            item,
            originalPath,
            finalPath,
            index++,
            state,
            depth + 1,
          ),
        );
      }
      return result;
    } finally {
      state.leave(value);
    }
  }

  Object? _redactIndexedValue(
    Object? value,
    List<String> originalPath,
    List<String> finalPath,
    int index,
    _TraversalState state,
    int depth,
  ) {
    final segment = '$index';
    final originalChildPath = <String>[...originalPath, segment];
    final finalChildPath = identical(finalPath, originalPath)
        ? originalChildPath
        : <String>[...finalPath, segment];
    return _redactValue(value, originalChildPath, finalChildPath, state, depth);
  }

  Object? _redactUnknown(
    Object value,
    List<String> originalPath,
    List<String> finalPath,
    _TraversalState state,
    int depth,
  ) {
    final encoder = policy.objectEncoder;
    if (encoder != null) {
      state.enter(value, depth, 0);
      try {
        return _redactValue(
          encoder(value),
          originalPath,
          finalPath,
          state,
          depth + 1,
        );
      } finally {
        state.leave(value);
      }
    }

    return switch (policy.unknownValueHandling) {
      UnknownValueHandling.redact => replacement,
      UnknownValueHandling.dropEntry => throw const RedactionException(
        'encountered an unsupported structured value',
      ),
      UnknownValueHandling.stringify => _text.redact(
        value.toString(),
        state,
        originalPath,
        finalPath,
        depth,
        _redactValue,
      ),
    };
  }
}

final class _TraversalState {
  _TraversalState(this.policy);

  final RedactionPolicy policy;
  final Set<Object> _active = HashSet<Object>.identity();
  int _nodes = 0;

  void visit(int depth) {
    if (depth > policy.maxDepth) {
      throw const RedactionException('maximum redaction depth exceeded');
    }
    if (++_nodes > policy.maxNodes) {
      throw const RedactionException('maximum redaction node count exceeded');
    }
  }

  void enter(Object value, int depth, int length) {
    if (depth > policy.maxDepth) {
      throw const RedactionException('maximum redaction depth exceeded');
    }
    if (length > policy.maxCollectionLength) {
      throw const RedactionException('collection exceeds the configured limit');
    }
    if (!_active.add(value)) {
      throw const RedactionException('cyclic structured data detected');
    }
  }

  void leave(Object value) => _active.remove(value);
}
