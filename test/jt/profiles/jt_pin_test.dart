import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/jt/jt_defaults.dart';
import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/util/fladder_config.dart';

void main() {
  group('JtPin hash', () {
    test('format v1\$iter\$salt\$hash, no PIN in clear', () {
      final stored = JtPin.hash('4821');
      final parts = stored.split('\$');
      expect(parts, hasLength(4));
      expect(parts[0], 'v1');
      expect(parts[1], '${JtPin.iterations}');
      expect(stored.contains('4821'), isFalse);
    });

    test('verify accepts the right PIN and rejects the others', () {
      final stored = JtPin.hash('0007');
      expect(JtPin.verify('0007', stored), isTrue);
      expect(JtPin.verify('0008', stored), isFalse);
      expect(JtPin.verify('7000', stored), isFalse);
      expect(JtPin.verify('', stored), isFalse);
    });

    test('salted: same PIN twice gives a different hash, both verify', () {
      final a = JtPin.hash('1234');
      final b = JtPin.hash('1234');
      expect(a, isNot(b));
      expect(JtPin.verify('1234', a), isTrue);
      expect(JtPin.verify('1234', b), isTrue);
    });

    test('PBKDF2-HMAC-SHA256 known answers (P="password", S="salt", c=1/2/4096)', () {
      String b64(String hex) => base64Encode([
            for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
          ]);
      final salt = base64Encode(utf8.encode('salt'));
      const vectors = {
        1: '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        2: 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        4096: 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      };
      vectors.forEach((c, hex) {
        expect(JtPin.verify('password', 'v1\$$c\$$salt\$${b64(hex)}'), isTrue, reason: 'c=$c');
        expect(JtPin.verify('passwore', 'v1\$$c\$$salt\$${b64(hex)}'), isFalse, reason: 'c=$c');
      });
    });

    test('deterministic with a fixed Random', () {
      final a = JtPin.hash('1111', random: Random(1));
      final b = JtPin.hash('1111', random: Random(1));
      expect(a, b);
    });

    test('unreadable stored values never verify', () {
      for (final bad in ['', 'v1', 'v2\$1\$AA==\$AA==', 'v1\$x\$AA==\$AA==', 'v1\$0\$AA==\$AA==', 'v1\$1\$!!\$AA==']) {
        expect(JtPin.verify('1234', bad), isFalse, reason: bad);
      }
    });

    test('only 4 digits are valid', () {
      expect(JtPin.isValidPin('1234'), isTrue);
      expect(JtPin.isValidPin('123'), isFalse);
      expect(JtPin.isValidPin('12345'), isFalse);
      expect(JtPin.isValidPin('12a4'), isFalse);
      expect(() => JtPin.hash('12a4'), throwsArgumentError);
    });
  });

  group('JtPinRecord', () {
    test('reads pinHash from CustomPrefs; empty = no PIN', () {
      expect(JtPinRecord.fromCustomPrefs({'pinHash': 'v1\$x'}).hasPin, isTrue);
      expect(JtPinRecord.fromCustomPrefs({'pinHash': ''}).hasPin, isFalse);
      expect(JtPinRecord.fromCustomPrefs({}).hasPin, isFalse);
      expect(JtPinRecord.fromCustomPrefs(null).hasPin, isFalse);
      expect(JtPinRecord.fromJson(const JtPinRecord('abc').toJson()).hash, 'abc');
    });
  });

  group('JtPinLockout (5 fouten -> 30 s)', () {
    final t0 = DateTime(2026, 10, 30, 20, 0, 0);

    test('four failures: not locked, attempts count down', () {
      var lock = const JtPinLockout();
      for (var i = 0; i < 4; i++) {
        lock = lock.fail(t0);
        expect(lock.isLocked(t0), isFalse);
      }
      expect(lock.attemptsLeft, 1);
    });

    test('fifth failure locks for exactly 30 s, then counts from zero again', () {
      var lock = const JtPinLockout();
      for (var i = 0; i < 5; i++) {
        lock = lock.fail(t0);
      }
      expect(lock.isLocked(t0), isTrue);
      expect(lock.remaining(t0), const Duration(seconds: 30));
      expect(lock.isLocked(t0.add(const Duration(seconds: 29))), isTrue);
      final later = t0.add(const Duration(seconds: 30));
      expect(lock.isLocked(later), isFalse);
      final normalized = lock.normalize(later);
      expect(normalized.lockedUntil, isNull);
      expect(normalized.attemptsLeft, JtPinLockout.maxAttempts);
    });

    test('survives a restart (json round trip)', () {
      var lock = const JtPinLockout();
      for (var i = 0; i < 5; i++) {
        lock = lock.fail(t0);
      }
      final restored = JtPinLockout.fromJson(lock.toJson());
      expect(restored.isLocked(t0.add(const Duration(seconds: 10))), isTrue);
      expect(JtPinLockout.fromJson(null).failures, 0);
      expect(JtPinLockout.fromJson('garbage').failures, 0);
    });
  });

  group('JtDefaults server', () {
    test('new install: fixed server, override and reset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      FladderConfig.baseUrl = null;
      JtDefaults.applyServer(prefs);
      expect(FladderConfig.baseUrl, 'https://tv.fam-thoelen.be');

      await JtDefaults.setServerOverride(prefs, ' https://andere.example ');
      expect(FladderConfig.baseUrl, 'https://andere.example');
      expect(JtDefaults.serverOverride(prefs), 'https://andere.example');

      await JtDefaults.setServerOverride(prefs, '');
      expect(FladderConfig.baseUrl, 'https://tv.fam-thoelen.be');
      expect(JtDefaults.serverOverride(prefs), isNull);
    });
  });
}
