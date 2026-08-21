import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

final class _ThrowsFromToString {
  @override
  String toString() => throw StateError('cannot render');
}

final class _Credential {
  const _Credential(this.password);

  final String password;
}

final class _SensitiveLogger {}

enum _CredentialKind { apiCredential, publicValue }

final class _ThrowingIterable extends Iterable<Object?> {
  @override
  Iterator<Object?> get iterator => throw StateError('must not iterate');
}

final class _RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void dispose() {}

  @override
  void log(LogEntry entry) {
    entries.add(entry);
  }
}

final class _RecordingCrashReporting extends CrashReportingDelegate {
  final List<String> logs = [];
  final List<(Object, StackTrace?, bool, String?)> errors = [];

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add((error, stackTrace, fatal, reason));
  }
}

LogEntry _entry({
  required String message,
  Object? data,
  Map<String, Object?>? context,
  Object? error,
  StackTrace? stackTrace,
  String loggerName = 'redaction-test',
  String? method,
  StackTrace? callerStackTrace,
  String? scopeTag,
  String? tag,
}) => LogEntry(
  level: LogLevel.error,
  message: message,
  object: LogMessage(
    message,
    _ThrowsFromToString,
    data: data,
    context: context,
    method: method,
    callerStackTrace: callerStackTrace,
    scopeTag: scopeTag,
  ),
  loggerName: loggerName,
  time: DateTime.utc(2026, 8, 21),
  error: error,
  stackTrace: stackTrace,
  tag: tag,
);

