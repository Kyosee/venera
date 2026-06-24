import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart'
    show KeyParameter, AEADParameters, InvalidCipherTextException;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Transfer of WebDAV sync configuration between devices via a PIN-encrypted
/// QR code.
///
/// One device renders a `venera://sync` QR code that carries the whole config
/// encrypted with a short, one-time PIN; another device scans it and supplies
/// the PIN to recover the config. The entire payload (URL, account, password,
/// flags) is encrypted, so a bare scan of the QR reveals nothing.
///
/// Security note: the PIN has only ~10^6 possibilities. A captured QR image can
/// therefore be brute-forced offline; the 200k-round PBKDF2 only slows that to
/// roughly hours, not centuries. The PIN guards against a casual glance or
/// screenshot being read instantly — it is NOT strong protection against a
/// determined attacker who captures the image. Acceptable for moving your own
/// credentials between your own devices over a briefly-shown on-screen code.

/// Decoded sync configuration carried by the QR payload.
class SyncConfigPayload {
  const SyncConfigPayload({
    required this.url,
    required this.user,
    required this.pass,
    required this.autoSync,
    required this.disableSyncFields,
  });

  final String url;
  final String user;
  final String pass;
  final bool autoSync;
  final String disableSyncFields;

  Map<String, dynamic> toJson() => {
    'url': url,
    'user': user,
    'pass': pass,
    'autoSync': autoSync,
    'disableSyncFields': disableSyncFields,
  };

  factory SyncConfigPayload.fromJson(Map<String, dynamic> json) {
    return SyncConfigPayload(
      url: json['url']?.toString() ?? '',
      user: json['user']?.toString() ?? '',
      pass: json['pass']?.toString() ?? '',
      autoSync: json['autoSync'] == true,
      disableSyncFields: json['disableSyncFields']?.toString() ?? '',
    );
  }
}

/// Why decoding a sync-config QR failed. Lets the UI show a precise message.
enum SyncConfigTransferError {
  /// Not a `venera://sync` QR at all (wrong scheme/host, or unparseable).
  notSyncConfig,

  /// Recognized as ours but the payload version is newer than we understand.
  unsupportedVersion,

  /// Structurally broken payload (missing `d`, corrupt base64, too short).
  malformed,

  /// GCM authentication failed: wrong PIN, or the QR data was altered.
  wrongPinOrTampered,
}

class SyncConfigTransferException implements Exception {
  const SyncConfigTransferException(this.kind, [this.message = '']);

  final SyncConfigTransferError kind;
  final String message;

  @override
  String toString() => 'SyncConfigTransferException($kind): $message';
}

const _scheme = 'venera';
const _host = 'sync';
const _version = 1;
const _pbkdf2Iterations = 200000;
const _keyLengthBytes = 32; // AES-256
const _saltLengthBytes = 16;
const _ivLengthBytes = 12; // GCM standard nonce
const _gcmTagBits = 128;
const _minBlobLength = _saltLengthBytes + _ivLengthBytes + 16; // +tag

/// Generates a cryptographically-random 6-digit numeric PIN string.
String generateSyncPin() {
  final rnd = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buffer.write(rnd.nextInt(10));
  }
  return buffer.toString();
}

/// Quick, PIN-free check that [raw] is one of our sync-config QR codes, so a
/// scanner can accept it (and stop scanning) before prompting for the PIN.
bool isSyncConfigUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  return uri.scheme == _scheme &&
      uri.host == _host &&
      (uri.queryParameters['d']?.isNotEmpty ?? false);
}

