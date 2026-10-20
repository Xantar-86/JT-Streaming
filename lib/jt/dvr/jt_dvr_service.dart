import 'package:flutter/foundation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/providers/service_provider.dart';

/// `GET /LiveTv/Timers/Defaults` returns a [SeriesTimerInfoDto]; a single
/// recording needs a [TimerInfoDto]. Both DTOs share their JSON keys
/// (ProgramId, ChannelId, StartDate, EndDate, Pre/PostPaddingSeconds, ...),
/// unknown keys are ignored by fromJson.
TimerInfoDto jtTimerFromDefaults(SeriesTimerInfoDto defaults) => TimerInfoDto.fromJson(defaults.toJson());

/// JT-Streaming DVR calls on top of the existing generated client, so
/// service_provider.dart stays untouched (ontwerp-dvr §2).
extension JtDvr on JellyService {
  Future<SeriesTimerInfoDto?> jtTimerDefaults(String programId) async {
    final response = await api.liveTvTimersDefaultsGet(programId: programId);
    return response.isSuccessful ? response.body : null;
  }

  Future<bool> jtCreateTimer(SeriesTimerInfoDto defaults) async {
    final response = await api.liveTvTimersPost(body: jtTimerFromDefaults(defaults));
    return response.isSuccessful;
  }

  Future<bool> jtCreateSeriesTimer(SeriesTimerInfoDto defaults) async {
    final response = await api.liveTvSeriesTimersPost(body: defaults);
    return response.isSuccessful;
  }

  Future<bool> jtCancelTimer(String timerId) async {
    final response = await api.liveTvTimersTimerIdDelete(timerId: timerId);
    return response.isSuccessful;
  }

  Future<bool> jtCancelSeriesTimer(String seriesTimerId) async {
    final response = await api.liveTvSeriesTimersTimerIdDelete(timerId: seriesTimerId);
    return response.isSuccessful;
  }

  Future<List<TimerInfoDto>> jtTimers() async {
    final response = await api.liveTvTimersGet();
    if (!response.isSuccessful) debugPrint('[jt-dvr] GET /LiveTv/Timers failed: ${response.statusCode}');
    return response.body?.items ?? const [];
  }

  Future<List<SeriesTimerInfoDto>> jtSeriesTimers() async {
    final response = await api.liveTvSeriesTimersGet();
    if (!response.isSuccessful) debugPrint('[jt-dvr] GET /LiveTv/SeriesTimers failed: ${response.statusCode}');
    return response.body?.items ?? const [];
  }
}
