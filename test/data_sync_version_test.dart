// Tests target the pure protocol module directly — no IO, no app state.
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/sync_protocol.dart';

void main() {
  group('RemoteBackupInfo.fromFileName', () {
    test('parses numeric version and platform', () {
      var info = RemoteBackupInfo.fromFileName('20240-7.android.venera');
      expect(info.version, 7);
      expect(info.platform, 'android');
    });

    test('two-digit version outranks single-digit by value, not string order',
        () {
      // Regression: file names were previously sorted lexicographically, which
      // ranks "...-9.venera" above "...-10.venera" and reversed the sync
      // direction once the version crossed into double digits.
      var v9 = RemoteBackupInfo.fromFileName('20240-9.windows.venera');
      var v10 = RemoteBackupInfo.fromFileName('20240-10.android.venera');

      // The bug: string comparison puts v9 first.
      expect('20240-9.windows.venera'.compareTo('20240-10.android.venera') > 0,
          isTrue);
      // The fix: numeric version correctly ranks v10 as newer.
      expect(v10.version > v9.version, isTrue);
    });

    test('malformed name falls back to version 0', () {
      expect(RemoteBackupInfo.fromFileName('garbage.venera').version, 0);
    });

    test('does not overflow on legacy millisecond-timestamp file names', () {
      // Regression for issue #51: older/foreign backups name files with a full
      // millisecondsSinceEpoch leading segment (13 digits) instead of
      // days-since-epoch (5 digits). The parser multiplied that by 86400000,
      // overflowing 64-bit int on Android and throwing
      // RangeError (millisecondsSinceEpoch) ... 6355900559421187072, which
      // aborted the whole directory scan and blocked WebDAV download.
      late RemoteBackupInfo info;
      expect(
        () => info =
            RemoteBackupInfo.fromFileName('1781595522559-3.android.venera'),
        returnsNormally,
      );
      expect(info.version, 3);
      expect(info.platform, 'android');
      // A millisecond leading segment must be read as milliseconds directly,
      // not multiplied. 1781595522559 ms since epoch == 2026-06-16.
      expect(info.date, DateTime.fromMillisecondsSinceEpoch(1781595522559));
    });

    test('day-precision file names still resolve to the right date', () {
      // 20621 days since epoch == 2026-06-16; the common path must be unchanged.
      var info = RemoteBackupInfo.fromFileName('20621-3.android.venera');
      expect(info.date, DateTime.fromMillisecondsSinceEpoch(20621 * 86400000));
      expect(info.version, 3);
    });

    test('leading segment that overflows int64 falls back to epoch, never throws',
        () {
      // 20 digits exceeds Dart's int range, so int.tryParse returns null and we
      // fall back to 0 (epoch) rather than crashing the directory scan.
      late RemoteBackupInfo info;
      expect(
        () => info = RemoteBackupInfo.fromFileName(
            '99999999999999999999-1.android.venera'),
        returnsNormally,
      );
      expect(info.version, 1);
      expect(info.date, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('parseable-but-out-of-range leading segment is clamped to the max date',
        () {
      // 9e15 parses as a valid int64 but exceeds DateTime's millisecond range.
      // This is the only case that exercises the `ms > _maxValidMs` clamp branch
      // of _dateFromLeadingSegment; without the clamp,
      // fromMillisecondsSinceEpoch(9000000000000000) would throw RangeError.
      late RemoteBackupInfo info;
      expect(
        () => info = RemoteBackupInfo.fromFileName(
            '9000000000000000-2.android.venera'),
        returnsNormally,
      );
      expect(info.version, 2);
      expect(info.date, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
    });
  });

  group('maxBackupVersion', () {
    test('returns 0 when there are no backups', () {
      expect(maxBackupVersion(const <String?>[]), 0);
    });

    test('ignores non-.venera and null names', () {
      expect(
        maxBackupVersion(['notes.txt', null, '20240-4.android.venera']),
        4,
      );
    });

    test('picks the highest version by number, not string order', () {
      // "…-10" must outrank "…-9"; lexicographic order would pick 9.
      expect(
        maxBackupVersion([
          '20240-9.windows.venera',
          '20240-10.android.venera',
          '20240-2.ios.venera',
        ]),
        10,
      );
    });
  });

  group('nextSyncVersion', () {
    test('steady state (local == remote max) is unchanged: max + 1', () {
      // Normal daily use keeps local aligned to the server, so this is the
      // common path and must stay identical to the old `local + 1`.
      expect(nextSyncVersion(7, 7), 8);
    });

    test('device behind the server jumps above the server max (#80)', () {
      // A fresh device, or one that just imported a foreign archive carrying an
      // unrelated lower dataVersion, has local < remote max. The upload must
      // still beat the server's highest version, otherwise other devices never
      // recognize it as newer. Old behavior (local + 1 = 4) silently lost.
      expect(nextSyncVersion(3, 20), 21);
    });

    test('device ahead of the server still advances from local', () {
      // Server backups were rotated/cleared away; the local copy is the source
      // of truth and keeps climbing from its own version.
      expect(nextSyncVersion(30, 12), 31);
    });

    test('fresh install with empty server starts at 1', () {
      expect(nextSyncVersion(0, 0), 1);
    });
  });

  group('lowestVersionBackup', () {
    test('returns null when there are no backups', () {
      expect(lowestVersionBackup(const <String?>[]), isNull);
    });

    test('ignores non-.venera and null names', () {
      expect(
        lowestVersionBackup(['notes.txt', null, '20240-7.android.venera']),
        '20240-7.android.venera',
      );
    });

    test('picks the lowest version, never the lexicographically smallest (#80)',
        () {
      // Retention rotation must prune the OLDEST (lowest version), never the
      // newest. Lexicographic order ranks "…-100" below "…-99", so a string
      // sort would delete version 100 — the latest backup. Numeric order keeps
      // it and prunes 99.
      expect(
        '20240-100.android.venera'.compareTo('20240-99.windows.venera') < 0,
        isTrue, // the trap: string order calls -100 the "smallest"
      );
      expect(
        lowestVersionBackup(
            ['20240-100.android.venera', '20240-99.windows.venera']),
        '20240-99.windows.venera',
      );
    });

    test('picks the lowest among several', () {
      expect(
        lowestVersionBackup([
          '20240-5.android.venera',
          '20240-3.ios.venera',
          '20240-12.windows.venera',
        ]),
        '20240-3.ios.venera',
      );
    });
  });

  group('shouldSkipStaleUpload', () {
    test('behind the server: an automatic upload is skipped (#86)', () {
      // The core #86 case. Device B still holds v5 while the server already has
      // A's newer v6. Auto-uploading would stamp B's stale data v7 and make
      // every device pull it back, reverting A. B must download instead.
      expect(
        shouldSkipStaleUpload(force: false, localVersion: 5, remoteMaxVersion: 6),
        isTrue,
      );
    });

    test('aligned with the server: normal auto-upload proceeds', () {
      // Steady state — local matches the server's newest. Nothing stale, so a
      // routine change uploads as usual.
      expect(
        shouldSkipStaleUpload(force: false, localVersion: 6, remoteMaxVersion: 6),
        isFalse,
      );
    });

    test('ahead of the server: auto-upload proceeds', () {
      // Server backups were rotated away; local is the source of truth and keeps
      // climbing. Not behind, so no skip.
      expect(
        shouldSkipStaleUpload(force: false, localVersion: 9, remoteMaxVersion: 4),
        isFalse,
      );
    });

    test('forced upload never skips, even when behind (#80 preserved)', () {
      // A manual "Upload" tap, a local-file import ("make this the source of
      // truth"), or the headless CLI must still win over a newer server backup.
      expect(
        shouldSkipStaleUpload(force: true, localVersion: 5, remoteMaxVersion: 6),
        isFalse,
      );
    });

    test('forced upload proceeds when aligned or ahead too', () {
      expect(
        shouldSkipStaleUpload(force: true, localVersion: 6, remoteMaxVersion: 6),
        isFalse,
      );
      expect(
        shouldSkipStaleUpload(force: true, localVersion: 9, remoteMaxVersion: 4),
        isFalse,
      );
    });

    test('fresh state (both zero) does not skip', () {
      // A brand-new device with an empty server is not "behind"; guarded by the
      // separate initial-sync check, an unforced upload here is not blocked by
      // this predicate.
      expect(
        shouldSkipStaleUpload(force: false, localVersion: 0, remoteMaxVersion: 0),
        isFalse,
      );
    });
  });

  group('mergeIncomingDataVersion', () {
    test('incoming newer wins', () {
      expect(mergeIncomingDataVersion(5, 8), 8);
    });

    test('incoming older never pulls local backwards', () {
      // Restoring an old backup must not make this device look "behind" and
      // re-enter the stale-overwrite loop.
      expect(mergeIncomingDataVersion(8, 5), 8);
    });

    test('implausibly huge foreign version is rejected', () {
      // A foreign archive carrying a milliseconds timestamp as dataVersion
      // would otherwise permanently inflate the whole fleet's versions — and a
      // near-int64 value would overflow nextSyncVersion into negative,
      // inverting every later direction decision.
      expect(mergeIncomingDataVersion(42, 1781595522559), 42);
      expect(mergeIncomingDataVersion(42, 9223372036854775807), 42);
    });

    test('negative incoming is rejected', () {
      expect(mergeIncomingDataVersion(42, -3), 42);
    });

    test('boundary: exactly the ceiling is accepted', () {
      expect(
        mergeIncomingDataVersion(1, maxReasonableDataVersion),
        maxReasonableDataVersion,
      );
      expect(mergeIncomingDataVersion(1, maxReasonableDataVersion + 1), 1);
    });
  });

  group('sameDayOwnBackups', () {
    test('selects only this platform, same day, excluding the new file', () {
      expect(
        sameDayOwnBackups(
          fileNames: [
            '20240-5.android.venera', // same day, own platform → prune
            '20240-7.windows.venera', // same day, OTHER device → keep!
            '20239-4.android.venera', // other day → keep
            '20240-8.android.venera', // the new upload itself → keep
            'notes.txt', null,
          ],
          day: '20240',
          platform: 'android',
          newFileName: '20240-8.android.venera',
        ),
        ['20240-5.android.venera'],
      );
    });

    test('another platform backup today is never treated as stale', () {
      // The old bare "day-" prefix match deleted whatever same-day file it
      // found first — including a backup another device uploaded today, which
      // could be the fleet's newest data.
      expect(
        sameDayOwnBackups(
          fileNames: ['20240-9.windows.venera'],
          day: '20240',
          platform: 'android',
          newFileName: '20240-10.android.venera',
        ),
        isEmpty,
      );
    });

    test('empty listing yields nothing', () {
      expect(
        sameDayOwnBackups(
          fileNames: const <String?>[],
          day: '20240',
          platform: 'android',
          newFileName: '20240-1.android.venera',
        ),
        isEmpty,
      );
    });
  });
}
