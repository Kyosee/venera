/// Pure decision logic for WebDAV data sync.
///
/// Every rule that decides sync DIRECTION (upload vs download), VERSION
/// numbers, or FILE selection lives here as a pure function so the whole
/// protocol is unit-testable and auditable in one place. IO, locking and UI
/// stay in `data_sync.dart`; nothing in this file may import app state.
///
/// ## Protocol summary
///
/// The server holds whole-library snapshots named
/// `<days-since-epoch>-<version>.<platform>.venera`. The numeric `version` is
/// the only ordering signal: higher wins (last-writer-wins). Devices track
/// their own position in `appdata.settings['dataVersion']`.
///
/// - Download: pull the highest-version backup if it is newer than local.
/// - Automatic upload: allowed only when the device is NOT behind the server
///   ([shouldSkipStaleUpload]); a stale device downloads to catch up instead
///   (#86). The new backup is stamped [nextSyncVersion] = above both local and
///   server max (#80).
/// - Explicit upload (manual button / local import / headless CLI): always
///   wins (`force`), preserving "this device is the source of truth" intent.
library;

/// The version number to stamp on a freshly uploaded WebDAV backup.
///
/// It must beat BOTH the local version and the highest version already on the
/// server. Deriving it from the local version alone let a device whose local
/// version trailed the server — a fresh device, or one that just imported a
/// foreign archive carrying an unrelated lower `dataVersion` — upload a backup
/// that the numeric version-based sync direction treated as "older", so other
/// devices never pulled it (issue #80). Pure function, easy to unit-test.
int nextSyncVersion(int localVersion, int remoteMaxVersion) =>
    (localVersion > remoteMaxVersion ? localVersion : remoteMaxVersion) + 1;

/// Whether an automatic upload must be skipped because this device is behind
/// the server, and should download first instead of overwriting newer remote
/// data with its own stale snapshot (issue #86).
///
/// Sync is a whole-library snapshot with last-writer-wins keyed on the numeric
/// version. If a device holding older data ([localVersion] < [remoteMaxVersion])
/// uploads, [nextSyncVersion] stamps that stale snapshot with `remoteMax + 1`,
/// making every other device pull the old data back and revert the newer data
/// they had. Guarding automatic uploads against this is the fix.
///
/// [force] uploads are explicit "publish, this is the source of truth" actions
/// (manual upload button, local-file import, headless CLI) and intentionally
/// bypass the guard, preserving the #80 "always wins" behavior. Pure function.
bool shouldSkipStaleUpload({
  required bool force,
  required int localVersion,
  required int remoteMaxVersion,
}) =>
    !force && remoteMaxVersion > localVersion;

/// Sanity ceiling for a believable sync version.
///
/// Versions advance by +1 per upload; even a decade of hourly uploads stays
/// under 100k. Foreign or corrupted archives, however, may carry a
/// milliseconds-since-epoch value (~1.7e12) in `dataVersion`. Accepting one
/// through the max-merge would permanently inflate the whole fleet's version
/// lineage, and a near-int64 value would overflow [nextSyncVersion] into a
/// negative number, inverting every subsequent direction decision.
const int maxReasonableDataVersion = 10000000;

/// Merges an incoming backup's `dataVersion` into the local one.
///
/// Normal rule: never move backwards — `max(local, incoming)` — so restoring
/// an older backup cannot make this device look "behind" and re-enter the
/// stale-overwrite loop. Additionally, an incoming version beyond
/// [maxReasonableDataVersion] is treated as foreign garbage and ignored (the
/// local version is kept). Pure function.
int mergeIncomingDataVersion(int localVersion, int incomingVersion) {
  if (incomingVersion < 0 || incomingVersion > maxReasonableDataVersion) {
    return localVersion;
  }
  return localVersion > incomingVersion ? localVersion : incomingVersion;
}

/// Highest backup version present among [fileNames], or 0 when none parse.
///
/// Compares by numeric version (via [RemoteBackupInfo.fromFileName]), never by
/// file-name string order — `…-10.venera` outranks `…-9.venera`. Skips null and
/// non-`.venera` entries. Pure function, easy to unit-test.
int maxBackupVersion(Iterable<String?> fileNames) {
  var max = 0;
  for (final name in fileNames) {
    if (name == null || !name.endsWith('.venera')) continue;
    final v = RemoteBackupInfo.fromFileName(name).version;
    if (v > max) max = v;
  }
  return max;
}

