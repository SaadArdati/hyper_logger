part of '../redacting_interceptor.dart';

/// How values outside the supported structured-log data model are handled.
enum UnknownValueHandling {
  /// Replace the unsupported value without invoking its `toString()` method.
  redact,

  /// Drop the complete log entry.
  dropEntry,

  /// Render and sanitize the value. This is an explicit best-effort opt-in.
  ///
  /// Only use this when the object's `toString()` contract is trusted not to
  /// throw, mutate state, or disclose data outside the configured policy.
  stringify,
}

/// Converts an application object into supported structured-log data.
///
/// The returned value is traversed using the same limits and policy as every
/// other value. Returning the input object, producing a cycle, or throwing
/// causes the entry to be dropped.
typedef RedactionObjectEncoder = Object? Function(Object value);

/// An exact structured-data path.
///
/// Every segment is compared case-sensitively. A `*` segment matches exactly
/// one map key or list index. There is deliberately no string path parser, so
/// dots, brackets, and other characters in real keys remain unambiguous.
/// Each structured surface (`LogMessage.data`, context, error, or a standalone
/// object) has its own root; transport wrapper names are not path segments.
/// This decoded-name comparison also handles equivalent JSON escapes as
/// described by [RFC 8259 section 8.3](https://www.rfc-editor.org/rfc/rfc8259.html#section-8.3).
final class RedactionPath {
  /// Creates a non-empty exact path from [segments].
  ///
  /// Empty paths and empty segments throw [ArgumentError]. Use [wildcard] for
  /// a deliberate single-segment wildcard.
  factory RedactionPath(Iterable<String> segments) {
    final copy = List<String>.unmodifiable(segments);
    if (copy.isEmpty) {
      throw ArgumentError.value(segments, 'segments', 'must not be empty');
    }
    if (copy.any((segment) => segment.isEmpty)) {
      throw ArgumentError.value(
        segments,
        'segments',
        'must not contain empty segments',
      );
    }
    return RedactionPath._(copy);
  }

  const RedactionPath._(this.segments);

  /// Matches exactly one map key, list index, or set index.
  static const String wildcard = '*';

  /// The immutable, case-sensitive path segments.
  final List<String> segments;

  /// Whether this path matches the complete decoded [path].
  bool matches(List<String> path) {
    if (segments.length != path.length) return false;
    for (var index = 0; index < segments.length; index++) {
      final expected = segments[index];
      if (expected != wildcard && expected != path[index]) return false;
    }
    return true;
  }
}

