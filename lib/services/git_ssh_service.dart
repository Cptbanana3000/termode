import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'runtime_prefix_service.dart';

/// Represents an SSH Keypair managed by Termode.
class SshKeyPair {
  final String keyType;
  final String publicKey;
  final String publicKeyPath;
  final String privateKeyPath;
  final String fingerprint;
  final String comment;

  const SshKeyPair({
    required this.keyType,
    required this.publicKey,
    required this.publicKeyPath,
    required this.privateKeyPath,
    required this.fingerprint,
    required this.comment,
  });
}

/// Service that generates and manages SSH keys (~/.ssh/id_ed25519) in Termode.
class GitSshService {
  static final GitSshService _instance = GitSshService._internal();
  factory GitSshService() => _instance;
  GitSshService._internal();

  final RuntimePrefixService _prefix = RuntimePrefixService();

  // Test override hook
  String? overrideHomeDir;

  // Edwards25519 mathematical constants
  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _d = (-BigInt.from(121665) * _inv(BigInt.from(121666))) % _p;
  static final BigInt _sqrtMinusOne = _modPow(BigInt.from(2), (_p - BigInt.one) ~/ BigInt.from(4), _p);
  static final BigInt _by = (BigInt.from(4) * _inv(BigInt.from(5))) % _p;
  static final BigInt _bx = _recoverX(_by);
  static final _EdwardsPoint _basePoint = _EdwardsPoint(_bx, _by, BigInt.one, (_bx * _by) % _p);

