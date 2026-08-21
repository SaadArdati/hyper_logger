import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../model/log_entry.dart';
import '../model/log_message.dart';

part 'redaction/protocol_redactor.dart';
part 'redaction/redaction_policy.dart';
part 'redaction/secret_matcher.dart';
part 'redaction/structured_redactor.dart';
part 'redaction/text_redactor.dart';

/// Sanitizes a [LogEntry] using exact schema and protocol rules.
///
/// The default policy provides exact structured key/path matching, HTTP field
/// redaction, URI/form parameter redaction, JSON decoding, RFC 7468 block
/// removal, bounded cycle-aware traversal, and explicitly configured literal
/// secret matching.
///
/// Use this as `HyperLogger.init(sanitizers: [redactor.call])`. Sanitizers run
/// after ordinary interceptors and before every output sink.
///
/// The supported formats and defaults are based on:
///
/// - the [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
///   for removing, masking, or sanitizing credentials before recording them;
/// - [RFC 9110 sections 5.1 and 11.4](https://www.rfc-editor.org/rfc/rfc9110.html)
///   for HTTP field names and credential-bearing authorization fields;
/// - [RFC 9112 section 5.2](https://www.rfc-editor.org/rfc/rfc9112.html#section-5.2)
///   for defensive handling of obsolete HTTP/1.1 field folding;
/// - [RFC 3986 section 3.2.1](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.2.1)
///   for URI user information;
/// - [RFC 6750 section 2](https://www.rfc-editor.org/rfc/rfc6750.html#section-2)
///   for OAuth bearer tokens in headers, form bodies, and query strings;
/// - [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html) for JSON syntax,
///   duplicate-name interoperability, and parser resource limits;
/// - [RFC 7468 sections 2-3](https://www.rfc-editor.org/rfc/rfc7468.html)
///   for textual key and certificate boundaries;
/// - the OpenTelemetry [URL semantic conventions](https://opentelemetry.io/docs/specs/semconv/url/)
///   and [URL attribute registry](https://opentelemetry.io/docs/specs/semconv/registry/attributes/url/)
///   for user-info removal and default sensitive query names.
///
/// This is a conservative log sanitizer, not a protocol validator or a claim
/// of regulatory compliance. Extend [RedactionPolicy] with the exact schema
/// names used by the application, and configure [secrets] for opaque values
/// that can appear in prose.
final class RedactingInterceptor {
  /// Creates an exact, bounded redactor.
  ///
  /// [secrets] are matched as complete, case-sensitive literal values with a
  /// linear-time multi-pattern matcher. Empty and duplicate values are
  /// ignored. [replacement] must fit [RedactionPolicy.maxStringLength] and
  /// must not itself contain a configured secret.
  ///
  /// Construction throws [ArgumentError] rather than silently omitting a
  /// secret when matcher or string limits are exceeded. Error messages never
  /// render the confidential values.
  factory RedactingInterceptor({
    Iterable<String> secrets = const [],
    String replacement = defaultReplacement,
    RedactionPolicy? policy,
  }) {
    final effectivePolicy = policy ?? RedactionPolicy();
    if (replacement.length > effectivePolicy.maxStringLength) {
      throw ArgumentError('replacement must not exceed policy.maxStringLength');
    }

    final uniqueSecrets = <String>{};
    var totalSecretLength = 0;
    for (final secret in secrets) {
      if (secret.isEmpty || !uniqueSecrets.add(secret)) continue;
      if (secret.length > effectivePolicy.maxStringLength) {
        throw ArgumentError(
          'a configured secret exceeds policy.maxStringLength',
        );
      }
      totalSecretLength += secret.length;
      if (uniqueSecrets.length > effectivePolicy.maxSecretCount) {
        throw ArgumentError.value(
          uniqueSecrets.length,
          'secrets',
          'distinct secret count exceeds policy.maxSecretCount',
        );
      }
      if (totalSecretLength > effectivePolicy.maxTotalSecretLength) {
        throw ArgumentError.value(
          totalSecretLength,
          'secrets',
          'aggregate secret length exceeds policy.maxTotalSecretLength',
        );
      }
    }
    final matcher = _SecretMatcher(uniqueSecrets);
    if (!matcher.isEmpty && matcher.containsMatch(replacement)) {
      throw ArgumentError('replacement must not contain a configured secret');
    }
    return RedactingInterceptor._(
      replacement,
      effectivePolicy,
      _TextRedactor(effectivePolicy, replacement, matcher),
    );
  }

  /// Collects values from explicitly named environment entries.
  ///
  /// Environment names are exact and case-sensitive. A complete selected
  /// value is protected, and policy-selected strings inside valid JSON are
  /// added as component secrets. Inspection is bounded by [policy]; JSON with
  /// duplicate decoded names is rejected because [RFC 8259 section 4](https://www.rfc-editor.org/rfc/rfc8259.html#section-4)
  /// documents non-interoperable receiver behavior for duplicate names.
  ///
  /// The package does not read process state implicitly. Callers decide which
  /// environment snapshot and exact [environmentKeys] are in scope.
  factory RedactingInterceptor.fromEnvironment(
    Map<String, String> environment, {
    required Iterable<String> environmentKeys,
    Iterable<String> additionalSecrets = const [],
    String replacement = defaultReplacement,
    RedactionPolicy? policy,
  }) {
    final effectivePolicy = policy ?? RedactionPolicy();
    final secrets = _environmentSecrets(
      environment,
      environmentKeys,
      additionalSecrets,
      effectivePolicy,
    );
    return RedactingInterceptor(
      secrets: secrets,
      replacement: replacement,
      policy: effectivePolicy,
    );
  }

