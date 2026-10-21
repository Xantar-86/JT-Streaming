import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/providers/api_provider.dart';

/// The two calls the guide makes (§2). An interface so the cache can be tested
/// against a fake API.
abstract class JtGuideApi {
  /// Programs of [channelIds] overlapping [start]..[end] (one GET).
  Future<List<ChannelProgram>> programs(List<String> channelIds, DateTime start, DateTime end);

  /// Earliest start and latest end in the EPG (§2.4); null when unknown.
  Future<(DateTime?, DateTime?)> coverage();

  /// Configured guide range (/LiveTv/GuideInfo), the fallback for [coverage].
  Future<(DateTime?, DateTime?)> guideInfo();
}

class _JellyfinGuideApi implements JtGuideApi {
  final Ref ref;
  _JellyfinGuideApi(this.ref);

  @override
  Future<List<ChannelProgram>> programs(List<String> channelIds, DateTime start, DateTime end) async {
    final service = ref.read(jellyApiProvider);
    final response = await service.api.liveTvProgramsGet(
      channelIds: channelIds,
      userId: service.account?.id,
      minEndDate: start.toUtc(),
      maxStartDate: end.toUtc(),
      enableUserData: false,
      sortBy: [ItemSortBy.startdate],
      fields: [ItemFields.overview, ItemFields.parentid],
      // Safety net only: a chunk is 20 channels x ~30-50 programs.
      limit: 1500,
      enableTotalRecordCount: false,
    );
    if (!response.isSuccessful) throw Exception('GET /LiveTv/Programs failed: ${response.statusCode}');
    return response.body?.items?.map((e) => ChannelProgram.fromBaseDto(e, ref)).toList() ?? const [];
  }

  @override
  Future<(DateTime?, DateTime?)> coverage() async {
    final service = ref.read(jellyApiProvider);
    Future<BaseItemDto?> one(SortOrder order) async {
      final response = await service.api.liveTvProgramsGet(
        userId: service.account?.id,
        limit: 1,
        sortBy: [ItemSortBy.startdate],
        sortOrder: [order],
        enableImages: false,
        enableUserData: false,
        enableTotalRecordCount: false,
      );
      if (!response.isSuccessful) throw Exception('GET /LiveTv/Programs failed: ${response.statusCode}');
      return response.body?.items?.firstOrNull;
    }

    final first = await one(SortOrder.ascending);
    final last = await one(SortOrder.descending);
    return (first?.startDate?.toLocal(), last?.endDate?.toLocal());
  }

  @override
  Future<(DateTime?, DateTime?)> guideInfo() async {
    final response = await ref.read(jellyApiProvider).api.liveTvGuideInfoGet();
    return (response.body?.startDate?.toLocal(), response.body?.endDate?.toLocal());
  }
}

final jtGuideApiProvider = Provider<JtGuideApi>((ref) => _JellyfinGuideApi(ref));

/// Clock of the guide; tests pin it (25/10/2026).
final jtGuideClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Days for the day picker (§2.4): EPG coverage, else GuideInfo, else today
/// through today + 6.
final jtGuideRangeProvider = FutureProvider<JtGuideRange>((ref) async {
  final api = ref.watch(jtGuideApiProvider);
  final now = ref.watch(jtGuideClockProvider)();
  try {
    final (first, last) = await api.coverage();
    if (first != null && last != null) return JtGuideRange.fromTimes(first, last, now);
  } catch (e) {
    debugPrint('[jt-guide] coverage failed: $e');
  }
  try {
    final (first, last) = await api.guideInfo();
    if (first != null && last != null) return JtGuideRange.fromTimes(first, last, now);
  } catch (e) {
    debugPrint('[jt-guide] GuideInfo failed: $e');
  }
  return JtGuideRange.week(now);
});

class JtGuideEntry {
  final List<ChannelProgram> programs;
  final DateTime fetchedAt;
  const JtGuideEntry(this.programs, this.fetchedAt);
}

typedef JtGuideKey = (JtGuideDay, String);

class JtGuideCacheState {
  final Map<JtGuideDay, Map<String, JtGuideEntry>> days;
  final Set<JtGuideKey> loading;
  final Map<JtGuideKey, DateTime> failed;

  const JtGuideCacheState({this.days = const {}, this.loading = const {}, this.failed = const {}});

  JtGuideEntry? entry(JtGuideDay day, String channelId) => days[day]?[channelId];
  bool isLoading(JtGuideDay day, String channelId) => loading.contains((day, channelId));
}

/// Program cache per (local day, channel) (§2.3): rows ask through [ensure],
/// a batcher groups them into one GET per <= 20 channels, at most 3 days are
/// kept (LRU, the shown day is pinned), entries older than 60 min are fetched
/// again while the old data stays visible.
final jtGuideCacheProvider = NotifierProvider<JtGuideCache, JtGuideCacheState>(JtGuideCache.new);

