import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pincode van een profiel (WP3.1): 4 cijfers, bewaard als gezouten hash.
///
/// De hash staat in de Jellyfin-DisplayPreferences van de gebruiker (zie [JtProfilePinStore]),
/// zodat dezelfde code op al zijn toestellen geldt. De code zelf wordt nergens bewaard.
///
/// Formaat: `v1$<iteraties>$<zout base64>$<hash base64>`, met hash = PBKDF2-HMAC-SHA256.
/// Let op: 4 cijfers zijn 10 000 mogelijkheden. Wie de DisplayPreferences kan lezen (de gebruiker
/// zelf en Jellyfin-beheerders) kan de code dus terugrekenen; het is een gezinsslot, geen kluis.
abstract final class JtPin {
  static const int length = 4;
  static const int iterations = 4000;
  static const int _saltBytes = 16;

  static bool isValidPin(String pin) => pin.length == length && RegExp(r'^[0-9]+$').hasMatch(pin);

  /// Nieuwe hash met een willekeurig zout.
  static String hash(String pin, {Random? random, int iterations = iterations}) {
    if (!isValidPin(pin)) throw ArgumentError('Pincode moet uit $length cijfers bestaan');
    final rnd = random ?? Random.secure();
    final salt = Uint8List.fromList(List.generate(_saltBytes, (_) => rnd.nextInt(256)));
    final derived = _pbkdf2(utf8.encode(pin), salt, iterations);
    return 'v1\$$iterations\$${base64Encode(salt)}\$${base64Encode(derived)}';
  }

  /// `true` als [pin] bij [stored] hoort. Een onleesbare [stored] geeft altijd `false`.
  static bool verify(String pin, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'v1') return false;
    final iter = int.tryParse(parts[1]);
    if (iter == null || iter < 1 || iter > 1000000) return false;
    try {
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      final actual = _pbkdf2(utf8.encode(pin), salt, iter);
      if (actual.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= actual[i] ^ expected[i];
      }
      return diff == 0;
    } on FormatException {
      return false;
    }
  }

  /// PBKDF2-HMAC-SHA256 met één blok van 32 bytes.
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }
}

/// Wat er per profiel op de server staat (client `jt-streaming`, id `jt-streaming`).
class JtPinRecord {
  /// Lege tekst = geen pincode.
  final String hash;
  const JtPinRecord(this.hash);

  static const none = JtPinRecord('');

  static const String prefsKey = 'pinHash';

  bool get hasPin => hash.isNotEmpty;

  factory JtPinRecord.fromCustomPrefs(Map<String, dynamic>? prefs) {
    final value = prefs?[prefsKey];
    return JtPinRecord(value is String ? value : '');
  }

  String toJson() => jsonEncode({prefsKey: hash});

  factory JtPinRecord.fromJson(String source) {
    final decoded = jsonDecode(source);
    return JtPinRecord.fromCustomPrefs(decoded is Map<String, dynamic> ? decoded : null);
  }
}

/// Teller voor foute pogingen: na [maxAttempts] fouten [lockDuration] wachten.
class JtPinLockout {
  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(seconds: 30);

  final int failures;
  final DateTime? lockedUntil;

  const JtPinLockout({this.failures = 0, this.lockedUntil});

  bool isLocked(DateTime now) => lockedUntil != null && now.isBefore(lockedUntil!);

  Duration remaining(DateTime now) => isLocked(now) ? lockedUntil!.difference(now) : Duration.zero;

  int get attemptsLeft => maxAttempts - failures;

  /// Na een foute poging. De vijfde fout zet het slot en begint de teller opnieuw.
  JtPinLockout fail(DateTime now) {
    final next = failures + 1;
    if (next >= maxAttempts) return JtPinLockout(lockedUntil: now.add(lockDuration));
    return JtPinLockout(failures: next, lockedUntil: lockedUntil);
  }

  /// Een verlopen slot telt niet meer mee.
  JtPinLockout normalize(DateTime now) =>
      lockedUntil != null && !isLocked(now) ? JtPinLockout(failures: failures) : this;

  String toJson() => jsonEncode({'f': failures, 'u': lockedUntil?.millisecondsSinceEpoch});

  factory JtPinLockout.fromJson(String? source) {
    if (source == null || source.isEmpty) return const JtPinLockout();
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      final until = map['u'] as int?;
      return JtPinLockout(
        failures: (map['f'] as int? ?? 0).clamp(0, maxAttempts - 1),
        lockedUntil: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
      );
    } catch (_) {
      return const JtPinLockout();
    }
  }
}
