import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/providers/api_provider.dart';

class JtTimersState {
  final List<TimerInfoDto> timers;
  final List<SeriesTimerInfoDto> series;
  final Map<String, TimerInfoDto> byProgramId;

  const JtTimersState._(this.timers, this.series, this.byProgramId);

  static const empty = JtTimersState._([], [], {});

  /// Drops finished/cancelled timers, sorts by start and indexes by programId.
  factory JtTimersState.from(List<TimerInfoDto> timers, List<SeriesTimerInfoDto> series) {
    final active = timers
        .where((t) => t.status != RecordingStatus.cancelled && t.status != RecordingStatus.completed)
        .toList()
      ..sort((a, b) => (a.startDate ?? DateTime(0)).compareTo(b.startDate ?? DateTime(0)));
    final byProgramId = <String, TimerInfoDto>{
      for (final timer in active)
        if (timer.programId?.isNotEmpty ?? false) timer.programId!: timer,
    };
    return JtTimersState._(active, List.unmodifiable(series), Map.unmodifiable(byProgramId));
  }
}

/// Light provider with the scheduled timers (tens of items). The ~840 guide
/// channels in liveTvProvider are never reloaded for a recording change.
final jtTimersProvider = AsyncNotifierProvider<JtTimers, JtTimersState>(JtTimers.new);

class JtTimers extends AsyncNotifier<JtTimersState> {
  @override
  Future<JtTimersState> build() async {
    if (!ref.watch(jtCanManageRecordingsProvider)) return JtTimersState.empty;
    final api = ref.read(jellyApiProvider);
    final timers = api.jtTimers();
    final series = api.jtSeriesTimers();
    return JtTimersState.from(await timers, await series);
  }
}