  RedactingInterceptor._(this.replacement, this.policy, _TextRedactor text)
    : _structured = _StructuredRedactor(policy, replacement, text);

  /// The default marker used for removed content.
  static const String defaultReplacement = '[redacted]';

  /// The marker used for removed content.
  final String replacement;

  /// Exact policy and resource limits used by this interceptor.
  final RedactionPolicy policy;

  final _StructuredRedactor _structured;

  /// Sanitizes [entry], or drops it when the complete policy cannot finish.
  ///
  /// Every supported entry field is traversed. Any exception, cycle, resource
  /// limit, unsafe replacement composition, or configured drop condition
  /// returns `null`, making this method suitable for [LogSanitizer].
  LogEntry? call(LogEntry entry) => _structured.redactEntry(entry);

  /// Sanitizes a standalone structured value.
  ///
  /// Throws [RedactionException] when configured limits are exceeded, a cycle
  /// is found, a safe fixed point cannot be reached, or
  /// [UnknownValueHandling.dropEntry] applies.
  Object? redactObject(Object? value, {String? key}) =>
      _structured.redactObject(value, key: key);

  /// Sanitizes a standalone string using exact supported representations and
  /// known literal secret values.
  ///
  /// A changed candidate is re-inspected so a replacement cannot synthesize a
  /// new supported representation after its parser has already run. Throws
  /// [RedactionException] when limits or the bounded fixed-point requirement
  /// cannot be satisfied.
  String redactText(String value) => _structured.redactText(value);
}

Set<String> _environmentSecrets(
  Map<String, String> environment,
  Iterable<String> environmentKeys,
  Iterable<String> additionalSecrets,
  RedactionPolicy policy,
) {
  final secrets = <String>{};
  var totalLength = 0;

  void add(String secret) {
    if (secret.isEmpty || secrets.contains(secret)) return;
    if (secret.length > policy.maxStringLength) {
      throw ArgumentError(
        'an environment secret exceeds policy.maxStringLength',
      );
    }
    if (secrets.length >= policy.maxSecretCount) {
      throw ArgumentError.value(
        secrets.length + 1,
        'environment secrets',
        'distinct secret count exceeds policy.maxSecretCount',
      );
    }
    if (totalLength + secret.length > policy.maxTotalSecretLength) {
      throw ArgumentError.value(
        totalLength + secret.length,
        'environment secrets',
        'aggregate secret length exceeds policy.maxTotalSecretLength',
      );
    }
    secrets.add(secret);
    totalLength += secret.length;
  }

  for (final secret in additionalSecrets) {
    add(secret);
  }
  for (final key in environmentKeys) {
    final value = environment[key];
    if (value == null || value.isEmpty) continue;
    if (value.length > policy.maxStringLength) {
      throw const RedactionException(
        'a selected environment value exceeds the configured string limit',
      );
    }
    add(value);
    _collectSelectedJsonStrings(value, policy, add);
  }
  return secrets;
}

void _collectSelectedJsonStrings(
  String raw,
  RedactionPolicy policy,
  void Function(String value) addSecret,
) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return;
  }
  _rejectDuplicateJsonKeys(raw, policy.maxDepth);
  _collectJsonValue(
    decoded,
    policy,
    addSecret,
    const [],
    false,
    _TraversalState(policy),
    0,
  );
}

void _collectJsonValue(
  Object? value,
  RedactionPolicy policy,
  void Function(String value) addSecret,
  List<String> path,
  bool selected,
  _TraversalState state,
  int depth,
) {
  state.visit(depth);
  switch (value) {
    case final String value when selected && value.isNotEmpty:
      addSecret(value);
    case final Map<Object?, Object?> value:
      state.enter(value, depth, value.length);
      try {
        for (final entry in value.entries) {
          final key = entry.key;
          if (key is! String) continue;
          if (key.length > policy.maxStringLength) {
            throw const RedactionException(
              'environment JSON key exceeds the configured limit',
            );
          }
          final childPath = <String>[...path, key];
          _collectJsonValue(
            entry.value,
            policy,
            addSecret,
            childPath,
            selected ||
                policy.isSensitiveKey(key) ||
                policy.isSensitivePath(childPath),
            state,
            depth + 1,
          );
        }
      } finally {
        state.leave(value);
      }
    case final List<Object?> value:
      state.enter(value, depth, value.length);
      try {
        for (var index = 0; index < value.length; index++) {
          _collectJsonValue(
            value[index],
            policy,
            addSecret,
            <String>[...path, '$index'],
            selected,
            state,
            depth + 1,
          );
        }
      } finally {
        state.leave(value);
      }
    case _:
      return;
  }
}
