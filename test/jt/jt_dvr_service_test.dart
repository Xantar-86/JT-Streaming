import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';

void main() {
  test('Defaults (SeriesTimerInfoDto) -> TimerInfoDto keeps program, channel, dates and padding', () {
    final defaults = SeriesTimerInfoDto(
      programId: 'prog-1',
      channelId: 'chan-1',
      name: 'Journaal',
      startDate: DateTime.utc(2026, 10, 20, 19, 0),
      endDate: DateTime.utc(2026, 10, 20, 19, 30),
      prePaddingSeconds: 120,
      postPaddingSeconds: 300,
      recordNewOnly: true,
      recordAnyChannel: false,
      days: const [DayOfWeek.monday],
    );

    final timer = jtTimerFromDefaults(defaults);

    expect(timer.programId, 'prog-1');
    expect(timer.channelId, 'chan-1');
    expect(timer.startDate, DateTime.utc(2026, 10, 20, 19, 0));
    expect(timer.endDate, DateTime.utc(2026, 10, 20, 19, 30));
    expect(timer.prePaddingSeconds, 120);
    expect(timer.postPaddingSeconds, 300);
    expect(timer.name, 'Journaal');
  });

  test('timer index maps programId -> timer and drops cancelled/completed timers', () {
    final state = JtTimersState.from(
      [
        TimerInfoDto(id: 't2', programId: 'p2', status: RecordingStatus.$new, startDate: DateTime.utc(2026, 10, 21)),
        TimerInfoDto(
            id: 't1', programId: 'p1', status: RecordingStatus.inprogress, startDate: DateTime.utc(2026, 10, 20)),
        const TimerInfoDto(id: 't3', programId: 'p3', status: RecordingStatus.cancelled),
        const TimerInfoDto(id: 't4', programId: 'p4', status: RecordingStatus.completed),
        const TimerInfoDto(id: 't5', status: RecordingStatus.$new),
      ],
      const [SeriesTimerInfoDto(id: 's1', name: 'Reeks')],
    );

    expect(state.byProgramId.keys, unorderedEquals(['p1', 'p2']));
    expect(state.byProgramId['p1']?.id, 't1');
    expect(state.byProgramId['p2']?.id, 't2');
    expect(state.byProgramId['p3'], isNull);
    // Sorted by start; a timer without a start date sorts first.
    expect(state.timers.map((t) => t.id), ['t5', 't1', 't2']);
    expect(state.series.single.id, 's1');
  });
}
