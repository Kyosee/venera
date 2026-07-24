import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_translation/ordered_group_committer.dart';

GroupResult r(int done) => GroupResult(done, 0, <int>{});

void main() {
  group('OrderedGroupCommitter', () {
    test('in-order records commit immediately', () {
      var c = OrderedGroupCommitter(0);
      expect(c.record(0, r(1)).map((g) => g.done), [1]);
      expect(c.record(1, r(2)).map((g) => g.done), [2]);
      expect(c.nextCommitIndex, 2);
      expect(c.hasPending, false);
    });

    test('out-of-order buffers until the prefix is contiguous', () {
      var c = OrderedGroupCommitter(0);
      expect(c.record(1, r(2)), isEmpty); // 1 arrives before 0
      expect(c.hasPending, true);
      var flushed = c.record(0, r(1)); // now 0,1 both commit in order
      expect(flushed.map((g) => g.done), [1, 2]);
      expect(c.nextCommitIndex, 2);
      expect(c.hasPending, false);
    });

    test('gap: index 2 waits for 0 and 1', () {
      var c = OrderedGroupCommitter(0);
      expect(c.record(2, r(3)), isEmpty);
      expect(c.record(0, r(1)).map((g) => g.done), [1]);
      expect(c.record(1, r(2)).map((g) => g.done), [2, 3]);
      expect(c.nextCommitIndex, 3);
    });

    test('carries failedPages and failed counts through', () {
      var c = OrderedGroupCommitter(0);
      var flushed = c.record(0, GroupResult(1, 1, {5}));
      expect(flushed.single.failed, 1);
      expect(flushed.single.failedPages, {5});
    });
  });
}
