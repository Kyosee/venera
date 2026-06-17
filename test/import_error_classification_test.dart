import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/data.dart';

void main() {
  group('importErrorMessageKey', () {
    test('classifies out-of-space failures', () {
      // The redundant copy + full extraction can exhaust internal storage on a
      // large (issue #52) import; surface a clear message instead of raw errno.
      expect(
        importErrorMessageKey(
          'FileSystemException: No space left on device, errno = 28',
        ),
        'Not enough storage space',
      );
      expect(
        importErrorMessageKey('write failed (os error 28)'),
        'Not enough storage space',
      );
    });

    test('classifies corrupted / unsupported archives', () {
      expect(
        importErrorMessageKey('Exception: failed to open zip'),
        'Backup file is corrupted or unsupported',
      );
      expect(
        importErrorMessageKey('invalid archive: bad central directory'),
        'Backup file is corrupted or unsupported',
      );
    });

    test('returns null for unrecognized errors', () {
      expect(importErrorMessageKey('some unrelated failure'), isNull);
    });
  });
}
