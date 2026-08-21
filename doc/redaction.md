# Redaction and sanitizers

Use sanitizers when a log entry must satisfy a final privacy policy before any
configured output receives it. HyperLogger applies the ordered sanitizer list
after ordinary interceptors and before both crash reporting and printers.

```dart
final redactor = RedactingInterceptor(
  secrets: [apiToken],
  policy: RedactionPolicy(
    sensitiveKeys: {
      ...RedactionPolicy.defaultSensitiveKeys,
      'merchantSigningSecret',
    },
    sensitivePaths: [
      RedactionPath(['users', RedactionPath.wildcard, 'ssn']),
    ],
  ),
);

HyperLogger.init(
  interceptors: [dropNoisyRecords],
  sanitizers: [redactor.call],
);
```

The boundary is fail-closed. A sanitizer returning `null` or throwing drops the
entry before every sink. A later sanitizer sees the earlier sanitizer's output,
so place the broadest privacy policy last when preceding stages may introduce
new fields.

## What the redactor covers

`RedactingInterceptor` uses exact schema and protocol rules. It does not guess
that arbitrary prose is confidential because a word resembles `token` or
`secret`.

| Input | Matching and behavior |
|---|---|
| Structured maps, lists, and sets | Exact case-sensitive keys and segment paths. A `*` path segment matches one key or index. Both original and final key spellings are checked. |
| JSON text | A complete JSON value is decoded and traversed, then safe output is encoded as valid JSON. General JSON uses `dart:convert` duplicate-name behavior; selected environment JSON is checked more strictly as described below. |
| HTTP field lines | Field names use exact ASCII case-insensitive matching, following [RFC 9110 §5.1][rfc9110]. The complete configured field value is replaced. Historical folded continuations are handled defensively according to the obsolete syntax in [RFC 9112 §5.2][rfc9112]. |
| URI references | URI user information is removed according to [RFC 3986 §3.2.1][rfc3986]. Exact, decoded query names are matched case-sensitively. |
| Form bodies | Complete whitespace-free form representations are split on `&`; exact decoded parameter names are matched case-sensitively against the union of structured keys and query/form parameters. |
| OAuth bearer tokens | `Authorization` and exact `access_token` form/query locations follow [RFC 6750 §2][rfc6750]. |
| Textual key and certificate blocks | Matching `BEGIN`/`END` labels and boundary-line rules follow [RFC 7468 §§2–3][rfc7468]. The redactor removes the complete block; it does not validate its base64 or cryptographic contents. |
| Configured literal secrets | Non-empty literal values are matched case-sensitively with a bounded, linear-time multi-pattern matcher. |

Replacement is compositional: when a transformation changes text or a key, the
candidate is checked again. A replacement cannot synthesize a sensitive form
field, URI, HTTP field, JSON document, structured path, or configured literal
after that representation's parser has already run. If the checks do not reach
a safe fixed point within the strict bound, the entry is dropped.

The complete `LogEntry` surface is covered: canonical message and logger name,
`LogMessage` data and context, errors, stack traces, method and scope metadata,
source type metadata, and tags. HyperLogger synchronizes the
`LogMessage.message` compatibility mirror after every pipeline stage, so
built-in printers and delegates receive the same sanitized entry.

## Exact keys and paths

Default structured keys include common OAuth, session, password, API-key,
private-key, and webhook names in snake_case and camelCase. Extend the set with
the application's actual schema rather than broad substrings:

```dart
final policy = RedactionPolicy(
  sensitiveKeys: {
    ...RedactionPolicy.defaultSensitiveKeys,
    'merchantSigningSecret',
  },
  sensitivePaths: [
    RedactionPath(['payment', 'card', 'pan']),
    RedactionPath(['users', RedactionPath.wildcard, 'ssn']),
  ],
);
```

Every structured surface is a path root. The second path therefore matches:

```dart
HyperLogger.info('Loaded', data: {
  'users': [
    {'name': 'A', 'ssn': '...'},
  ],
});
```

Do not prefix the path with `data` or `context`. Segments compare decoded key
values, so JSON spellings such as `"api_key"` and `"api\u005fkey"` are treated
as the same name. RFC 8259 recommends unique object names and documents
unpredictable receiver behavior for duplicates ([RFC 8259 §§4 and 8.3][rfc8259]).
General JSON redaction uses `dart:convert` and does not promise to reject
duplicate names; avoid ambiguous input. `fromEnvironment` does reject duplicate
decoded names before collecting component secrets, where accepting one of
several conflicting values could weaken literal coverage.

## Query and HTTP defaults

HTTP field names are case-insensitive by specification. The default set removes
complete values for authorization, proxy authorization, authentication-info,
proxy-authentication-info, cookie, and set-cookie fields. RFC 9110 identifies
authorization fields as credential carriers and notes the common use of cookies
for authentication tokens ([RFC 9110 §11.4][rfc9110]).

The policy sets deliberately overlap across formats:

| Policy field | Structured map | HTTP field line | URI query | Form body |
|---|:---:|:---:|:---:|:---:|
| `sensitiveKeys` | Yes | No | No | Yes |
| `sensitiveHeaderNames` | Yes, ASCII case-insensitive | Yes, ASCII case-insensitive | No | No |
| `sensitiveQueryParameters` | No | No | Yes | Yes |

