import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:pointycastle/export.dart';

/// Dart-side crypto for the JS `crypto.subtle` polyfill (see assets/js/polyfill.js).
///
/// The JS side calls: sendMessage('__crypto', JSON {action, ...})
/// Dart returns a hex string. Actions:
///   digest      {algo, dataHex} -> hex digest
///   hmac        {hash, keyHex, dataHex} -> hex hmac
///   pbkdf2      {passwordHex, saltHex, iterations, keyLengthBits, hash} -> hex derived key
///   aesEncrypt  {mode, keyHex, ivHex, dataHex} -> hex ciphertext (GCM: ct||tag)
///   aesDecrypt  {mode, keyHex, ivHex, dataHex} -> hex plaintext (GCM: ct||tag)
///   random      {bytes} -> hex random bytes
///
/// Uses package:crypto for hashes/HMAC and package:pointycastle for AES/PBKDF2.
/// This covers AES-CBC (most providers) and AES-GCM (CineHD/CineJoy VidRock).
class CryptoBridge {
  static Future<String> handle(Map<String, dynamic> args) async {
    final action = args['action']?.toString() ?? '';
    switch (action) {
      case 'digest':
        return _digest(
          args['algo']?.toString() ?? 'SHA-256',
          _hex(args['dataHex']),
        );
      case 'hmac':
        return _hmac(
          args['hash']?.toString() ?? 'SHA-256',
          _hex(args['keyHex']),
          _hex(args['dataHex']),
        );
      case 'pbkdf2':
        return _pbkdf2(
          _hex(args['passwordHex']),
          _hex(args['saltHex']),
          int.tryParse(args['iterations']?.toString() ?? '1000') ?? 1000,
          int.tryParse(args['keyLengthBits']?.toString() ?? '256') ?? 256,
          args['hash']?.toString() ?? 'SHA-256',
        );
      case 'aesEncrypt':
        return _aes(
          true,
          args['mode']?.toString() ?? 'AES-CBC',
          _hex(args['keyHex']),
          _hex(args['ivHex']),
          _hex(args['dataHex']),
        );
      case 'aesDecrypt':
        return _aes(
          false,
          args['mode']?.toString() ?? 'AES-CBC',
          _hex(args['keyHex']),
          _hex(args['ivHex']),
          _hex(args['dataHex']),
        );
      case 'random':
        final n = int.tryParse(args['bytes']?.toString() ?? '16') ?? 16;
        final rnd = Random.secure();
        final bytes = Uint8List.fromList(
          List.generate(n, (_) => rnd.nextInt(256)),
        );
        return _toHex(bytes);
      default:
        throw Exception('Unknown crypto action: $action');
    }
  }

  static Uint8List _hex(dynamic v) {
    final s = v?.toString() ?? '';
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static crypto_pkg.Hash _hashFor(String name) {
    switch (name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '')) {
      case 'MD5':
        return crypto_pkg.md5;
      case 'SHA1':
        return crypto_pkg.sha1;
      case 'SHA256':
        return crypto_pkg.sha256;
      case 'SHA384':
        return crypto_pkg.sha384;
      case 'SHA512':
        return crypto_pkg.sha512;
      default:
        return crypto_pkg.sha256;
    }
  }

  static String _digest(String algo, Uint8List data) =>
      _toHex(Uint8List.fromList(_hashFor(algo).convert(data).bytes));

  static String _hmac(String hashName, Uint8List key, Uint8List data) {
    final hmac = crypto_pkg.Hmac(_hashFor(hashName), key);
    return _toHex(Uint8List.fromList(hmac.convert(data).bytes));
  }

  static String _pbkdf2(
    Uint8List password,
    Uint8List salt,
    int iterations,
    int keyLengthBits,
    String hashName,
  ) {
    final mac = hashName.toUpperCase().contains('SHA1')
        ? HMac(SHA1Digest(), 64)
        : hashName.toUpperCase().contains('SHA512')
        ? HMac(SHA512Digest(), 128)
        : HMac(SHA256Digest(), 64);
    final derivator = PBKDF2KeyDerivator(mac)
      ..init(Pbkdf2Parameters(salt, iterations, keyLengthBits ~/ 8));
    final key = derivator.process(password);
    return _toHex(key);
  }

  static String _aes(
    bool encrypt,
    String mode,
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    final m = mode.toUpperCase();
    if (m.contains('GCM')) return _aesGcm(encrypt, key, iv, data);
    if (m.contains('ECB')) return _aesBlock(encrypt, 'ECB', key, iv, data);
    return _aesBlock(encrypt, 'CBC', key, iv, data);
  }

  static String _aesBlock(
    bool encrypt,
    String blockMode,
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    // PKCS7 padding, matching WebCrypto / OpenSSL default padding used by providers.
    final PaddedBlockCipher cipher = blockMode == 'ECB'
        ? PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))
        : PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));

    if (blockMode == 'ECB') {
      cipher.init(
        encrypt,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(key),
          null,
        ),
      );
    } else {
      cipher.init(
        encrypt,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    }
    final out = cipher.process(data);
    return _toHex(out);
  }

  static String _aesGcm(
    bool encrypt,
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    // WebCrypto AES-GCM: data = ciphertext || tag(16) on decrypt, ct||tag on encrypt.
    final cipher = GCMBlockCipher(AESEngine());
    if (encrypt) {
      cipher.init(
        true,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
      final out = Uint8List(cipher.getOutputSize(data.length));
      var len = cipher.processBytes(data, 0, data.length, out, 0);
      len += cipher.doFinal(out, len);
      return _toHex(out.sublist(0, len));
    } else {
      if (data.length < 16) throw Exception('AES-GCM data too short');
      final ct = data.sublist(0, data.length - 16);
      final tag = data.sublist(data.length - 16);
      final combined = Uint8List.fromList([...ct, ...tag]);
      cipher.init(
        false,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
      final out = Uint8List(cipher.getOutputSize(combined.length));
      var len = cipher.processBytes(combined, 0, combined.length, out, 0);
      len += cipher.doFinal(out, len);
      return _toHex(out.sublist(0, len));
    }
  }
}
