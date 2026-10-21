import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/models/items/channel_program.dart';

import 'jt_guide_test_helpers.dart';

class _EmptyTimers extends JtTimers {
  @override
  Future<JtTimersState> build() async => JtTimersState.empty;
}

void main() {
  late FakeGuideApi api;
  late DateTime now;
  late ProviderContainer container;
  const today = JtGuideDay(2026, 10, 21);

  setUp(() {
    api = FakeGuideApi();
    now = DateTime(2026, 10, 21, 18);
    container = ProviderContainer(overrides: [
      jtGuideApiProvider.overrideWithValue(api),
      jtGuideClockProvider.overrideWithValue(() => now),
      jtTimersProvider.overrideWith(_EmptyTimers.new),
    ]);
    addTearDown(container.dispose);
  });

  JtGuideCache cache() => container.read(jtGuideCacheProvider.notifier);
  JtGuideCacheState state() => container.read(jtGuideCacheProvider);
  // Batch timer (30 ms) + fetch; waits until nothing is loading (max 3 s).
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    for (var i = 0; i < 150 && state().loading.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('same day and channel twice -> 1 request', () async {
    cache().ensure(today, 'c1');
    cache().ensure(today, 'c1');
    await settle();
    cache().ensure(today, 'c1');
    await settle();
    expect(api.requests.length, 1);
    expect(state().entry(today, 'c1')!.programs, isNotEmpty);
  });

  test('25 channels at once -> 2 requests (20 + 5) with channelIds and the day window', () async {
    for (var i = 0; i < 25; i++) {
      cache().ensure(today, 'c$i');
    }
    await settle();
    expect(api.requests.map((r) => r.channelIds.length), [20, 5]);
    expect(api.requests.first.start, today.start);
    expect(api.requests.first.end, today.end);
    expect(state().days[today]!.length, 25);
  });

  test('channel without programs gets an empty entry and is not asked again', () async {
    api.emptyChannels.add('c-empty');
    cache().ensure(today, 'c-empty');
    await settle();
    cache().ensure(today, 'c-empty');
    await settle();
    expect(api.requests.length, 1);
    expect(state().entry(today, 'c-empty')!.programs, isEmpty);
  });

  test('client filter: programs outside the day are dropped, over-midnight ones kept', () async {
    cache().ensure(today, 'c1');
    cache().ensure(today, 'c2');
    await settle();
    final c1 = state().entry(today, 'c1')!.programs;
    final c2 = state().entry(today, 'c2')!.programs;
    expect(api.requests.length, 1);
    expect(c1.any((p) => p.id == 'c1-before'), isFalse, reason: 'ends exactly at 00:00 of the day');
    expect(c1.any((p) => p.id == 'c1-over-midnight'), isTrue);
    expect(c2.any((p) => p.id == 'c2-ends-at-midnight'), isTrue);
    expect(c1.length, 24);
  });

  test('another day -> a new request', () async {
    cache().ensure(today, 'c1');
    await settle();
    cache().ensure(today.addDays(-1), 'c1');
    await settle();
    expect(api.requests.length, 2);
    expect(api.requests.last.start, today.addDays(-1).start);
  });

  test('older than 60 min -> new request, old data stays visible meanwhile', () async {
    cache().ensure(today, 'c1');
    await settle();
    final before = state().entry(today, 'c1');
    now = now.add(const Duration(minutes: 61));
    api.delay = const Duration(milliseconds: 200);
    cache().ensure(today, 'c1');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(api.requests.length, 2);
    expect(state().entry(today, 'c1'), same(before), reason: 'stale-while-revalidate');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(state().entry(today, 'c1')!.fetchedAt, now);
  });

  test('younger than 60 min -> no request', () async {
    cache().ensure(today, 'c1');
    await settle();
    now = now.add(const Duration(minutes: 59));
    cache().ensure(today, 'c1');
    await settle();
    expect(api.requests.length, 1);
  });

  test('Refresh -> cache empty, next ensure fetches again', () async {
    cache().ensure(today, 'c1');
    await settle();
    cache().clear();
    expect(state().days, isEmpty);
    cache().ensure(today, 'c1');
    await settle();
    expect(api.requests.length, 2);
  });

  test('a DVR action (timers refreshed) -> 0 program requests', () async {
    cache().ensure(today, 'c1');
    await settle();
    await container.read(jtTimersProvider.future);
    container.invalidate(jtTimersProvider);
    await container.read(jtTimersProvider.future);
    await settle();
    expect(api.requests.length, 1);
    expect(state().entry(today, 'c1'), isNotNull);
  });

  test('LRU: a 4th day evicts the oldest, the pinned day stays', () async {
    final d1 = today.addDays(-1), d2 = today, d3 = today.addDays(1), d4 = today.addDays(2);
    cache().pin(d2);
    for (final d in [d1, d2, d3]) {
      cache().ensure(d, 'c1');
      await settle();
    }
    expect(state().days.keys.toSet(), {d1, d2, d3});
    cache().ensure(d4, 'c1');
    await settle();
    expect(state().days.keys.toSet(), {d2, d3, d4});
  });

  test('LRU never evicts the pinned day even if it is the oldest', () async {
    final d1 = today.addDays(-1), d2 = today, d3 = today.addDays(1), d4 = today.addDays(2);
    cache().pin(d1);
    for (final d in [d1, d2, d3, d4]) {
      cache().ensure(d, 'c1');
      await settle();
    }
    expect(state().days.keys.toSet(), {d1, d3, d4});
  });

  test('a failed request shows no data and is retried after 1 min', () async {
    api.fail = true;
    cache().ensure(today, 'c1');
    await settle();
    expect(state().entry(today, 'c1'), isNull);
    expect(state().isLoading(today, 'c1'), isFalse);
    api.fail = false;
    cache().ensure(today, 'c1');
    await settle();
    expect(api.requests.length, 1);
    now = now.add(const Duration(minutes: 2));
    cache().ensure(today, 'c1');
    await settle();
    expect(api.requests.length, 2);
    expect(state().entry(today, 'c1'), isNotNull);
  });

  group('range provider (§2.4)', () {
    test('coverage -> days from earliest start to latest end', () async {
      api.coverageResult = (DateTime(2026, 10, 20, 4), DateTime(2026, 10, 21, 20, 38));
      final range = await container.read(jtGuideRangeProvider.future);
      expect(range.days, [today.addDays(-1), today]);
    });
    test('coverage fails -> GuideInfo', () async {
      api.coverageResult = null;
      api.guideInfoResult = (DateTime(2026, 10, 21, 16), DateTime(2026, 10, 28, 16));
      final range = await container.read(jtGuideRangeProvider.future);
      expect(range.first, today);
      expect(range.last, today.addDays(7));
    });
    test('both fail -> today .. today + 6', () async {
      api.coverageResult = null;
      api.guideInfoResult = null;
      final range = await container.read(jtGuideRangeProvider.future);
      expect(range.days.length, 7);
      expect(range.first, today);
    });
  });

  test('test helper sanity', () {
    final p = guideProgram('x', 'c1', DateTime(2026, 10, 21, 1), DateTime(2026, 10, 21, 2));
    expect(p, isA<ChannelProgram>());
  });
}
