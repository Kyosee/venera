import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_translation/worker_pool_selection.dart';

void main() {
  group('pickLeastBusyIndex', () {
    test('picks the worker with fewest pending tasks', () {
      expect(pickLeastBusyIndex([2, 0, 1]), 1);
      expect(pickLeastBusyIndex([3, 3, 1, 5]), 2);
    });
    test('ties resolve to the first', () {
      expect(pickLeastBusyIndex([0, 0, 0]), 0);
      expect(pickLeastBusyIndex([2, 2, 3]), 0);
    });
    test('single element', () {
      expect(pickLeastBusyIndex([7]), 0);
    });
  });
}