/// Exact redaction rules and traversal limits.
///
/// Generic structured keys and paths are case-sensitive. HTTP header names
/// are ASCII case-insensitive as required by [RFC 9110 section 5.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.1).
/// URI and form parameter names are matched case-sensitively; the defaults
/// combine [RFC 6750 section 2](https://www.rfc-editor.org/rfc/rfc6750.html#section-2)
/// with OpenTelemetry's [URL sanitization profile](https://opentelemetry.io/docs/specs/semconv/registry/attributes/url/).
/// Resource limits follow the allowance in [RFC 8259 section 9](https://www.rfc-editor.org/rfc/rfc8259.html#section-9)
/// for parsers to bound text size, nesting, numbers, and string content.
final class RedactionPolicy {
  /// Creates an immutable policy from exact names, paths, and hard limits.
  ///
  /// HTTP names are normalized to ASCII lowercase once during construction.
  /// Other names remain case-sensitive. Invalid names or non-positive limits
  /// throw [ArgumentError].
  factory RedactionPolicy({
    Iterable<String> sensitiveKeys = defaultSensitiveKeys,
    Iterable<RedactionPath> sensitivePaths = const [],
    Iterable<String> sensitiveHeaderNames = defaultSensitiveHeaderNames,
    Iterable<String> sensitiveQueryParameters = defaultSensitiveQueryParameters,
    UnknownValueHandling unknownValueHandling = UnknownValueHandling.redact,
    RedactionObjectEncoder? objectEncoder,
    bool redactRfc7468Blocks = true,
    int maxDepth = 32,
    int maxNodes = 10000,
    int maxCollectionLength = 1000,
    int maxStringLength = 65536,
    int maxSecretCount = 1024,
    int maxTotalSecretLength = 1048576,
  }) {
    final safeKeys = Set<String>.unmodifiable(sensitiveKeys);
    final safePaths = List<RedactionPath>.unmodifiable(sensitivePaths);
    final safeHeaderNames = Set<String>.unmodifiable(
      sensitiveHeaderNames.map(_asciiLowercase),
    );
    final safeQueryParameters = Set<String>.unmodifiable(
      sensitiveQueryParameters,
    );
    if (safeKeys.any((key) => key.isEmpty)) {
      throw ArgumentError.value(
        sensitiveKeys,
        'sensitiveKeys',
        'must not contain empty keys',
      );
    }
    if (safeHeaderNames.any((name) => !_isHttpToken(name))) {
      throw ArgumentError.value(
        sensitiveHeaderNames,
        'sensitiveHeaderNames',
        'must contain valid HTTP field names',
      );
    }
    if (safeQueryParameters.any((name) => name.isEmpty)) {
      throw ArgumentError.value(
        sensitiveQueryParameters,
        'sensitiveQueryParameters',
        'must not contain empty names',
      );
    }
    if (maxDepth < 1) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'must be >= 1');
    }
    if (maxNodes < 1) {
      throw ArgumentError.value(maxNodes, 'maxNodes', 'must be >= 1');
    }
    if (maxCollectionLength < 1) {
      throw ArgumentError.value(
        maxCollectionLength,
        'maxCollectionLength',
        'must be >= 1',
      );
    }
    if (maxStringLength < 1) {
      throw ArgumentError.value(
        maxStringLength,
        'maxStringLength',
        'must be >= 1',
      );
    }
    if (maxSecretCount < 1) {
      throw ArgumentError.value(
        maxSecretCount,
        'maxSecretCount',
        'must be >= 1',
      );
    }
    if (maxTotalSecretLength < 1) {
      throw ArgumentError.value(
        maxTotalSecretLength,
        'maxTotalSecretLength',
        'must be >= 1',
      );
    }
    return RedactionPolicy._(
      sensitiveKeys: safeKeys,
      sensitivePaths: safePaths,
      sensitiveHeaderNames: safeHeaderNames,
      sensitiveQueryParameters: safeQueryParameters,
      unknownValueHandling: unknownValueHandling,
      objectEncoder: objectEncoder,
      redactRfc7468Blocks: redactRfc7468Blocks,
      maxDepth: maxDepth,
      maxNodes: maxNodes,
      maxCollectionLength: maxCollectionLength,
      maxStringLength: maxStringLength,
      maxSecretCount: maxSecretCount,
      maxTotalSecretLength: maxTotalSecretLength,
    );
  }

  const RedactionPolicy._({
    required this.sensitiveKeys,
    required this.sensitivePaths,
    required this.sensitiveHeaderNames,
    required this.sensitiveQueryParameters,
    required this.unknownValueHandling,
    required this.objectEncoder,
    required this.redactRfc7468Blocks,
    required this.maxDepth,
    required this.maxNodes,
    required this.maxCollectionLength,
    required this.maxStringLength,
    required this.maxSecretCount,
    required this.maxTotalSecretLength,
  });

  /// Exact structured keys commonly defined as credentials by OAuth and
  /// application configuration formats. Applications should extend this set
  /// with their own schema names instead of relying on name fragments. The
  /// categories follow the [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html),
  /// which calls out access tokens, passwords, session identifiers, keys, and
  /// other primary secrets as data that normally requires special handling.
  static const Set<String> defaultSensitiveKeys = {
    'access_token',
    'refresh_token',
    'id_token',
    'client_secret',
    'client_assertion',
    'password',
    'passphrase',
    'private_key',
    'private_key_id',
    'api_key',
    'access_key',
    'secret_access_key',
    'secret',
    'credential',
    'credentials',
    'session_id',
    'csrf_token',
    'webhook_secret',
    'webhook_signature',
    'accessToken',
    'refreshToken',
    'idToken',
    'clientSecret',
    'clientAssertion',
    'privateKey',
    'privateKeyId',
    'apiKey',
    'accessKey',
    'secretAccessKey',
    'sessionId',
    'csrfToken',
    'webhookSecret',
    'webhookSignature',
  };

  /// HTTP fields whose complete values carry credentials or session state.
  ///
  /// Authorization fields follow [RFC 9110 section 11.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-11.4).
  /// Cookie fields are included conservatively because RFC 9110 notes their
  /// common use for authentication tokens in the same section.
  static const Set<String> defaultSensitiveHeaderNames = {
    'authorization',
    'proxy-authorization',
    'authentication-info',
    'proxy-authentication-info',
    'cookie',
    'set-cookie',
  };

  /// Exact, case-sensitive URI/form parameters from OAuth bearer-token usage
  /// and the OpenTelemetry URL semantic-convention sanitization profile.
  ///
  /// `access_token` follows [RFC 6750 sections 2.2-2.3](https://www.rfc-editor.org/rfc/rfc6750.html#section-2.2).
  /// The remaining defaults mirror the OpenTelemetry [URL attribute registry](https://opentelemetry.io/docs/specs/semconv/registry/attributes/url/),
  /// whose list is explicitly subject to change; callers can replace this set
  /// when they need a different or newer profile.
  static const Set<String> defaultSensitiveQueryParameters = {
    'access_token',
    'X-Amz-Signature',
    'X-Amz-Credential',
    'X-Amz-Security-Token',
    'sig',
    'X-Goog-Signature',
  };

  /// Exact, case-sensitive structured-map and form-parameter names.
  ///
  /// Their complete values are removed. This set does not apply to HTTP field
  /// lines or URI queries.
  final Set<String> sensitiveKeys;

  /// Exact structured paths, evaluated against original and final key names.
  final List<RedactionPath> sensitivePaths;

  /// ASCII case-insensitive HTTP field-line and structured-map names.
  ///
  /// Their complete values are removed. This set does not apply to URI-query
  /// or form-parameter names.
  final Set<String> sensitiveHeaderNames;

  /// Exact, case-sensitive decoded URI-query and form-parameter names.
  ///
  /// Their complete values are removed. This set does not apply to structured
  /// maps or HTTP field lines.
  final Set<String> sensitiveQueryParameters;

  /// The fallback for values outside the supported structured data model.
  final UnknownValueHandling unknownValueHandling;

  /// Optional trusted conversion for application objects.
  final RedactionObjectEncoder? objectEncoder;

  /// Whether matching [RFC 7468](https://www.rfc-editor.org/rfc/rfc7468.html)
  /// textual encoding blocks are replaced as a whole.
  ///
  /// This recognizes boundary syntax and matching labels; it does not validate
  /// certificate, key, or base64 contents.
  final bool redactRfc7468Blocks;

  /// Maximum traversal depth across structured and decoded JSON values.
  final int maxDepth;

  /// Maximum number of values visited by one redaction operation.
  final int maxNodes;

  /// Maximum number of entries in any traversed collection.
  final int maxCollectionLength;

  /// Maximum UTF-16 code-unit count for inspected strings and safe output.
  final int maxStringLength;

  /// Maximum number of distinct non-empty configured literal secrets.
  final int maxSecretCount;

  /// Maximum aggregate UTF-16 code-unit count across literal secrets.
  final int maxTotalSecretLength;

  /// Whether [key] is an exact structured key or configured HTTP field name.
  bool isSensitiveKey(String key) =>
      sensitiveKeys.contains(key) ||
      sensitiveHeaderNames.contains(_asciiLowercase(key));

  /// Whether any configured path matches the complete [path].
  bool isSensitivePath(List<String> path) =>
      sensitivePaths.any((candidate) => candidate.matches(path));
}

