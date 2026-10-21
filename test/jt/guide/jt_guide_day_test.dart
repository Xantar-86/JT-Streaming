import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jt/guide/jt_guide_day.dart';

/// Time zone: Dart uses the OS zone for local DateTimes and the Windows VM
/// ignores TZ, so the DST cases only run when the machine follows the
/// Europe/Brussels rules (Forge VM: "W. Europe Standard Time", same EU DST rules); elsewhere they
/// are reported as skipped, never silently green.
final bool brussels = DateTime(2026, 10, 24, 12).timeZoneOffset == const Duration(hours: 2) &&
    DateTime(2026, 10, 26, 12).timeZoneOffset == const Duration(hours: 1) &&
    DateTime(2027, 3, 27, 12).timeZoneOffset == const Duration(hours: 1) &&
    DateTime(2027, 3, 29, 12).timeZoneOffset == const Duration(hours: 2);
final String? noBrussels = brussels ? null : 'local time zone is not Europe/Brussels (${DateTime.now().timeZoneName})';

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

void main() {
  group('JtGuideDay', () {
    test('ordinary day: local midnight to local midnight, 24 h', () {
      const day = JtGuideDay(2026, 10, 21);
      expect(day.start, DateTime(2026, 10, 21));
      expect(day.end, DateTime(2026, 10, 22));
      expect(day.minutes, 24 * 60);
      expect(day.timelineWidth, 14400);
      expect(day.toString(), '2026-10-21');
    });

    test('25/10/2026 lasts 25 h (03:00 CEST -> 02:00 CET), timeline 15000 px', () {
      const day = JtGuideDay(2026, 10, 25);
      expect(day.minutes, 25 * 60);
      expect(day.timelineWidth, 15000);
    }, skip: noBrussels);

    test('28/03/2027 lasts 23 h', () {
      expect(const JtGuideDay(2027, 3, 28).minutes, 23 * 60);
    }, skip: noBrussels);

    test('of(t) around midnight', () {
      expect(JtGuideDay.of(DateTime(2026, 10, 21, 23, 59, 59)), const JtGuideDay(2026, 10, 21));
      expect(JtGuideDay.of(DateTime(2026, 10, 22)), const JtGuideDay(2026, 10, 22));
      expect(const JtGuideDay(2026, 10, 21).contains(DateTime(2026, 10, 22)), isFalse);
      expect(const JtGuideDay(2026, 10, 21).addDays(1), const JtGuideDay(2026, 10, 22));
      expect(const JtGuideDay(2026, 10, 31).addDays(1), const JtGuideDay(2026, 11, 1));
      expect(const JtGuideDay(2026, 10, 25).addDays(1), const JtGuideDay(2026, 10, 26));
    });

    test('value type: equal days are one cache key', () {
      expect({const JtGuideDay(2026, 10, 21), JtGuideDay.of(DateTime(2026, 10, 21, 18))}.length, 1);
    });

    test('hour(h) on 25/10: 02:00 is the first (CEST) one, 03:00 comes 2 h later', () {
      const day = JtGuideDay(2026, 10, 25);
      final two = day.hour(2);
      final three = day.hour(3);
      expect(hm(two), '02:00');
      expect(two.timeZoneOffset, const Duration(hours: 2));
      expect(three.difference(two), const Duration(hours: 2));
    }, skip: noBrussels);

    test('hour(2) on 28/03/2027 does not exist -> 03:00', () {
      expect(hm(const JtGuideDay(2027, 3, 28).hour(2)), '03:00');
    }, skip: noBrussels);
  });

  group('filter (overlap with the day)', () {
    const day = JtGuideDay(2026, 10, 21);
    test('23:30-00:30 is in both days', () {
      final s = DateTime(2026, 10, 21, 23, 30), e = DateTime(2026, 10, 22, 0, 30);
      expect(jtGuideOverlaps(s, e, day), isTrue);
      expect(jtGuideOverlaps(s, e, day.addDays(1)), isTrue);
    });
    test('a program ending exactly at 00:00 is only in the first day', () {
      final s = DateTime(2026, 10, 21, 23, 0), e = DateTime(2026, 10, 22);
      expect(jtGuideOverlaps(s, e, day), isTrue);
      expect(jtGuideOverlaps(s, e, day.addDays(1)), isFalse);
    });
    test('a program starting exactly at 00:00 is only in its own day', () {
      final s = DateTime(2026, 10, 22), e = DateTime(2026, 10, 22, 1);
      expect(jtGuideOverlaps(s, e, day), isFalse);
      expect(jtGuideOverlaps(s, e, day.addDays(1)), isTrue);
    });
  });

  test('jtGuideStep: 78 -> 60, 174 -> 120, 400 -> 180', () {
    expect(jtGuideStep(78), 60);
    expect(jtGuideStep(174), 120);
    expect(jtGuideStep(400), 180);
  });

  test('jump offset: 10 min lead, clamped to the timeline', () {
    const day = JtGuideDay(2026, 10, 21);
    expect(jtGuideScrollOffset(day, DateTime(2026, 10, 21, 18)), 18 * 600 - 100);
    expect(jtGuideScrollOffset(day, DateTime(2026, 10, 21)), 0);
    expect(jtGuideScrollOffset(day, DateTime(2026, 10, 21, 23, 59), viewport: 1000), 14400 - 1000);
  });

  test('+2 h from 23:00 crosses midnight -> tomorrow 01:00', () {
    final t = DateTime(2026, 10, 21, 23).add(const Duration(hours: 2));
    expect(JtGuideDay.of(t), const JtGuideDay(2026, 10, 22));
    expect(hm(t), '01:00');
  });

  test('labels on 25/10: "02:00" twice, 50 labels', () {
    final labels = jtGuideTimeLabels(const JtGuideDay(2026, 10, 25)).map(hm).toList();
    expect(labels.where((l) => l == '02:00').length, 2);
    expect(labels.length, 50);
    expect(labels.first, '00:00');
    expect(labels.last, '23:30');
  }, skip: noBrussels);

  test('labels on an ordinary day: 48, "02:00" once', () {
    final labels = jtGuideTimeLabels(const JtGuideDay(2026, 10, 21)).map(hm).toList();
    expect(labels.length, 48);
    expect(labels.where((l) => l == '02:00').length, 1);
  });

  group('JtGuideRange', () {
    final now = DateTime(2026, 10, 21, 18, 44);
    test('measured forge-test coverage (20/10 04:00 .. 21/10 20:38) -> 2 days', () {
      final range = JtGuideRange.fromTimes(DateTime(2026, 10, 20, 4), DateTime(2026, 10, 21, 20, 38), now);
      expect(range.days, [const JtGuideDay(2026, 10, 20), const JtGuideDay(2026, 10, 21)]);
    });
    test('a last program ending at 00:00 does not offer the next day', () {
      final range = JtGuideRange.fromTimes(DateTime(2026, 10, 21, 4), DateTime(2026, 10, 23), now);
      expect(range.last, const JtGuideDay(2026, 10, 22));
    });
    test('today is always offered; fallback is today + 6', () {
      final range = JtGuideRange.fromTimes(DateTime(2026, 10, 10), DateTime(2026, 10, 12), now);
      expect(range.contains(const JtGuideDay(2026, 10, 21)), isTrue);
      expect(JtGuideRange.week(now).days.length, 7);
    });
  });
}
