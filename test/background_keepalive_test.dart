import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/background_keepalive.dart';

void main() {
  group('formatTaskStatus', () {
    test('appends detail after the title', () {
      expect(
        formatTaskStatus(title: 'My Folder', detail: '3/10'),
        'My Folder · 3/10',
      );
    });

    test('falls back to title only when detail is null', () {
      expect(formatTaskStatus(title: 'My Folder'), 'My Folder');
    });

    test('falls back to title only when detail is empty/blank', () {
      expect(formatTaskStatus(title: 'My Folder', detail: ''), 'My Folder');
      expect(formatTaskStatus(title: 'My Folder', detail: '   '), 'My Folder');
    });

    test('trims surrounding whitespace from detail', () {
      expect(
        formatTaskStatus(title: 'Comic', detail: '  Extracting  '),
        'Comic · Extracting',
      );
    });
  });
}
