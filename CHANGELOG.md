## 0.2.0

### Breaking

- `RotatingFilePrinter` rotation API redesigned. The single
  `rotationConfig: FileRotationConfig.…` parameter is replaced by:
  - `rotations: List<FileRotation>` — a list of rotation rules, each a
    trigger (`FileRotation.size` / `.interval` / `.daily` / `.onStart`)
    crossed with a `Cadence` (`continuous`, checked on every write, or
    `onStart`, checked once when the file opens). Rules compose as a union
    (the first to fire rotates), so size **and** time triggers can now be
    combined. An empty list (the default) appends forever.
  - `retention: FileRetention?` — shared archive policy (`maxFiles`,
    `maxAge`, `compress`). `maxBytes`/`interval` now live on the rule;
    retention knobs moved here.
  - `FileRotationConfig` is removed.

  Migration: `FileRotationConfig.size(maxBytes: N, maxFiles: M, compress: c)`
  → `rotations: [FileRotation.size(N)], retention: FileRetention(maxFiles: M, compress: c)`;
  `FileRotationConfig.interval(interval: D)` → `rotations: [FileRotation.interval(D)]`.

### Added

- `FileRotation.onStart({bool discard})` — rotate (archive) or discard the
  existing log on every process start, e.g. a fresh `server.log` per run.
- `FileRetention.maxAge` — delete rotated archives older than a given
  duration (age parsed from the archive's filename timestamp), pruned on
  each rotation alongside `maxFiles`.

## 0.1.0

- Initial public release.
