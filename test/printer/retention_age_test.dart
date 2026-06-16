@TestOn('vm')
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:hyper_logger/hyper_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hl_age_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<String> archives(String basePath) {
    final dir = Directory(p.dirname(basePath));
    final stem = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    final re = RegExp(
      '^${RegExp.escape(stem)}'
      r'\.\d{8}T\d{6}Z(?:\.\d+)?'
      '${RegExp.escape(ext)}'
      r'(\.gz)?$',
    );
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where(re.hasMatch)
        .toList();
  }

  test('maxAge prunes archives whose filename timestamp is too old', () async {
    final path = '${tempDir.path}/app.log';
    // Seed two pre-existing "archives" with explicit timestamps in the name.
    // 40 days old (should be pruned) and 2 days old (should survive),
    // relative to the fixed clock below.
    File(
      '${tempDir.path}/app.20260507T120000Z.log',
    ).writeAsStringSync('old'); // ~40 days before 2026-06-16
    File(
      '${tempDir.path}/app.20260614T120000Z.log',
    ).writeAsStringSync('recent'); // 2 days before 2026-06-16

    // A continuous size:1 rule forces a rotation on the first write, which
    // triggers retention enforcement. Fixed clock so age math is stable.
    await withClock(Clock.fixed(DateTime.utc(2026, 6, 16, 12)), () async {
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.size(1)],
        retention: FileRetention(maxAge: const Duration(days: 30)),
      );
      await printer.ready;
      printer.log(_line('trigger rotation'));
      await printer.close();
    });

    final names = archives(path);
    expect(
      names,
      isNot(contains('app.20260507T120000Z.log')),
      reason: '40-day-old archive pruned by maxAge',
    );
    expect(
      names,
      contains('app.20260614T120000Z.log'),
      reason: '2-day-old archive survives',
    );
  });

  test('maxFiles still caps archive count', () async {
    final path = '${tempDir.path}/app.log';
    final printer = RotatingFilePrinter(
      baseFilePathProvider: () => path,
      rotations: [FileRotation.size(1)],
      retention: FileRetention(maxFiles: 2),
    );
    await printer.ready;
    for (var i = 0; i < 5; i++) {
      printer.log(_line('line $i'));
    }
    await printer.close();

    expect(archives(path).length, 2);
  });

  test('maxAge and maxFiles together: age-prune then count-cap', () async {
    final path = '${tempDir.path}/app.log';
    // Seed three archives relative to the fixed clock at 2026-06-16T12:
    //  - 40 days old  -> pruned by maxAge (30d)
    //  - 2 days old   -> survives age, but becomes oldest-remaining
    //  - 1 day old    -> survives
    File('${tempDir.path}/app.20260507T120000Z.log').writeAsStringSync('old');
    File('${tempDir.path}/app.20260614T120000Z.log').writeAsStringSync('d2');
    File('${tempDir.path}/app.20260615T120000Z.log').writeAsStringSync('d1');

    await withClock(Clock.fixed(DateTime.utc(2026, 6, 16, 12)), () async {
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.size(1)],
        retention: FileRetention(maxFiles: 2, maxAge: const Duration(days: 30)),
      );
      await printer.ready;
      printer.log(
        _line('trigger'),
      ); // rotates -> creates app.20260616T120000Z.log
      await printer.close();
    });

    final names = archives(path);
    // 40-day-old removed by age; 2-day-old removed by count (oldest of the
    // three survivors once the fresh 20260616 archive joins).
    expect(names, isNot(contains('app.20260507T120000Z.log')));
    expect(names, isNot(contains('app.20260614T120000Z.log')));
    expect(names, contains('app.20260615T120000Z.log'));
    expect(names, contains('app.20260616T120000Z.log'));
    expect(names.length, 2);
  });

  test(
    'maxAge prunes a compressed .gz archive by filename timestamp',
    () async {
      final path = '${tempDir.path}/app.log';
      File(
        '${tempDir.path}/app.20260507T120000Z.log.gz',
      ).writeAsStringSync('gz-old'); // 40 days old
      File(
        '${tempDir.path}/app.20260615T120000Z.log.gz',
      ).writeAsStringSync('gz-recent'); // 1 day old

      await withClock(Clock.fixed(DateTime.utc(2026, 6, 16, 12)), () async {
        final printer = RotatingFilePrinter(
          baseFilePathProvider: () => path,
          rotations: [FileRotation.size(1)],
          retention: FileRetention(maxAge: const Duration(days: 30)),
        );
        await printer.ready;
        printer.log(_line('trigger'));
        await printer.close();
      });

      final names = archives(path);
      expect(
        names,
        isNot(contains('app.20260507T120000Z.log.gz')),
        reason: '40-day-old gz pruned by maxAge',
      );
      expect(
        names,
        contains('app.20260615T120000Z.log.gz'),
        reason: '1-day-old gz survives',
      );
    },
  );
}

LogEntry _line(String m) => LogEntry(
  level: LogLevel.info,
  message: m,
  object: LogMessage(m, String),
  loggerName: 'test',
  time: DateTime.utc(2026, 6, 16, 12),
);