/// Raised by direct redaction helpers when an input cannot be sanitized within
/// the configured safety contract.
///
/// [RedactingInterceptor.call] catches this and drops the complete entry.
final class RedactionException implements Exception {
  /// Creates an exception with a non-confidential diagnostic [message].
  const RedactionException(this.message);

  /// A generic diagnostic that never intentionally includes inspected data.
  final String message;

  @override
  String toString() => 'RedactionException: $message';
}

String _asciiLowercase(String value) {
  var firstUppercase = -1;
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0x41 && unit <= 0x5a) {
      firstUppercase = index;
      break;
    }
  }
  if (firstUppercase < 0) return value;

  final units = value.codeUnits.toList();
  for (var index = firstUppercase; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0x41 && unit <= 0x5a) units[index] = unit + 0x20;
  }
  return String.fromCharCodes(units);
}

bool _isHttpToken(String value) {
  if (value.isEmpty) return false;
  for (final unit in value.codeUnits) {
    final alphaNumeric =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5a) ||
        (unit >= 0x61 && unit <= 0x7a);
    const punctuation = {
      0x21,
      0x23,
      0x24,
      0x25,
      0x26,
      0x27,
      0x2a,
      0x2b,
      0x2d,
      0x2e,
      0x5e,
      0x5f,
      0x60,
      0x7c,
      0x7e,
    };
    if (!alphaNumeric && !punctuation.contains(unit)) return false;
  }
  return true;
}