/// Encrypts [payload] under [pin] and returns a `venera://sync?v=1&d=...` URI
/// suitable for rendering as a QR code. [pin] is typically [generateSyncPin].
String encodeSyncConfigToUri(SyncConfigPayload payload, String pin) {
  final plaintext = utf8.encode(jsonEncode(payload.toJson()));
  final salt = _randomBytes(_saltLengthBytes);
  final iv = _randomBytes(_ivLengthBytes);
  final key = _deriveKey(pin, salt);
  final ciphertext = _gcm(true, key, iv, Uint8List.fromList(plaintext));

  final blob = Uint8List(salt.length + iv.length + ciphertext.length);
  blob.setAll(0, salt);
  blob.setAll(salt.length, iv);
  blob.setAll(salt.length + iv.length, ciphertext);

  // Strip base64url padding so the value is unreserved-only and needs no
  // percent-encoding; the QR stays as short as possible.
  final d = base64Url.encode(blob).replaceAll('=', '');
  return '$_scheme://$_host?v=$_version&d=$d';
}

/// Decrypts a `venera://sync` URI produced by [encodeSyncConfigToUri] using
/// [pin]. Throws [SyncConfigTransferException] with a precise [kind] on any
/// failure (not ours, wrong version, malformed, or wrong PIN / tampered).
SyncConfigPayload decodeSyncConfigFromUri(String uri, String pin) {
  final parsed = Uri.tryParse(uri.trim());
  if (parsed == null || parsed.scheme != _scheme || parsed.host != _host) {
    throw const SyncConfigTransferException(
      SyncConfigTransferError.notSyncConfig,
    );
  }

  final versionText = parsed.queryParameters['v'];
  final version = int.tryParse(versionText ?? '');
  if (version == null) {
    throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
  }
  if (version > _version) {
    throw const SyncConfigTransferException(
      SyncConfigTransferError.unsupportedVersion,
    );
  }

  final d = parsed.queryParameters['d'];
  if (d == null || d.isEmpty) {
    throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
  }

  Uint8List blob;
  try {
    blob = base64Url.decode(_repad(d));
  } catch (_) {
    throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
  }
  if (blob.length < _minBlobLength) {
    throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
  }

  final salt = Uint8List.sublistView(blob, 0, _saltLengthBytes);
  final iv = Uint8List.sublistView(
    blob,
    _saltLengthBytes,
    _saltLengthBytes + _ivLengthBytes,
  );
  final ciphertext = Uint8List.sublistView(
    blob,
    _saltLengthBytes + _ivLengthBytes,
  );

  final key = _deriveKey(pin, salt);

  Uint8List plaintext;
  try {
    plaintext = _gcm(false, key, iv, ciphertext);
  } on InvalidCipherTextException {
    throw const SyncConfigTransferException(
      SyncConfigTransferError.wrongPinOrTampered,
    );
  } catch (_) {
    // Any other cipher failure on decrypt is, from the user's perspective, an
    // unusable code — surface it as the same actionable error.
    throw const SyncConfigTransferException(
      SyncConfigTransferError.wrongPinOrTampered,
    );
  }

  try {
    final json = jsonDecode(utf8.decode(plaintext));
    if (json is! Map) {
      throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
    }
    return SyncConfigPayload.fromJson(Map<String, dynamic>.from(json));
  } on SyncConfigTransferException {
    rethrow;
  } catch (_) {
    throw const SyncConfigTransferException(SyncConfigTransferError.malformed);
  }
}

Uint8List _randomBytes(int length) {
  final rnd = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

Uint8List _deriveKey(String pin, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLengthBytes));
  return derivator.process(Uint8List.fromList(utf8.encode(pin)));
}

/// Runs AES-256-GCM over [input]. On encrypt the output is ciphertext||tag; on
/// decrypt a bad tag throws [InvalidCipherTextException].
Uint8List _gcm(bool encrypt, Uint8List key, Uint8List iv, Uint8List input) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      encrypt,
      AEADParameters(KeyParameter(key), _gcmTagBits, iv, Uint8List(0)),
    );
  return cipher.process(input);
}

/// Restores base64url `=` padding that [encodeSyncConfigToUri] stripped.
String _repad(String value) {
  final remainder = value.length % 4;
  if (remainder == 0) return value;
  return value.padRight(value.length + (4 - remainder), '=');
}
