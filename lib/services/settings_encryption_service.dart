import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SettingsEncryptionService {
  SettingsEncryptionService({
    AesGcm? cipher,
    Hkdf? hkdf,
  }) : _cipher = cipher ?? AesGcm.with256bits(),
       _hkdf =
           hkdf ??
           Hkdf(
             hmac: Hmac.sha256(),
             outputLength: 32,
           );

  final AesGcm _cipher;
  final Hkdf _hkdf;

  static const int _formatVersion = 1;

  // Cross-device decryption requires a shared secret.
  // Put it in `.env` as SETTINGS_ENC_SECRET (min 16 chars).
  String? _readSecret() {
    try {
      final raw = dotenv.env['SETTINGS_ENC_SECRET']?.trim();
      if (raw == null || raw.length < 16) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<String?> encryptApiKey({
    required String uid,
    required String apiKey,
  }) async {
    final secret = _readSecret();
    if (secret == null) {
      debugPrint(
        'SETTINGS_ENC_SECRET missing/short; API key sync disabled.',
      );
      return null;
    }

    final key = await _deriveKey(uid: uid, secret: secret);
    final nonce = _randomBytes(12);
    final box = await _cipher.encrypt(
      utf8.encode(apiKey),
      secretKey: key,
      nonce: nonce,
    );

    final payload = <String, dynamic>{
      'v': _formatVersion,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    };
    return jsonEncode(payload);
  }

  Future<String?> decryptApiKey({
    required String uid,
    required String encoded,
  }) async {
    final secret = _readSecret();
    if (secret == null) {
      debugPrint(
        'SETTINGS_ENC_SECRET missing/short; API key sync disabled.',
      );
      return null;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(encoded);
      payload = Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }

    final v = payload['v'];
    if (v is! num || v.toInt() != _formatVersion) {
      return null;
    }

    final nonceB64 = payload['n'];
    final cipherB64 = payload['c'];
    final macB64 = payload['m'];
    if (nonceB64 is! String || cipherB64 is! String || macB64 is! String) {
      return null;
    }

    final nonce = base64Decode(nonceB64);
    final cipherText = base64Decode(cipherB64);
    final macBytes = base64Decode(macB64);

    final key = await _deriveKey(uid: uid, secret: secret);
    try {
      final clear = await _cipher.decrypt(
        SecretBox(
          cipherText,
          nonce: nonce,
          mac: Mac(macBytes),
        ),
        secretKey: key,
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveKey({
    required String uid,
    required String secret,
  }) async {
    final salt = utf8.encode('agenix.settings.$uid');
    final info = utf8.encode('agenix.settings.aesgcm.v$_formatVersion');
    return _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
      info: info,
    );
  }

  Uint8List _randomBytes(int length) {
    final r = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }
}
