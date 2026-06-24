import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/sync_config_transfer.dart';

void main() {
  const payload = SyncConfigPayload(
    url: 'https://dav.example.com/venera/',
    user: 'alice@example.com',
    pass: r'p@$$w0rd with spaces & 符号',
    autoSync: true,
    disableSyncFields: 'history,read_later',
  );

  test('round-trips with the correct PIN', () {
    final uri = encodeSyncConfigToUri(payload, '482917');
    final decoded = decodeSyncConfigFromUri(uri, '482917');
    expect(decoded.url, payload.url);
    expect(decoded.user, payload.user);
    expect(decoded.pass, payload.pass);
    expect(decoded.autoSync, payload.autoSync);
    expect(decoded.disableSyncFields, payload.disableSyncFields);
  });

  test('produces a venera://sync URI recognized by isSyncConfigUri', () {
    final uri = encodeSyncConfigToUri(payload, '000000');
    expect(uri.startsWith('venera://sync?'), isTrue);
    expect(isSyncConfigUri(uri), isTrue);
    expect(isSyncConfigUri('https://example.com'), isFalse);
    expect(isSyncConfigUri('venera://comic?id=1'), isFalse);
    expect(isSyncConfigUri('not a uri at all'), isFalse);
  });

  test('different generations use fresh salt/iv (ciphertext differs)', () {
    final a = encodeSyncConfigToUri(payload, '123456');
    final b = encodeSyncConfigToUri(payload, '123456');
    expect(a, isNot(equals(b)));
  });

  test('wrong PIN throws wrongPinOrTampered', () {
    final uri = encodeSyncConfigToUri(payload, '111111');
    expect(
      () => decodeSyncConfigFromUri(uri, '222222'),
      throwsA(
        isA<SyncConfigTransferException>().having(
          (e) => e.kind,
          'kind',
          SyncConfigTransferError.wrongPinOrTampered,
        ),
      ),
    );
  });

  test('tampered payload throws (auth fails or malformed)', () {
    final uri = encodeSyncConfigToUri(payload, '111111');
    // Flip the last character of the d= value.
    final flipped = uri.substring(0, uri.length - 1) +
        (uri.endsWith('A') ? 'B' : 'A');
    expect(
      () => decodeSyncConfigFromUri(flipped, '111111'),
      throwsA(
        isA<SyncConfigTransferException>().having(
          (e) => e.kind,
          'kind',
          anyOf(
            SyncConfigTransferError.wrongPinOrTampered,
            SyncConfigTransferError.malformed,
          ),
        ),
      ),
    );
  });

  test('non-venera string throws notSyncConfig', () {
    expect(
      () => decodeSyncConfigFromUri('https://example.com/x', '111111'),
      throwsA(
        isA<SyncConfigTransferException>().having(
          (e) => e.kind,
          'kind',
          SyncConfigTransferError.notSyncConfig,
        ),
      ),
    );
  });

  test('unsupported future version throws unsupportedVersion', () {
    final uri = encodeSyncConfigToUri(payload, '111111');
    final bumped = uri.replaceFirst('v=1', 'v=2');
    expect(
      () => decodeSyncConfigFromUri(bumped, '111111'),
      throwsA(
        isA<SyncConfigTransferException>().having(
          (e) => e.kind,
          'kind',
          SyncConfigTransferError.unsupportedVersion,
        ),
      ),
    );
  });

  test('generateSyncPin yields six digits', () {
    for (var i = 0; i < 50; i++) {
      final pin = generateSyncPin();
      expect(pin, hasLength(6));
      expect(RegExp(r'^\d{6}$').hasMatch(pin), isTrue);
    }
  });
}
