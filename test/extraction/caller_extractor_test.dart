import 'package:hyper_logger/src/extraction/caller_extractor.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

// Helper: builds a Chain containing a single Trace with the given frames.
Chain _chain(List<Frame> frames) => Chain([Trace(frames)]);

// Helper: builds a synthetic Frame with the given library URI and member name.
Frame _frame(String library, String member) =>
    Frame(Uri.parse(library), 1, 1, member);

void main() {
  late CallerExtractor extractor;

  setUp(() {
    extractor = CallerExtractor();
  });

  group('CallerExtractor.extractFromChain', () {
    test('parses Class.method format correctly', () {
      final chain = _chain([
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('MyClass'));
      expect(result.methodName, equals('myMethod'));
    });

    test('strips generic type bracket characters from method name', () {
      // The regex removes the chars '<', '>', '(', ')' individually.
      // 'myMethod<T>' → the brackets are stripped but the content 'T' remains
      // → 'myMethodT'. This matches the ported original behaviour.
      final chain = _chain([
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod<T>'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.methodName, equals('myMethodT'));
    });

    test('strips parentheses from method name', () {
      final chain = _chain([
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod()'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.methodName, equals('myMethod'));
    });

    test('strips angle bracket chars and parentheses individually', () {
      // 'myMethod<T>()' → strip '<', '>', '(', ')' → 'myMethodT'
      final chain = _chain([
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod<T>()'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.methodName, equals('myMethodT'));
    });

    test('skips frames from hyper_logger library', () {
      final chain = _chain([
        _frame('package:hyper_logger/src/logger.dart', 'HyperLogger.log'),
        _frame('package:my_app/src/foo.dart', 'UserClass.userMethod'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('UserClass'));
      expect(result.methodName, equals('userMethod'));
    });

    test('skips frames from logging library', () {
      final chain = _chain([
        _frame('package:logging/src/logger.dart', 'Logger.log'),
        _frame('package:my_app/src/foo.dart', 'AppClass.appMethod'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('AppClass'));
      expect(result.methodName, equals('appMethod'));
    });

    test('skips frames from dart: core libraries', () {
      final chain = _chain([
        _frame('dart:core', 'print'),
        _frame('package:my_app/src/bar.dart', 'BarClass.barMethod'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('BarClass'));
      expect(result.methodName, equals('barMethod'));
    });

    test('returns null for empty chain', () {
      final chain = _chain([]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNull);
    });

    test('returns null when all frames are internal', () {
      final chain = _chain([
        _frame('package:hyper_logger/src/a.dart', 'A.a'),
        _frame('package:logging/src/b.dart', 'B.b'),
        _frame('dart:async', 'Zone.run'),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNull);
    });

    test('returns null for single-part member with no dot', () {
      final chain = _chain([_frame('package:my_app/src/main.dart', 'main')]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNull);
    });

    test('skips frame with null member', () {
      // Frame with member=null — the Frame constructor accepts null for member.
      final nullMemberFrame = Frame(
        Uri.parse('package:my_app/src/foo.dart'),
        1,
        1,
        null,
      );
      final goodFrame = _frame(
        'package:my_app/src/bar.dart',
        'GoodClass.goodMethod',
      );
      final chain = _chain([nullMemberFrame, goodFrame]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('GoodClass'));
    });

    test('picks first non-internal frame across multiple traces', () {
      final chain = Chain([
        Trace([_frame('package:hyper_logger/src/x.dart', 'X.x')]),
        Trace([_frame('package:my_app/src/baz.dart', 'BazClass.bazMethod')]),
      ]);

      final result = extractor.extractFromChain(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('BazClass'));
    });
  });

  group('CallerExtractor.extract', () {
    test('works with a real StackTrace.current without throwing', () {
      final stackTrace = StackTrace.current;

      expect(() => extractor.extract(stackTrace), returnsNormally);
    });

    test('returns a result or null from real StackTrace without throwing', () {
      final stackTrace = StackTrace.current;
      final result = extractor.extract(stackTrace);

      // May be null if all frames are filtered; just ensure no exception.
      expect(result == null || result.className.isNotEmpty, isTrue);
    });

    test('accepts a Chain directly via extract', () {
      final chain = _chain([
        _frame('package:my_app/src/foo.dart', 'MyClass.myMethod'),
      ]);

      final result = extractor.extract(chain);

      expect(result, isNotNull);
      expect(result!.className, equals('MyClass'));
    });
  });
}
