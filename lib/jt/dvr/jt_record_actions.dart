import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/channel_program.dart';

enum JtRecordAction {
  record,
  recordSeries,
  cancel,
  cancelSeries,
  stop,
}

/// Which recording buttons a program gets (ontwerp-dvr §1, "Toestanden").
/// Pure, so it can be unit tested without widgets or network.
List<JtRecordAction> jtRecordActions(
  ChannelProgram program,
  TimerInfoDto? timer,
  DateTime now,
  bool canManage,
) {
  if (!canManage) return const [];
  if (!program.endDate.isAfter(now)) return const [];

  if (timer == null) {
    return [
      JtRecordAction.record,
      if (program.isSeries) JtRecordAction.recordSeries,
    ];
  }

  if (timer.status == RecordingStatus.inprogress) {
    return const [JtRecordAction.stop];
  }

  return [
    JtRecordAction.cancel,
    if (timer.seriesTimerId?.isNotEmpty ?? false) JtRecordAction.cancelSeries,
  ];
}
