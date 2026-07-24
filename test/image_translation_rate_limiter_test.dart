import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_translation/rate_limiter.dart';

void main() {
  group('classifyStatus', () {
    test('429 and 503 are rate limited', () {
      expect(classifyStatus(429), HttpErrorClass.rateLimited);
      expect(classifyStatus(503), HttpErrorClass.rateLimited);
    });
    test('other 4xx are client errors', () {
      expect(classifyStatus(400), HttpErrorClass.clientError);
      expect(classifyStatus(401), HttpErrorClass.clientError);
      expect(classifyStatus(404), HttpErrorClass.clientError);
    });
    test('5xx (except 503) are transient', () {
      expect(classifyStatus(500), HttpErrorClass.transient);
      expect(classifyStatus(502), HttpErrorClass.transient);
    });
  });

  group('parseRetryAfter', () {
    test('integer seconds', () {
      expect(parseRetryAfter('5'), const Duration(seconds: 5));
      expect(parseRetryAfter('0'), Duration.zero);
    });
    test('clamps to 300s', () {
      expect(parseRetryAfter('99999'), const Duration(seconds: 300));
    });
    test('null/empty/non-integer -> null', () {
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter('   '), isNull);
      expect(parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
    });
  });

  group('backoff', () {
    test('honors retryAfter, capped at 32s', () {
      expect(backoff(0, retryAfter: const Duration(seconds: 3)),
          const Duration(seconds: 3));
      expect(backoff(0, retryAfter: const Duration(seconds: 99)),
          const Duration(seconds: 32));
    });
    test('full jitter scales with attempt', () {
      // rng() == 0 -> zero; rng() == 0.5 -> half of exp base.
      expect(backoff(0, rng: () => 0.0), Duration.zero);
      expect(backoff(0, rng: () => 0.5), const Duration(milliseconds: 250));
      expect(backoff(1, rng: () => 0.5), const Duration(milliseconds: 500));
    });
  });

  group('ConcurrencyGate', () {
    test('caps concurrent holders and hands slot to waiter on release', () async {
      var gate = ConcurrencyGate((_) => 2);
      await gate.acquire('a');
      await gate.acquire('a');
      expect(gate.activeOf('a'), 2);
      var third = gate.acquire('a');
      var done = false;
      third.then((_) => done = true);
      await Future.delayed(Duration.zero);
      expect(done, false); // blocked
      gate.release('a');
      await Future.delayed(Duration.zero);
      expect(done, true); // woken
      expect(gate.activeOf('a'), 2);
    });

    test('separate buckets are independent', () async {
      var gate = ConcurrencyGate((_) => 1);
      await gate.acquire('a');
      var b = gate.acquire('b');
      await Future.delayed(Duration.zero);
      expect(gate.activeOf('b'), 1); // 'b' not blocked by 'a'
      await b;
    });
  });

  group('AimdController', () {
    test('starts at max, halves on rate limit, grows after cooldown', () {
      var aimd = AimdController(min: 1, max: 6, coolSuccesses: 2);
      expect(aimd.limitFor('x'), 6);
      aimd.onRateLimited('x');
      expect(aimd.limitFor('x'), 3); // 6 / 2
      // cooldown swallows the next 2 successes (no growth)
      aimd.onSuccess('x');
      aimd.onSuccess('x');
      expect(aimd.limitFor('x'), 3);
      // now grows additively, capped at max
      aimd.onSuccess('x');
      expect(aimd.limitFor('x'), 4);
    });
    test('never drops below min', () {
      var aimd = AimdController(min: 1, max: 4);
      aimd.onRateLimited('y');
      aimd.onRateLimited('y');
      aimd.onRateLimited('y');
      expect(aimd.limitFor('y'), 1);
    });
  });
}