void main() {
  setUp(HyperLogger.reset);
  tearDown(HyperLogger.reset);

  group('exact structured policy', () {
    test('redacts exact keys and case-insensitive HTTP field names', () {
      final redactor = RedactingInterceptor();

      final result =
          redactor.redactObject({
                'password': 'password-value',
                'accessToken': 'oauth-value',
                'AUTHORIZATION': 'Basic dXNlcjpwYXNz',
                'Cookie': 'sid=abc; csrf=def',
                'secretary': 'visible-secretary',
                'tokenCount': 4,
                'cookieConsent': true,
                'rapidKey': 'visible-rapid-key',
              })!
              as Map<String, Object?>;

      expect(result['password'], RedactingInterceptor.defaultReplacement);
      expect(result['accessToken'], RedactingInterceptor.defaultReplacement);
      expect(result['AUTHORIZATION'], RedactingInterceptor.defaultReplacement);
      expect(result['Cookie'], RedactingInterceptor.defaultReplacement);
      expect(result['secretary'], 'visible-secretary');
      expect(result['tokenCount'], 4);
      expect(result['cookieConsent'], isTrue);
      expect(result['rapidKey'], 'visible-rapid-key');
    });

    test('policy sets compose only across their documented formats', () {
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(
          sensitiveKeys: const {'formSecret'},
          sensitiveHeaderNames: const {'x-auth'},
          sensitiveQueryParameters: const {'querySecret'},
        ),
      );

      final structured =
          redactor.redactObject({
                'formSecret': 'structured-a',
                'X-Auth': 'structured-b',
                'querySecret': 'structured-visible',
              })!
              as Map<String, Object?>;
      expect(structured['formSecret'], '[redacted]');
      expect(structured['X-Auth'], '[redacted]');
      expect(structured['querySecret'], 'structured-visible');

      expect(
        redactor.redactText(
          'formSecret=form-a&querySecret=form-b&x-auth=form-visible',
        ),
        'formSecret=%5Bredacted%5D&querySecret=%5Bredacted%5D&x-auth=form-visible',
      );
      expect(
        redactor.redactText(
          'https://example.test/?formSecret=query-visible&'
          'querySecret=query-b&x-auth=query-visible',
        ),
        'https://example.test/?formSecret=query-visible&'
        'querySecret=%5Bredacted%5D&x-auth=query-visible',
      );
      expect(redactor.redactText('X-Auth: header-b'), 'X-Auth: [redacted]');
    });

    test('matches explicit segment paths with one-level wildcards', () {
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(
          sensitiveKeys: const {},
          sensitiveHeaderNames: const {},
          sensitiveQueryParameters: const {},
          sensitivePaths: [
            RedactionPath(const ['data', 'users', '*', 'ssn']),
          ],
        ),
      );

      final result =
          redactor.redactObject({
                'data': {
                  'users': [
                    {'ssn': '111', 'name': 'A'},
                    {'ssn': '222', 'name': 'B'},
                  ],
                },
              })!
              as Map<String, Object?>;
      final data = result['data']! as Map<String, Object?>;
      final users = data['users']! as List<Object?>;

      expect((users[0]! as Map<String, Object?>)['ssn'], '[redacted]');
      expect((users[1]! as Map<String, Object?>)['ssn'], '[redacted]');
      expect((users[0]! as Map<String, Object?>)['name'], 'A');
    });

    test('treats LogMessage.data as the root of an exact path', () {
      final printer = _RecordingPrinter();
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(
          sensitiveKeys: const {},
          sensitiveHeaderNames: const {},
          sensitiveQueryParameters: const {},
          sensitivePaths: [
            RedactionPath(const ['users', '*', 'ssn']),
          ],
        ),
      );
      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );

      HyperLogger.info<String>(
        'users',
        data: {
          'users': [
            {'ssn': '111', 'name': 'A'},
          ],
        },
      );
      final data =
          (printer.entries.single.object! as LogMessage).data!
              as Map<String, Object?>;
      final users = data['users']! as List<Object?>;

      expect((users.single! as Map<String, Object?>)['ssn'], '[redacted]');
      expect((users.single! as Map<String, Object?>)['name'], 'A');
    });
  });

  group('protocol-aware text handling', () {
    test('rechecks protocol rules after literal replacement', () {
      final redactor = RedactingInterceptor(
        secrets: const ['SECRET'],
        replacement: 'access',
      );

      expect(redactor.redactText('SECRET_token=oauth'), 'access_token=access');

      final synthesizedSyntax =
          RedactingInterceptor(
                secrets: const ['SECRET'],
                replacement: 'access_token=',
              ).redactObject({'SECRETfoo': 'public'})!
              as Map<String, Object?>;
      expect(synthesizedSyntax.keys.single, isNot(contains('foo')));
    });

    test('rechecks JSON rules after literal replacement', () {
      final redactor = RedactingInterceptor(
        secrets: const ['SECRET'],
        replacement: '{"password":"',
      );

      final result = redactor.redactText('SECRETclear"}');

      expect(result, isNot(contains('clear')));
      expect(jsonDecode(result), {'password': '{"password":"'});
    });

    test('checks JSON values against final redacted key paths', () {
      final redactor = RedactingInterceptor(
        secrets: const ['SECRET'],
        replacement: 'access',
      );

      expect(jsonDecode(redactor.redactText('{"SECRET_token":"oauth"}')), {
        'access_token': 'access',
      });
      final pathRedactor = RedactingInterceptor(
        secrets: const ['SECRET'],
        replacement: 'access',
        policy: RedactionPolicy(
          sensitivePaths: [
            RedactionPath(const ['access', 'access']),
          ],
        ),
      );
      expect(
        pathRedactor.redactObject({
          'SECRET': {'SECRET': 'oauth'},
        }),
        {
          'access': {'access': 'access'},
        },
      );
    });

    test('redacts complete HTTP credential and cookie field values', () {
      final redactor = RedactingInterceptor();
      const source =
          'Authorization: Basic dXNlcjpwYXNz\r\n'
          'Proxy-Authorization: Digest username="u", response="digest"\r\n'
          'Cookie: sid=abc; csrf=def\r\n'
          'Set-Cookie: sid=ghi; Secure; HttpOnly\r\n'
          'Content-Type: application/json';

      final result = redactor.redactText(source);

      for (final secret in [
        'dXNlcjpwYXNz',
        'username',
        'digest',
        'sid=abc',
        'csrf=def',
        'sid=ghi',
      ]) {
        expect(result, isNot(contains(secret)));
      }
      expect(result, contains('Content-Type: application/json'));
      expect(
        redactor.redactText('  Authorization: this is indented prose'),
        '  Authorization: this is indented prose',
      );
    });

    test('redacts obsolete folded sensitive field continuations', () {
      final redactor = RedactingInterceptor();
      const crlf =
          'Authorization:\r\n'
          ' Basic dXNlcjpwYXNz\r\n'
          '\tcontinued-credential\r\n'
          'Content-Type: application/json';
      const lf =
          'Cookie:\n'
          ' sid=abc; csrf=def\n'
          'X-Visible: yes';

      final redactedCrlf = redactor.redactText(crlf);
      final redactedLf = redactor.redactText(lf);

      expect(redactedCrlf, isNot(contains('dXNlcjpwYXNz')));
      expect(redactedCrlf, isNot(contains('continued-credential')));
      expect(redactedCrlf, contains('Content-Type: application/json'));
      expect(redactedLf, isNot(contains('sid=abc')));
      expect(redactedLf, isNot(contains('csrf=def')));
      expect(redactedLf, contains('X-Visible: yes'));
      expect(
        redactor.redactText('  Authorization: this is indented prose'),
        '  Authorization: this is indented prose',
      );
    });

    test('removes URI userinfo and exact sensitive query values', () {
      final redactor = RedactingInterceptor();
      const source =
          'https://user:password@example.com/path?access_token=oauth'
          '&X-Amz-Signature=aws&x-amz-signature=case-sensitive'
          '&visible=yes#fragment';

      final result = redactor.redactText(source);

      expect(result, isNot(contains('user:password')));
      expect(result, isNot(contains('oauth')));
      expect(result, isNot(contains('=aws')));
      expect(result, contains('x-amz-signature=case-sensitive'));
      expect(result, contains('visible=yes#fragment'));
    });

    test('redacts query-only and relative-path URI references', () {
      final redactor = RedactingInterceptor();

      expect(
        redactor.redactText('?access_token=oauth&visible=yes'),
        isNot(contains('oauth')),
      );
      expect(
        redactor.redactText('callback?access_token=oauth&visible=yes'),
        isNot(contains('oauth')),
      );
    });

    test('composes URI and form redaction for ambiguous input', () async {
      const source = 'password=clear?access_token=oauth';
      final redactor = RedactingInterceptor();
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();

      final direct = redactor.redactText(source);
      expect(direct, isNot(contains('clear')));
      expect(direct, isNot(contains('oauth')));

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.error<int>(source, data: source, exception: source);
      await Future<void>.delayed(Duration.zero);

      final entry = printer.entries.single;
      final printedData = (entry.object! as LogMessage).data! as String;
      for (final rendered in [
        entry.message,
        printedData,
        '${entry.error}',
        '${crash.errors.single.$1}',
        crash.errors.single.$4!,
      ]) {
        expect(rendered, isNot(contains('clear')));
        expect(rendered, isNot(contains('oauth')));
      }
    });

    test('matches percent-encoded URI parameter names after decoding', () {
      final result = RedactingInterceptor().redactText(
        'https://example.com/?X%2DAmz%2DSignature=aws-secret',
      );

      expect(result, isNot(contains('aws-secret')));
      expect(result, contains('X%2DAmz%2DSignature='));
    });

    test('redacts literals after sanitizing a structured URI', () async {
      const secret = 'literal-secret';
      final uri = Uri.parse('https://u:p@example.test/?visible=$secret');
      final redactor = RedactingInterceptor(secrets: const [secret]);
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();

      final direct = redactor.redactObject(uri)! as String;
      expect(direct, isNot(contains('u:p')));
      expect(direct, isNot(contains(secret)));

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.error<int>('failed', data: uri, exception: uri);
      await Future<void>.delayed(Duration.zero);

      final printedData =
          (printer.entries.single.object! as LogMessage).data! as String;
      expect(printedData, isNot(contains('u:p')));
      expect(printedData, isNot(contains(secret)));
      expect('${printer.entries.single.error}', isNot(contains(secret)));
      expect('${crash.errors.single.$1}', isNot(contains(secret)));
    });

    test('sanitizes protocol credentials in structured map keys', () async {
      const secretKey =
          'https://user:password@example.test/?access_token=oauth';
      final redactor = RedactingInterceptor();
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();

      final direct = redactor.redactObject({secretKey: true})! as Map;
      final directKey = direct.keys.single as String;
      expect(directKey, isNot(contains('user:password')));
      expect(directKey, isNot(contains('oauth')));

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.error<int>(
        'failed',
        data: {secretKey: true},
        exception: {secretKey: false},
      );
      await Future<void>.delayed(Duration.zero);

      final entry = printer.entries.single;
      final rendered = jsonEncode({
        'data': (entry.object! as LogMessage).data,
        'error': '${entry.error}',
        'delegateError': '${crash.errors.single.$1}',
      });
      expect(rendered, isNot(contains('user:password')));
      expect(rendered, isNot(contains('oauth')));
    });

    test('redacts complete form and JSON values with spaces', () {
      final redactor = RedactingInterceptor();

      final form = redactor.redactText(
        'access_token=oauth&password=two+words&visible=yes',
      );
      final json =
          jsonDecode(
                redactor.redactText(
                  jsonEncode({
                    'password': 'two word password',
                    'secretary': 'visible',
                    'headers': {'Authorization': 'Basic credential'},
                  }),
                ),
              )!
              as Map<String, Object?>;

      expect(form, isNot(contains('oauth')));
      expect(form, isNot(contains('two+words')));
      expect(form, contains('visible=yes'));
      expect(json['password'], '[redacted]');
      expect(json['secretary'], 'visible');
      expect(
        (json['headers']! as Map<String, Object?>)['Authorization'],
        '[redacted]',
      );
    });

    test('keeps JSON valid when literal patterns resemble JSON syntax', () {
      final syntaxRedactor = RedactingInterceptor(
        secrets: const ['":"'],
        replacement: '#',
      );
      final escapedReplacement = RedactingInterceptor(
        secrets: const ['credential'],
        replacement: 'quote" slash\\ control\u0001 newline\n',
      );

      final syntaxMatched = syntaxRedactor.redactText('{"a":"b"}');
      final replaced = escapedReplacement.redactText(
        jsonEncode({'value': 'credential'}),
      );

      expect(jsonDecode(syntaxMatched), '#');
      expect(jsonDecode(replaced), {
        'value': 'quote" slash\\ control\u0001 newline\n',
      });
    });

    test('fails closed when no safe JSON replacement exists', () {
      final redactor = RedactingInterceptor(
        secrets: const ['\\"'],
        replacement: '"',
      );

      expect(
        () => redactor.redactText('{"password":"value"}'),
        throwsA(isA<RedactionException>()),
      );
    });

    test('redacts a complete RFC 7468 block with a matching label', () {
      const block =
          '-----BEGIN PRIVATE-KEY-----\nabc123\n'
          '-----END PRIVATE-KEY-----';

      final redactor = RedactingInterceptor();
      final result = redactor.redactText('before\n$block\nafter');

      expect(result, 'before\n[redacted]\nafter');
      expect(redactor.redactText('inline $block'), 'inline $block');
      expect(
        redactor.redactText('-----BEGIN -----\neA==\n-----END -----'),
        '[redacted]',
      );
    });

    test(
      'accepts RFC 7468 boundary whitespace and CR-only line endings',
      () async {
        const lfSecret = 'lf-private-material';
        const crSecret = 'cr-private-material';
        const lfBlock =
            '-----BEGIN PRIVATE KEY----- \t\n$lfSecret\n'
            '-----END PRIVATE KEY----- \t';
        const crBlock =
            '-----BEGIN CERTIFICATE-----\t\r$crSecret\r'
            '-----END CERTIFICATE----- ';
        final redactor = RedactingInterceptor();
        final printer = _RecordingPrinter();
        final crash = _RecordingCrashReporting();

        expect(redactor.redactText(lfBlock), isNot(contains(lfSecret)));
        expect(redactor.redactText(crBlock), isNot(contains(crSecret)));

        HyperLogger.init(
          printer: printer,
          sanitizers: [redactor.call],
          captureStackTrace: false,
        );
        HyperLogger.attachServices(crashReporting: crash);
        HyperLogger.error<int>(lfBlock, data: crBlock, exception: crBlock);
        await Future<void>.delayed(Duration.zero);

        final entry = printer.entries.single;
        final rendered = jsonEncode({
          'message': entry.message,
          'data': (entry.object! as LogMessage).data,
          'error': '${entry.error}',
          'delegateError': '${crash.errors.single.$1}',
          'delegateReason': crash.errors.single.$4,
        });
        expect(rendered, isNot(contains(lfSecret)));
        expect(rendered, isNot(contains(crSecret)));
      },
    );

    test('sanitizes secrets encoded in top-level JSON strings', () async {
      const block =
          '-----BEGIN PRIVATE KEY-----\nabc123\n'
          '-----END PRIVATE KEY-----';
      const literal = 'credential "with quotes"\nand a newline';
      final encodedBlock = jsonEncode(block);
      final encodedLiteral = jsonEncode(literal);
      final redactor = RedactingInterceptor(secrets: const [literal]);
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();

      expect(jsonDecode(redactor.redactText(encodedBlock)), '[redacted]');
      expect(jsonDecode(redactor.redactText(encodedLiteral)), '[redacted]');

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);
      HyperLogger.error<int>(
        encodedLiteral,
        data: {'document': encodedBlock},
        exception: encodedBlock,
      );
      await Future<void>.delayed(Duration.zero);

      final entry = printer.entries.single;
      final data = (entry.object! as LogMessage).data! as Map<String, Object?>;
      expect(jsonDecode(entry.message), '[redacted]');
      expect(jsonDecode(data['document']! as String), '[redacted]');
      expect(jsonDecode(entry.error! as String), '[redacted]');
      expect(jsonDecode(crash.errors.single.$1 as String), '[redacted]');
      expect(jsonDecode(crash.errors.single.$4!), '[redacted]');
    });
  });

  group('configured secret values', () {
    test('uses longest single-pass matches and is idempotent', () {
      final redactor = RedactingInterceptor(
        secrets: const ['secret', 'secret-long'],
        replacement: '***',
      );

      final once = redactor.redactText('secret-long secret visible');
      final twice = redactor.redactText(once);

      expect(once, '*** *** visible');
      expect(twice, once);
    });

    test('rejects a replacement that contains a configured secret', () {
      expect(
        () => RedactingInterceptor(secrets: const ['redacted']),
        throwsArgumentError,
      );
      expect(
        () => RedactingInterceptor(secrets: const ['a']),
        throwsArgumentError,
      );
      expect(
        () => RedactingInterceptor(secrets: const ['a'], replacement: '***'),
        returnsNormally,
      );
    });

    test('cannot regenerate a secret across a replacement boundary', () {
      final redactor = RedactingInterceptor(
        secrets: const ['abc'],
        replacement: 'ab',
      );

      final result = redactor.redactText('abcc');

      expect(result, 'ab');
      expect(result, isNot(contains('abc')));
    });

    test('redacts configured secrets represented by supported scalars', () {
      final date = DateTime.utc(2026, 8, 21);
      const duration = Duration(seconds: 5);
      final redactor = RedactingInterceptor(
        secrets: [
          '123456',
          'true',
          '987654321',
          date.toString(),
          duration.toString(),
          'apiCredential',
        ],
      );

      final result =
          redactor.redactObject({
                'pin': 123456,
                'flag': true,
                'big': BigInt.from(987654321),
                'date': date,
                'duration': duration,
                'credentialKind': _CredentialKind.apiCredential,
                'publicKind': _CredentialKind.publicValue,
                'safeNumber': 42,
              })!
              as Map<String, Object?>;

      for (final key in [
        'pin',
        'flag',
        'big',
        'date',
        'duration',
        'credentialKind',
      ]) {
        expect(result[key], '[redacted]', reason: key);
      }
      expect(result['publicKind'], 'publicValue');
      expect(result['safeNumber'], 42);
    });

    test('handles adversarial overlapping near-misses in linear work', () {
      final secret = '${List.filled(32768, 'a').join()}b';
      final input = List.filled(65536, 'a').join();
      final redactor = RedactingInterceptor(secrets: [secret]);

      final result = redactor.redactText(input);

      expect(identical(result, input), isTrue);
    });

    test('validates an overlapping replacement in linear work', () {
      final secret = '${List.filled(32768, 'a').join()}b';
      final replacement = List.filled(65536, 'a').join();

      expect(
        () => RedactingInterceptor(secrets: [secret], replacement: replacement),
        returnsNormally,
      );
    });

    test('preserves leftmost-longest semantics across overlaps', () {
      final random = Random(42);
      String generate(int length) => String.fromCharCodes(
        List.generate(length, (_) => 0x61 + random.nextInt(3)),
      );

      for (var iteration = 0; iteration < 200; iteration++) {
        final secrets = <String>{
          for (var index = 0; index < 8; index++)
            generate(1 + random.nextInt(8)),
        };
        final input = generate(80);
        final expected = StringBuffer();
        var index = 0;
        while (index < input.length) {
          var longestMatch = 0;
          for (final secret in secrets) {
            if (secret.length > longestMatch &&
                input.startsWith(secret, index)) {
              longestMatch = secret.length;
            }
          }
          if (longestMatch == 0) {
            expected.writeCharCode(input.codeUnitAt(index++));
          } else {
            expected.write('#');
            index += longestMatch;
          }
        }

        final actual = RedactingInterceptor(
          secrets: secrets,
          replacement: '#',
        ).redactText(input);
        expect(actual, expected.toString(), reason: 'iteration $iteration');
      }
    });

    test('fails closed before literal replacement can expand output', () {
      final printer = _RecordingPrinter();
      final redactor = RedactingInterceptor(
        secrets: const ['a'],
        replacement: List.filled(64, 'b').join(),
        policy: RedactionPolicy(maxStringLength: 64),
      );

      expect(
        () => redactor.redactText('aaaa'),
        throwsA(isA<RedactionException>()),
      );

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.info<int>('ok', data: 'aaaa');
      expect(printer.entries, isEmpty);
    });

    test('bounds matcher construction inputs', () {
      expect(
        () => RedactingInterceptor(
          secrets: const ['one', 'two'],
          policy: RedactionPolicy(maxSecretCount: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => RedactingInterceptor(
          secrets: const ['long'],
          policy: RedactionPolicy(maxTotalSecretLength: 3),
        ),
        throwsArgumentError,
      );
      expect(
        () => RedactingInterceptor(
          replacement: 'toolong',
          policy: RedactionPolicy(maxStringLength: 3),
        ),
        throwsArgumentError,
      );
    });

    test('constructor errors never render confidential inputs', () {
      String renderedError(void Function() action) {
        Object? error;
        try {
          action();
        } catch (caught) {
          error = caught;
        }
        expect(error, isNotNull);
        return '$error';
      }

      final overlongSecret = renderedError(
        () => RedactingInterceptor(
          secrets: const ['secret-input'],
          replacement: '#',
          policy: RedactionPolicy(maxStringLength: 3),
        ),
      );
      final unsafeReplacement = renderedError(
        () => RedactingInterceptor(
          secrets: const ['token'],
          replacement: 'prefix-token',
        ),
      );
      final overlongEnvironment = renderedError(
        () => RedactingInterceptor.fromEnvironment(
          const {'SECRET_ENV': 'environment-secret'},
          environmentKeys: const ['SECRET_ENV'],
          replacement: '#',
          policy: RedactionPolicy(maxStringLength: 3),
        ),
      );
      final duplicateKey = renderedError(
        () => RedactingInterceptor.fromEnvironment(
          const {
            'JSON_ENV':
                '{"confidential-key":"first-value",'
                '"confidential-key":"second-value"}',
          },
          environmentKeys: const ['JSON_ENV'],
        ),
      );

      expect(overlongSecret, isNot(contains('secret-input')));
      expect(unsafeReplacement, isNot(contains('token')));
      expect(unsafeReplacement, isNot(contains('prefix-token')));
      expect(overlongEnvironment, isNot(contains('environment-secret')));
      expect(duplicateKey, isNot(contains('confidential-key')));
      expect(duplicateKey, isNot(contains('first-value')));
      expect(duplicateKey, isNot(contains('second-value')));
    });
  });

  test('environment collection uses exact names and selected JSON fields', () {
    const privateKey = 'firebase-private-key-value';
    final redactor = RedactingInterceptor.fromEnvironment(
      {
        'FIREBASE_SERVICE_ACCOUNT': jsonEncode({
          'private_key': privateKey,
          'client_email': 'server@example.com',
        }),
        'API_TOKEN': 'unselected-environment-value',
      },
      environmentKeys: const ['FIREBASE_SERVICE_ACCOUNT'],
      additionalSecrets: const ['runtime-secret'],
      replacement: '***',
    );

    final result = redactor.redactText(
      '$privateKey runtime-secret server@example.com '
      'unselected-environment-value',
    );

    expect(result, '*** *** server@example.com unselected-environment-value');
  });

  test('redacts a complete selected environment JSON literal', () async {
    final selected = jsonEncode({'client_email': 'server@example.com'});
    final redactor = RedactingInterceptor.fromEnvironment(
      {'SERVICE': selected},
      environmentKeys: const ['SERVICE'],
      replacement: '***',
    );
    final printer = _RecordingPrinter();
    final crash = _RecordingCrashReporting();

    expect(jsonDecode(redactor.redactText(selected)), '***');

    HyperLogger.init(
      printer: printer,
      sanitizers: [redactor.call],
      captureStackTrace: false,
    );
    HyperLogger.attachServices(crashReporting: crash);
    HyperLogger.error<int>(selected, data: selected, exception: selected);
    await Future<void>.delayed(Duration.zero);

    final entry = printer.entries.single;
    final output = jsonEncode({
      'message': entry.message,
      'data': (entry.object! as LogMessage).data,
      'error': entry.error,
      'delegateError': '${crash.errors.single.$1}',
      'delegateReason': crash.errors.single.$4,
    });
    expect(output, isNot(contains(selected)));
    expect(output, isNot(contains('server@example.com')));
  });

  test('environment collection fails closed above policy limits', () {
    const componentSecret = 'short-secret';
    final selectedJson = jsonEncode({
      'password': componentSecret,
      'padding':
          'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    });

    expect(selectedJson.length, greaterThan(32));
    expect(
      () => RedactingInterceptor.fromEnvironment(
        {'SELECTED_JSON': selectedJson},
        environmentKeys: const ['SELECTED_JSON'],
        policy: RedactionPolicy(maxStringLength: 32),
      ),
      throwsA(isA<RedactionException>()),
    );
  });

  test('environment collection rejects duplicate decoded JSON keys', () {
    const duplicate =
        '{"password":"first-secret",'
        '"pass\\u0077ord":"second-secret"}';

    expect(
      () => RedactingInterceptor.fromEnvironment(
        const {'SELECTED_JSON': duplicate},
        environmentKeys: const ['SELECTED_JSON'],
      ),
      throwsA(isA<RedactionException>()),
    );
  });

  group('bounded fail-closed traversal', () {
    test('bounds expansion from every decoded text format', () {
      final redactor = RedactingInterceptor(
        replacement: List.filled(64, 'b').join(),
        policy: RedactionPolicy(maxStringLength: 64),
      );

      for (final input in [
        'Authorization: x',
        'password=x',
        jsonEncode({'password': 'x', 'visible': 'y'}),
        'before\n-----BEGIN X-----\na\n-----END X-----',
      ]) {
        expect(
          () => redactor.redactText(input),
          throwsA(isA<RedactionException>()),
          reason: input,
        );
      }
    });

    test('accounts for lone-surrogate JSON escaping before encoding', () {
      final redactor = RedactingInterceptor(
        replacement: String.fromCharCodes(List.filled(20, 0xd800)),
        policy: RedactionPolicy(maxStringLength: 64),
      );

      expect(
        () => redactor.redactText(jsonEncode({'password': 'x'})),
        throwsA(isA<RedactionException>()),
      );
    });

    test('preflights percent-encoded replacement expansion', () {
      final redactor = RedactingInterceptor(
        replacement: List.filled(64, '\u0800').join(),
        policy: RedactionPolicy(maxStringLength: 64),
      );

      expect(
        () => redactor.redactText('password=x'),
        throwsA(isA<RedactionException>()),
      );
    });

    test('enforces the string limit for URI values and drops the entry', () {
      final printer = _RecordingPrinter();
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(maxStringLength: 8),
        replacement: '***',
      );
      final uri = Uri.parse('https://example.test/too-long');

      expect(
        () => redactor.redactObject(uri),
        throwsA(isA<RedactionException>()),
      );

      HyperLogger.init(
        printer: printer,
        sanitizers: [redactor.call],
        captureStackTrace: false,
      );
      HyperLogger.info<int>('ok', data: uri);

      expect(printer.entries, isEmpty);
    });

    test('redacts unknown objects without invoking toString', () {
      final redactor = RedactingInterceptor();
      final redacted = redactor(
        _entry(message: 'safe', data: _ThrowsFromToString()),
      );

      expect(redacted, isNotNull);
      final message = redacted!.object! as LogMessage;
      expect(message.data, '[redacted]');
    });

    test('can require unknown objects to drop the complete entry', () {
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(
          unknownValueHandling: UnknownValueHandling.dropEntry,
        ),
      );

      expect(
        redactor(_entry(message: 'safe', data: _ThrowsFromToString())),
        isNull,
      );
    });

    test('sanitizes application objects through an explicit encoder', () {
      final redactor = RedactingInterceptor(
        policy: RedactionPolicy(
          objectEncoder: (value) => switch (value) {
            _Credential(:final password) => {'password': password},
            _ => throw UnsupportedError('unsupported'),
          },
        ),
      );

      final result = redactor.redactObject(const _Credential('credential'));

      expect(result, {'password': '[redacted]'});
    });

    test('drops cyclic data and collections over configured limits', () {
      final cycle = <String, Object?>{};
      cycle['self'] = cycle;
      final cycleRedactor = RedactingInterceptor();
      final limitedRedactor = RedactingInterceptor(
        policy: RedactionPolicy(maxCollectionLength: 1),
      );

      expect(cycleRedactor(_entry(message: 'safe', data: cycle)), isNull);
      expect(limitedRedactor(_entry(message: 'safe', data: [1, 2])), isNull);
    });

    test(
      'does not iterate arbitrary lazy iterables and redacts binary data',
      () {
        final result =
            RedactingInterceptor().redactObject({
                  'lazy': _ThrowingIterable(),
                  'bytes': Uint8List.fromList([1, 2, 3]),
                })!
                as Map<String, Object?>;

        expect(result['lazy'], '[redacted]');
        expect(result['bytes'], '[redacted]');
      },
    );
  });

  test('sanitizer chain protects printers and crash reporting', () async {
    const secret = 'fanout-secret';
    final primary = _RecordingPrinter();
    final crash = _RecordingCrashReporting();
    final redactor = RedactingInterceptor(secrets: const [secret]);
    HyperLogger.init(
      printer: primary,
      interceptors: [
        (entry) => entry.copyWith(message: '${entry.message} enriched'),
      ],
      sanitizers: [
        (entry) => entry.copyWith(loggerName: '${entry.loggerName} checked'),
        redactor.call,
      ],
      captureStackTrace: false,
    );
    HyperLogger.attachServices(crashReporting: crash);

    HyperLogger.error<String>(
      'failed with $secret',
      data: {'credential': secret},
      exception: 'password=$secret',
    );
    await Future<void>.delayed(Duration.zero);

    expect(primary.entries, hasLength(1));
    expect(crash.errors, hasLength(1));
    final printed = jsonEncode({
      'entry': primary.entries.single.message,
      'data': (primary.entries.single.object! as LogMessage).data,
      'error': '${primary.entries.single.error}',
    });
    final delegated = jsonEncode({
      'error': '${crash.errors.single.$1}',
      'reason': crash.errors.single.$4,
    });
    expect(printed, isNot(contains(secret)));
    expect(delegated, isNot(contains(secret)));
    expect(primary.entries.single.message, endsWith('enriched'));
    expect(primary.entries.single.loggerName, endsWith('checked'));
    expect(
      (primary.entries.single.object! as LogMessage).reportToCrashReporting,
      isTrue,
    );
  });

  test(
    'replacement composition cannot expose values to printer or delegate',
    () async {
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();
      HyperLogger.init(
        printer: printer,
        sanitizers: [
          RedactingInterceptor(
            secrets: const ['SECRET'],
            replacement: 'access',
          ).call,
        ],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.error<String>(
        'SECRET_token=oauth',
        data: const {'SECRET_token': 'oauth'},
        exception: 'SECRET_token=oauth',
      );
      await Future<void>.delayed(Duration.zero);

      final printed = jsonEncode({
        'message': printer.entries.single.message,
        'object': (printer.entries.single.object! as LogMessage).data,
        'error': '${printer.entries.single.error}',
      });
      final delegated = jsonEncode({
        'error': '${crash.errors.single.$1}',
        'reason': crash.errors.single.$4,
      });
      expect(printed, isNot(contains('oauth')));
      expect(delegated, isNot(contains('oauth')));
      expect(printed, contains('access_token=access'));
    },
  );

  test(
    'synthesized JSON cannot expose values to printer or delegate',
    () async {
      final printer = _RecordingPrinter();
      final crash = _RecordingCrashReporting();
      HyperLogger.init(
        printer: printer,
        sanitizers: [
          RedactingInterceptor(
            secrets: const ['SECRET'],
            replacement: '{"password":"',
          ).call,
        ],
        captureStackTrace: false,
      );
      HyperLogger.attachServices(crashReporting: crash);

      HyperLogger.error<String>(
        'SECRETclear"}',
        data: 'SECRETclear"}',
        exception: 'SECRETclear"}',
      );
      await Future<void>.delayed(Duration.zero);

      final printed = jsonEncode({
        'message': printer.entries.single.message,
        'data': (printer.entries.single.object! as LogMessage).data,
        'error': '${printer.entries.single.error}',
      });
      final delegated = jsonEncode({
        'error': '${crash.errors.single.$1}',
        'reason': crash.errors.single.$4,
      });
      expect(printed, isNot(contains('clear')));
      expect(delegated, isNot(contains('clear')));
    },
  );

  test('LogEntry fields stay canonical across built-in printers', () {
    const messageSecret = 'message-secret';
    const loggerSecret = '_SensitiveLogger';
    final cloudOutput = <String>[];
    final humanOutput = <String>[];
    final recording = _RecordingPrinter();
    HyperLogger.init(
      printer: MultiPrinter([
        GcpJsonPrinter(output: cloudOutput.add),
        ComposablePrinter(
          const [PrefixDecorator()],
          output: humanOutput.add,
          suppressTypeNames: false,
        ),
        recording,
      ]),
      sanitizers: [
        (entry) => entry.copyWith(
          message: '[safe-message]',
          loggerName: '[safe-logger]',
        ),
      ],
      captureStackTrace: false,
    );

    HyperLogger.info<_SensitiveLogger>(messageSecret);

    final rendered = [...cloudOutput, ...humanOutput].join('\n');
    expect(rendered, isNot(contains(messageSecret)));
    expect(rendered, isNot(contains(loggerSecret)));
    expect(rendered, contains('[safe-message]'));
    expect(rendered, contains('[safe-logger]'));
    final mirror = recording.entries.single.object! as LogMessage;
    expect(mirror.message, '[safe-message]');
  });

  test('drops an entry when the safe type placeholder is sensitive', () {
    final printer = _RecordingPrinter();
    HyperLogger.init(
      printer: printer,
      sanitizers: [
        RedactingInterceptor(
          secrets: const ['Object'],
          replacement: '***',
        ).call,
      ],
      captureStackTrace: false,
    );

    HyperLogger.info<Object>('safe');

    expect(printer.entries, isEmpty);
  });

  test('scalar secrets are removed from printer and delegate output', () async {
    const pin = 123456;
    final printer = _RecordingPrinter();
    final crash = _RecordingCrashReporting();
    HyperLogger.init(
      printer: printer,
      sanitizers: [
        RedactingInterceptor(secrets: const ['$pin']).call,
      ],
      captureStackTrace: false,
    );
    HyperLogger.attachServices(crashReporting: crash);

    HyperLogger.error<String>(
      'failed',
      data: const {'pin': pin},
      exception: pin,
    );
    await Future<void>.delayed(Duration.zero);

    final data =
        (printer.entries.single.object! as LogMessage).data!
            as Map<String, Object?>;
    expect(data['pin'], '[redacted]');
    expect('${printer.entries.single.error}', isNot(contains('$pin')));
    expect('${crash.errors.single.$1}', isNot(contains('$pin')));
  });

  test('a throwing sanitizer drops the record from every sink', () async {
    final printer = _RecordingPrinter();
    final crash = _RecordingCrashReporting();
    HyperLogger.init(
      printer: printer,
      sanitizers: [(_) => throw StateError('broken sanitizer')],
    );
    HyperLogger.attachServices(crashReporting: crash);

    HyperLogger.error<String>('must be dropped');
    await Future<void>.delayed(Duration.zero);

    expect(printer.entries, isEmpty);
    expect(crash.errors, isEmpty);
  });

  test('pre-sanitization pipeline failures expose only generic errors', () {
    const secret = 'interceptor-error-secret';
    final printer = _RecordingPrinter();
    Object? reportedError;
    HyperLogger.setPipelineErrorHandler((_, error, _) {
      reportedError = error;
    });
    HyperLogger.init(
      printer: printer,
      interceptors: [(_) => throw StateError(secret)],
      sanitizers: [
        RedactingInterceptor(secrets: const [secret]).call,
      ],
    );

    HyperLogger.info<String>('message contains $secret');

    expect('$reportedError', isNot(contains(secret)));
    expect(printer.entries.single.message, isNot(contains(secret)));
  });
}