  Future<Directory> _getSshDir() async {
    if (overrideHomeDir != null) {
      final dir = Directory('$overrideHomeDir/.ssh');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final paths = await _prefix.paths();
    final home = paths['home']!;
    final dir = Directory('$home/.ssh');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Checks whether an Ed25519 SSH keypair exists.
  Future<bool> hasKeyPair() async {
    final dir = await _getSshDir();
    final priv = File('${dir.path}/id_ed25519');
    final pub = File('${dir.path}/id_ed25519.pub');
    return await priv.exists() && await pub.exists();
  }

  /// Reads the public key if present.
  Future<String?> getPublicKey() async {
    final dir = await _getSshDir();
    final pub = File('${dir.path}/id_ed25519.pub');
    if (await pub.exists()) {
      return (await pub.readAsString()).trim();
    }
    return null;
  }

  /// Calculates and returns SHA-256 fingerprint for stored public key.
  Future<String?> getFingerprint() async {
    final pubKey = await getPublicKey();
    if (pubKey == null) return null;
    final parts = pubKey.trim().split(' ');
    if (parts.length >= 2) {
      final blob = base64.decode(parts[1]);
      return calculateSha256Fingerprint(blob);
    }
    return null;
  }

  /// Deletes the SSH keypair.
  Future<bool> deleteKeyPair() async {
    final dir = await _getSshDir();
    final priv = File('${dir.path}/id_ed25519');
    final pub = File('${dir.path}/id_ed25519.pub');
    bool deleted = false;
    if (await priv.exists()) {
      await priv.delete();
      deleted = true;
    }
    if (await pub.exists()) {
      await pub.delete();
      deleted = true;
    }
    return deleted;
  }

  /// Generates a new cryptographic Ed25519 keypair and writes OpenSSH formatted files.
  Future<SshKeyPair> generateKeyPair({
    String comment = 'termode@android',
    bool overwrite = false,
  }) async {
    final dir = await _getSshDir();
    final privFile = File('${dir.path}/id_ed25519');
    final pubFile = File('${dir.path}/id_ed25519.pub');
    final configFile = File('${dir.path}/config');

    if (!overwrite && (await privFile.exists() || await pubFile.exists())) {
      throw StateError('SSH key already exists at ${privFile.path}. Use overwrite: true to replace.');
    }

    // 1. Generate 32-byte secure seed
    final rng = Random.secure();
    final seed = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }

    // 2. Derive Ed25519 clamped scalar
    final clamped = Uint8List.fromList(seed);
    clamped[0] &= 248;
    clamped[31] &= 127;
    clamped[31] |= 64;

    var scalar = BigInt.zero;
    for (int i = 31; i >= 0; i--) {
      scalar = (scalar << 8) | BigInt.from(clamped[i]);
    }

    // 3. Compute public point and 32-byte public key
    final pubPoint = _basePoint.mul(scalar);
    final pubBytes = pubPoint.encode();

    // 4. Format OpenSSH public key blob:
    // string "ssh-ed25519", string pubkey
    final pubBlobBuf = BytesBuilder();
    _writeSshString(pubBlobBuf, 'ssh-ed25519');
    _writeSshBytes(pubBlobBuf, pubBytes);
    final pubBlob = pubBlobBuf.toBytes();

    final pubB64 = base64.encode(pubBlob);
    final openSshPublic = 'ssh-ed25519 $pubB64 $comment';

    // 5. Format OpenSSH private key blob:
    final privBlobBuf = BytesBuilder();
    // Auth magic header
    privBlobBuf.add(utf8.encode('openssh-key-v1\x00'));
    // ciphername, kdfname, kdfoptions
    _writeSshString(privBlobBuf, 'none');
    _writeSshString(privBlobBuf, 'none');
    _writeSshBytes(privBlobBuf, Uint8List(0));
    // number of keys = 1
    _writeSshUint32(privBlobBuf, 1);
    // public key blob
    _writeSshBytes(privBlobBuf, pubBlob);

    // Private key body
    final checkInt = rng.nextInt(0x7fffffff);
    final bodyBuf = BytesBuilder();
    _writeSshUint32(bodyBuf, checkInt);
    _writeSshUint32(bodyBuf, checkInt);
    _writeSshString(bodyBuf, 'ssh-ed25519');
    _writeSshBytes(bodyBuf, pubBytes);

    // Ed25519 private key is 64 bytes: 32 bytes seed + 32 bytes pub
    final priv64 = Uint8List(64);
    priv64.setRange(0, 32, seed);
    priv64.setRange(32, 64, pubBytes);
    _writeSshBytes(bodyBuf, priv64);
    _writeSshString(bodyBuf, comment);

    // Padding to 8-byte block size
    final bodyBytes = bodyBuf.toBytes();
    final padLen = 8 - (bodyBytes.length % 8);
    final pad = Uint8List(padLen);
    for (int i = 0; i < padLen; i++) {
      pad[i] = i + 1;
    }
    final paddedBodyBuf = BytesBuilder();
    paddedBodyBuf.add(bodyBytes);
    paddedBodyBuf.add(pad);

    _writeSshBytes(privBlobBuf, paddedBodyBuf.toBytes());

    final privB64 = base64.encode(privBlobBuf.toBytes());
    final openSshPrivate = _formatPem(privB64, 'OPENSSH PRIVATE KEY');

    // 6. Write files with secure permissions
    await privFile.writeAsString('$openSshPrivate\n', flush: true);
    await pubFile.writeAsString('$openSshPublic\n', flush: true);

    // Default ssh config
    if (!await configFile.exists()) {
      await configFile.writeAsString(
        'Host github.com\n'
        '  IdentityFile ~/.ssh/id_ed25519\n'
        '  StrictHostKeyChecking accept-new\n\n'
        'Host gitlab.com\n'
        '  IdentityFile ~/.ssh/id_ed25519\n'
        '  StrictHostKeyChecking accept-new\n',
        flush: true,
      );
    }

    // Set POSIX permissions on non-Windows platforms
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', privFile.path]);
        await Process.run('chmod', ['644', pubFile.path]);
        await Process.run('chmod', ['600', configFile.path]);
      } catch (_) {}
    }

    final fingerprint = calculateSha256Fingerprint(pubBlob);

