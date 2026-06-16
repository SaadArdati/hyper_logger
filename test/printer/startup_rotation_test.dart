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
    tempDir = Directory.systemTemp.createTempSync('hl_startup_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // Counts rotated archives next to base (e.g. app.<ts>.log[.gz]).
  int archiveCount(String basePath) {
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
        .where((f) => re.hasMatch(p.basename(f.path)))
        .length;
  }

  test(
    'onStart() archives a non-empty existing file and opens fresh',
    () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('old run content\n');

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.onStart()],
      );
      await printer.ready;
      await printer.close();

      expect(archiveCount(path), 1, reason: 'old content archived');
      final base = File(path);
      final contents = base.existsSync() ? base.readAsStringSync() : '';
      expect(contents, isNot(contains('old run content')));
    },
  );

  test('two onStart opens produce two archives', () async {
    final path = '${tempDir.path}/app.log';
    // Seed content so the FIRST open has something to archive. (An onStart
    // open against an absent/empty file archives nothing.)
    File(path).writeAsStringSync('seed content\n');

    final p1 = RotatingFilePrinter(
      baseFilePathProvider: () => path,
      rotations: [FileRotation.onStart()],
    );
    await p1.ready;
    p1.log(_line('run one')); // leaves the base file non-empty for run two
    await p1.close();

    final p2 = RotatingFilePrinter(
      baseFilePathProvider: () => path,
      rotations: [FileRotation.onStart()],
    );
    await p2.ready;
    await p2.close();

    expect(archiveCount(path), 2);
  });

  test(
    'onStart() on an absent/empty file does not create an archive',
    () async {
      final path = '${tempDir.path}/app.log';

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.onStart()],
      );
      await printer.ready;
      await printer.close();

      expect(archiveCount(path), 0);
    },
  );

  test(
    'onStart(discard: true) removes old content without archiving',
    () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('discard me\n');

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.onStart(discard: true)],
      );
      await printer.ready;
      await printer.close();

      expect(archiveCount(path), 0, reason: 'discard produces no archive');
      final base = File(path);
      final contents = base.existsSync() ? base.readAsStringSync() : '';
      expect(contents, isNot(contains('discard me')));
    },
  );

  test(
    'size+onStart only rotates when existing file exceeds threshold',
    () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('x' * 10); // 10 bytes

      // Threshold 1000 > 10 => no rotation.
      final small = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.size(1000, cadence: Cadence.onStart)],
      );
      await small.ready;
      await small.close();
      expect(archiveCount(path), 0);

      // Grow file past threshold, reopen with threshold 5 => rotates.
      File(path).writeAsStringSync('y' * 50);
      final big = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.size(5, cadence: Cadence.onStart)],
      );
      await big.ready;
      await big.close();
      expect(archiveCount(path), 1);
    },
  );

  test('multiple onStart rules: first in list order wins (archive before '
      'discard)', () async {
    final path = '${tempDir.path}/app.log';
    File(path).writeAsStringSync('keep me\n');

    // Archive rule first => archives; the later discard rule is never reached.
    final printer = RotatingFilePrinter(
      baseFilePathProvider: () => path,
      rotations: [FileRotation.onStart(), FileRotation.onStart(discard: true)],
    );
    await printer.ready;
    await printer.close();

    expect(archiveCount(path), 1, reason: 'first (archive) rule wins');
  });

  test(
    'onStart(discard) with compress produces neither archive nor .gz',
    () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('discard me\n');

      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [FileRotation.onStart(discard: true)],
        retention: FileRetention(compress: true),
      );
      await printer.ready;
      await printer.close();

      expect(archiveCount(path), 0);
      final gz = Directory(p.dirname(path))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gz'))
          .toList();
      expect(gz, isEmpty, reason: 'discard deletes, never compresses');
    },
  );

  test('interval+onStart rotates when the existing file age exceeds the '
      'interval', () async {
    final path = '${tempDir.path}/app.log';
    File(path).writeAsStringSync('old run\n');
    final mtime = File(path).lastModifiedSync();

    // Fixed clock 2h after the file's mtime; interval 1h => should rotate.
    await withClock(Clock.fixed(mtime.add(const Duration(hours: 2))), () async {
      final printer = RotatingFilePrinter(
        baseFilePathProvider: () => path,
        rotations: [
          FileRotation.interval(
            const Duration(hours: 1),
            cadence: Cadence.onStart,
          ),
        ],
      );
      await printer.ready;
      await printer.close();
    });

    expect(archiveCount(path), 1);
  });

  test(
    'interval+onStart does NOT rotate when the existing file is fresh',
    () async {
      final path = '${tempDir.path}/app.log';
      File(path).writeAsStringSync('fresh\n');
      final mtime = File(path).lastModifiedSync();

      // Fixed clock 1min after mtime; interval 1h => should NOT rotate.
      await withClock(
        Clock.fixed(mtime.add(const Duration(minutes: 1))),
        () async {
          final printer = RotatingFilePrinter(
            baseFilePathProvider: () => path,
            rotations: [
              FileRotation.interval(
                const Duration(hours: 1),
                cadence: Cadence.onStart,
              ),
            ],
          );
          await printer.ready;
          await printer.close();
        },
      );

      expect(archiveCount(path), 0);
    },
  );

  test('continuous union: size + interval rules coexist in one printer '
      '(old API forbade combining)', () async {
    final path = '${tempDir.path}/app.log';
    final printer = RotatingFilePrinter(
      baseFilePathProvider: () => path,
      rotations: [
        FileRotation.size(1),
        FileRotation.interval(const Duration(hours: 1)),
      ],
    );
    await printer.ready;
    printer.log(_line('x')); // size(1) fires on the write
    await printer.close();

    expect(archiveCount(path), greaterThanOrEqualTo(1));
  });
}

LogEntry _line(String m) => LogEntry(
  level: LogLevel.info,
  message: m,
  object: LogMessage(m, String),
  loggerName: 'test',
  time: DateTime.utc(2026, 6, 16, 12),
);