/// The backup to prune when capping server retention: the one with the LOWEST
/// numeric version (the oldest in the version lineage), or null when none parse.
///
/// Selecting by numeric version — never by lexicographic file-name order — is
/// essential here too: string order ranks `…-100.venera` below `…-99.venera`,
/// so a string sort would delete version 100, i.e. the NEWEST backup that every
/// other device syncs from. Skips null and non-`.venera` entries. Pure function.
String? lowestVersionBackup(Iterable<String?> fileNames) {
  String? lowest;
  int? lowestVersion;
  for (final name in fileNames) {
    if (name == null || !name.endsWith('.venera')) continue;
    final v = RemoteBackupInfo.fromFileName(name).version;
    if (lowestVersion == null || v < lowestVersion) {
      lowestVersion = v;
      lowest = name;
    }
  }
  return lowest;
}

/// Stale same-day backups from THIS platform that a new upload supersedes.
///
/// The uploader keeps at most one backup per day per platform. Selection is
/// restricted to the uploader's own [platform] on purpose: a bare
/// `startsWith("<day>-")` match would also delete a backup ANOTHER device
/// uploaded today — potentially the fleet's newest snapshot — and the deletion
/// used to happen before the replacement was written, so a failed write
/// permanently destroyed it. Callers must delete these only AFTER the new
/// backup is safely on the server. [newFileName] (the just-written backup) is
/// always excluded. Pure function.
List<String> sameDayOwnBackups({
  required Iterable<String?> fileNames,
  required String day,
  required String platform,
  required String newFileName,
}) {
  final result = <String>[];
  for (final name in fileNames) {
    if (name == null || !name.endsWith('.venera')) continue;
    if (name == newFileName) continue;
    if (!name.startsWith('$day-')) continue;
    if (RemoteBackupInfo.fromFileName(name).platform != platform) continue;
    result.add(name);
  }
  return result;
}

class RemoteBackupInfo {
  final String fileName;
  final int version;
  final String platform;
  final DateTime date;
  final DateTime? mTime;

  RemoteBackupInfo({
    required this.fileName,
    required this.version,
    required this.platform,
    required this.date,
    this.mTime,
  });

  /// The most precise timestamp available for display: prefer the WebDAV
  /// last-modified time (has hour/minute/second) and fall back to the
  /// day-precision date parsed from the file name.
  DateTime get effectiveDate => mTime ?? date;

  factory RemoteBackupInfo.fromFileName(String name, {DateTime? mTime}) {
    var parts = name.replaceAll('.venera', '').split('-');
    var leadingSegment = int.tryParse(parts.firstOrNull ?? '') ?? 0;
    var versionStr = parts.elementAtOrNull(1)?.split('.').first ?? '0';
    var version = int.tryParse(versionStr) ?? 0;
    var platform = 'unknown';
    var dotParts = parts.elementAtOrNull(1)?.split('.') ?? [];
    if (dotParts.length >= 2) {
      platform = dotParts[1];
    }
    return RemoteBackupInfo(
      fileName: name,
      version: version,
      platform: platform,
      date: _dateFromLeadingSegment(leadingSegment),
      mTime: mTime,
    );
  }

  static const int _msPerDay = 86400000;

  /// Upper bound of [DateTime.fromMillisecondsSinceEpoch]'s valid range.
  static const int _maxValidMs = 8640000000000000;

  /// Resolves the date encoded in a backup file name's leading segment.
  ///
  /// The segment is normally days-since-epoch (~5 digits). Older and foreign
  /// backups instead store a full `millisecondsSinceEpoch` (~13 digits); blindly
  /// multiplying that by [_msPerDay] overflows 64-bit int on Android and throws
  /// a RangeError that aborts the entire directory scan (issue #51). So multiply
  /// only when the value is small enough to be a real day count, otherwise treat
  /// it as milliseconds, and clamp so the constructor can never throw.
  static DateTime _dateFromLeadingSegment(int value) {
    var ms =
        value.abs() <= _maxValidMs ~/ _msPerDay ? value * _msPerDay : value;
    if (ms > _maxValidMs) ms = _maxValidMs;
    if (ms < -_maxValidMs) ms = -_maxValidMs;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