    return SshKeyPair(
      keyType: 'ED25519',
      publicKey: openSshPublic,
      publicKeyPath: pubFile.path,
      privateKeyPath: privFile.path,
      fingerprint: fingerprint,
      comment: comment,
    );
  }

  /// Calculates the SHA-256 fingerprint for a public key blob (e.g. SHA256:abc...).
  static String calculateSha256Fingerprint(List<int> pubBlob) {
    final shaHex = sha256Hex(pubBlob);
    final bytes = <int>[];
    for (int i = 0; i < shaHex.length; i += 2) {
      bytes.add(int.parse(shaHex.substring(i, i + 2), radix: 16));
    }
    var b64 = base64.encode(bytes);
    while (b64.endsWith('=')) {
      b64 = b64.substring(0, b64.length - 1);
    }
    return 'SHA256:$b64';
  }

  /// Pure Dart SHA-256 implementation
  static String sha256Hex(List<int> input) {
    final bytes = List<int>.from(input);
    final bitLength = bytes.length * 8;
    bytes.add(0x80);
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      bytes.add((bitLength >> shift) & 0xff);
    }

    final k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

    final w = List<int>.filled(64, 0);
    for (var chunk = 0; chunk < bytes.length; chunk += 64) {
      for (var i = 0; i < 16; i++) {
        final offset = chunk + (i * 4);
        w[i] = ((bytes[offset] & 0xff) << 24) |
            ((bytes[offset + 1] & 0xff) << 16) |
            ((bytes[offset + 2] & 0xff) << 8) |
            (bytes[offset + 3] & 0xff);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ (~e & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = StringBuffer();
    for (final v in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      out.write(v.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }

  // --- Helper serialization routines ---

  static void _writeSshUint32(BytesBuilder buf, int v) {
    buf.add([
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ]);
  }

  static void _writeSshBytes(BytesBuilder buf, List<int> b) {
    _writeSshUint32(buf, b.length);
    buf.add(b);
  }

  static void _writeSshString(BytesBuilder buf, String s) {
    _writeSshBytes(buf, utf8.encode(s));
  }

  static String _formatPem(String b64, String label) {
    final sb = StringBuffer();
    sb.writeln('-----BEGIN $label-----');
    for (int i = 0; i < b64.length; i += 70) {
      final end = (i + 70 < b64.length) ? i + 70 : b64.length;
      sb.writeln(b64.substring(i, end));
    }
    sb.write('-----END $label-----');
    return sb.toString();
  }

  // --- Edwards25519 Curve Arithmetic ---

  static BigInt _inv(BigInt z) => _modPow(z, _p - BigInt.two, _p);

  static BigInt _modPow(BigInt base, BigInt exp, BigInt mod) {
    var res = BigInt.one;
    var b = base % mod;
    var e = exp;
    while (e > BigInt.zero) {
      if (e.isOdd) res = (res * b) % mod;
      e = e >> 1;
      b = (b * b) % mod;
    }
    return res;
  }

  static BigInt _recoverX(BigInt y) {
    final u = (y * y - BigInt.one) % _p;
    final v = (_d * y * y + BigInt.one) % _p;
    var x = (u * _inv(v)) % _p;
    var res = _modPow(x, (_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
    if ((res * res - x) % _p != BigInt.zero) {
      res = (res * _sqrtMinusOne) % _p;
    }
    if (res.isOdd) res = (_p - res) % _p;
    return res;
  }
}

class _EdwardsPoint {
  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;
  const _EdwardsPoint(this.x, this.y, this.z, this.t);

  static final _EdwardsPoint zero = _EdwardsPoint(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);

  _EdwardsPoint add(_EdwardsPoint other) {
    final a = ((y - x) * (other.y - other.x)) % GitSshService._p;
    final b = ((y + x) * (other.y + other.x)) % GitSshService._p;
    final c = (BigInt.two * GitSshService._d * t * other.t) % GitSshService._p;
    final d = (BigInt.two * z * other.z) % GitSshService._p;
    final e = (b - a) % GitSshService._p;
    final f = (d - c) % GitSshService._p;
    final g = (d + c) % GitSshService._p;
    final h = (b + a) % GitSshService._p;
    return _EdwardsPoint((e * f) % GitSshService._p, (g * h) % GitSshService._p, (f * g) % GitSshService._p, (e * h) % GitSshService._p);
  }

  _EdwardsPoint doublePoint() {
    final a = (x * x) % GitSshService._p;
    final b = (y * y) % GitSshService._p;
    final c = (BigInt.two * z * z) % GitSshService._p;
    final h = (a + b) % GitSshService._p;
    final e = (h - ((x + y) * (x + y)) % GitSshService._p) % GitSshService._p;
    final g = (a - b) % GitSshService._p;
    final f = (c + g) % GitSshService._p;
    return _EdwardsPoint((e * f) % GitSshService._p, (g * h) % GitSshService._p, (f * g) % GitSshService._p, (e * h) % GitSshService._p);
  }

  _EdwardsPoint mul(BigInt scalar) {
    var r = zero;
    var base = this;
    var s = scalar;
    while (s > BigInt.zero) {
      if (s.isOdd) r = r.add(base);
      base = base.doublePoint();
      s = s >> 1;
    }
    return r;
  }

  Uint8List encode() {
    final invZ = GitSshService._inv(z);
    final px = (x * invZ) % GitSshService._p;
    final py = (y * invZ) % GitSshService._p;
    final bytes = Uint8List(32);
    var tempY = py;
    for (int i = 0; i < 32; i++) {
      bytes[i] = (tempY & BigInt.from(0xff)).toInt();
      tempY = tempY >> 8;
    }
    if (px.isOdd) {
      bytes[31] |= 0x80;
    }
    return bytes;
  }
}