This means replacing `sensitiveQueryParameters` fully replaces URI-query
matching, but form matching still includes `sensitiveKeys`. Likewise, adding a
sensitive HTTP name also protects an ordinary structured map with that key.

Query and form names remain case-sensitive. Defaults include `access_token`
plus the OpenTelemetry URL profile's `X-Amz-Signature`, `X-Amz-Credential`,
`X-Amz-Security-Token`, `sig`, and `X-Goog-Signature`. OpenTelemetry marks its
list as subject to change, so applications that require a pinned or newer
profile should provide `sensitiveQueryParameters` explicitly
([URL semantic conventions][otel-url], [URL attribute registry][otel-registry]).

## Literal and environment secrets

Use `secrets` for opaque values that may occur in free text:

```dart
final redactor = RedactingInterceptor(
  secrets: [apiToken, databasePassword],
);
```

Empty values are ignored and duplicates are compiled once. Secret count,
aggregate length, input length, and output expansion are all bounded. A custom
replacement cannot contain a configured secret, and constructor failures do not
echo confidential inputs.

Server applications can select environment values explicitly:

```dart
final redactor = RedactingInterceptor.fromEnvironment(
  Platform.environment,
  environmentKeys: ['DATABASE_URL', 'SERVICE_ACCOUNT_JSON'],
  additionalSecrets: [runtimeCredential],
);
```

The package never reads process state implicitly. Environment names are exact
and case-sensitive. Each complete selected value is protected; if it is valid
JSON, strings under exact sensitive keys and paths are collected too. Invalid
or over-limit selected data fails construction instead of quietly weakening the
policy.

## Unknown objects and limits

By default, an unsupported application object is replaced without calling
`toString()`. This avoids executing an untrusted or unexpectedly revealing
renderer. Alternatives are explicit:

```dart
final encodedPolicy = RedactionPolicy(
  objectEncoder: (value) => value is Account
      ? {'id': value.id, 'credential': value.credential}
      : throw UnsupportedError('unsupported domain type'),
);

final strictPolicy = RedactionPolicy(
  unknownValueHandling: UnknownValueHandling.dropEntry,
);
```

When configured, `objectEncoder` handles every otherwise unsupported object and
takes precedence over `unknownValueHandling`. Its result is traversed under the
same depth, node, collection, string, cycle, and output limits. Returning the
original object, creating a cycle, or throwing causes the entry to be dropped.
Without an encoder, `UnknownValueHandling.stringify` is a best-effort opt-in and
should only be used for trusted `toString()` contracts. RFC 8259 explicitly
permits JSON parsers to impose implementation limits
([RFC 8259 §9][rfc8259-limits]); the redactor applies limits to every supported
representation, not just JSON.

## Security boundary and limitations

OWASP recommends removing, masking, sanitizing, hashing, or encrypting access
tokens, passwords, session identifiers, encryption keys, and other sensitive
data before it is recorded ([OWASP Logging Cheat Sheet][owasp]). The built-in
defaults are a safe baseline, not a complete classification policy.

- Add exact application-specific keys, paths, headers, and query names.
- Add opaque runtime values through `secrets` or `fromEnvironment`.
- Add separate sanitizers for PII, consent, jurisdiction, retention, or
  organization-specific classification rules.
- Treat log-injection prevention as a separate policy. The redactor preserves
  ordinary newlines and delimiters unless they belong to a supported format.
- Do not send the raw payload to another sink outside HyperLogger and expect
  this boundary to protect it.
- Test every configured sink and deliberate drop condition.

## Performance

Ordinary strings and unchanged structured keys take allocation-conscious fast
paths. Literal secrets are compiled once into a reverse Aho-Corasick-style
matcher. Active transformations pay for bounded representation revalidation;
no-sink log calls skip entry allocation and the complete sanitizer chain.

From a source checkout, run the focused benchmark on deployment-like hardware:

```shell
dart run benchmark/redacting_interceptor_benchmark.dart
```

Absolute timings are machine- and runtime-dependent. Use the benchmark to
compare revisions rather than treating repository measurements as a service
level objective. The benchmark source is also available in the
[repository](https://github.com/SaadArdati/hyper_logger/blob/main/benchmark/redacting_interceptor_benchmark.dart).

[owasp]: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
[rfc9110]: https://www.rfc-editor.org/rfc/rfc9110.html
[rfc9112]: https://www.rfc-editor.org/rfc/rfc9112.html#section-5.2
[rfc3986]: https://www.rfc-editor.org/rfc/rfc3986.html#section-3.2.1
[rfc6750]: https://www.rfc-editor.org/rfc/rfc6750.html#section-2
[rfc8259]: https://www.rfc-editor.org/rfc/rfc8259.html
[rfc8259-limits]: https://www.rfc-editor.org/rfc/rfc8259.html#section-9
[rfc7468]: https://www.rfc-editor.org/rfc/rfc7468.html
[otel-url]: https://opentelemetry.io/docs/specs/semconv/url/
[otel-registry]: https://opentelemetry.io/docs/specs/semconv/registry/attributes/url/