class JtGuideCache extends Notifier<JtGuideCacheState> {
  static const batchSize = 20;
  static const batchDelay = Duration(milliseconds: 30);
  static const ttl = Duration(minutes: 60);
  static const failedRetry = Duration(minutes: 1);
  static const maxDays = 3;

  final Map<JtGuideDay, Set<String>> _queued = {};
  Timer? _timer;
  final List<JtGuideDay> _recent = [];
  JtGuideDay? _pinned;
  int _generation = 0;

  @override
  JtGuideCacheState build() {
    ref.onDispose(() => _timer?.cancel());
    return const JtGuideCacheState();
  }

  DateTime _now() => ref.read(jtGuideClockProvider)();

  /// Marks the day on screen; it is never evicted.
  void pin(JtGuideDay day) {
    _pinned = day;
    _touch(day);
  }

  /// Cache hit = no request. Missing or stale (> 60 min) = queued.
  void ensure(JtGuideDay day, String channelId) {
    _touch(day);
    final key = (day, channelId);
    if (state.loading.contains(key) || (_queued[day]?.contains(channelId) ?? false)) return;
    final entry = state.entry(day, channelId);
    if (entry != null && _now().difference(entry.fetchedAt) < ttl) return;
    final failedAt = state.failed[key];
    if (entry == null && failedAt != null && _now().difference(failedAt) < failedRetry) return;

    (_queued[day] ??= <String>{}).add(channelId);
    // Only a missing entry shows a spinner; a stale one stays visible.
    if (entry == null) state = _copy(loading: {...state.loading, key});
    if (_queued[day]!.length >= batchSize) {
      _flushDay(day);
    } else {
      _timer ??= Timer(batchDelay, _flushAll);
    }
  }

  /// "Refresh": empties the guide cache.
  void clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _queued.clear();
    _recent.clear();
    if (_pinned != null) _recent.add(_pinned!);
    state = const JtGuideCacheState();
  }

  void _flushAll() {
    _timer = null;
    for (final day in _queued.keys.toList()) {
      _flushDay(day);
    }
  }

  void _flushDay(JtGuideDay day) {
    final ids = _queued.remove(day)?.toList() ?? const <String>[];
    for (var i = 0; i < ids.length; i += batchSize) {
      final end = (i + batchSize) > ids.length ? ids.length : i + batchSize;
      unawaited(_fetch(day, ids.sublist(i, end)));
    }
    if (_queued.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _fetch(JtGuideDay day, List<String> ids) async {
    final generation = _generation;
    final keys = {for (final id in ids) (day, id)};
    state = _copy(loading: {...state.loading, ...keys});
    try {
      final programs = await ref.read(jtGuideApiProvider).programs(ids, day.start, day.end);
      if (generation != _generation) return;
      final byChannel = <String, List<ChannelProgram>>{for (final id in ids) id: <ChannelProgram>[]};
      for (final p in programs) {
        if (!jtGuideOverlaps(p.startDate, p.endDate, day)) continue;
        byChannel[p.channelId]?.add(p);
      }
      final fetchedAt = _now();
      final dayMap = {...?state.days[day]};
      for (final e in byChannel.entries) {
        e.value.sort((a, b) => a.startDate.compareTo(b.startDate));
        dayMap[e.key] = JtGuideEntry(List.unmodifiable(e.value), fetchedAt);
      }
      final days = {...state.days, day: dayMap};
      _evict(days);
      state = _copy(
        days: days,
        loading: {...state.loading}..removeAll(keys),
        failed: {...state.failed}..removeWhere((k, _) => keys.contains(k)),
      );
    } catch (e) {
      debugPrint('[jt-guide] programs for $day failed: $e');
      if (generation != _generation) return;
      final failedAt = _now();
      state = _copy(
        loading: {...state.loading}..removeAll(keys),
        failed: {...state.failed, for (final k in keys) k: failedAt},
      );
    }
  }

  void _touch(JtGuideDay day) {
    _recent.remove(day);
    _recent.add(day);
  }

  void _evict(Map<JtGuideDay, Map<String, JtGuideEntry>> days) {
    while (days.length > maxDays) {
      final victim = _recent.firstWhere(
        (d) => days.containsKey(d) && d != _pinned,
        orElse: () => days.keys.firstWhere((d) => d != _pinned),
      );
      days.remove(victim);
      _recent.remove(victim);
    }
  }

  JtGuideCacheState _copy({
    Map<JtGuideDay, Map<String, JtGuideEntry>>? days,
    Set<JtGuideKey>? loading,
    Map<JtGuideKey, DateTime>? failed,
  }) =>
      JtGuideCacheState(
        days: days ?? state.days,
        loading: loading ?? state.loading,
        failed: failed ?? state.failed,
      );
}
