import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_record_actions.dart';

import 'jt_dvr_test_helpers.dart';

void main() {
  final now = DateTime(2026, 10, 20, 20, 0);
  final future = jtTestProgram(start: now.add(const Duration(hours: 1)), end: now.add(const Duration(hours: 2)));
  final futureSeries =
      jtTestProgram(start: now.add(const Duration(hours: 1)), end: now.add(const Duration(hours: 2)), isSeries: true);
  final running =
      jtTestProgram(start: now.subtract(const Duration(minutes: 10)), end: now.add(const Duration(minutes: 20)));
  final past =
      jtTestProgram(start: now.subtract(const Duration(hours: 2)), end: now.subtract(const Duration(hours: 1)));

  const scheduled = TimerInfoDto(id: 't1', programId: 'p1', status: RecordingStatus.$new);
  const scheduledSeries = TimerInfoDto(id: 't1', programId: 'p1', status: RecordingStatus.$new, seriesTimerId: 's1');
  const inProgress = TimerInfoDto(id: 't1', programId: 'p1', status: RecordingStatus.inprogress, seriesTimerId: 's1');

  test('past program has no actions', () {
    expect(jtRecordActions(past, null, now, true), isEmpty);
    expect(jtRecordActions(past, scheduled, now, true), isEmpty);
  });

  test('future program without timer: record, plus series only for series', () {
    expect(jtRecordActions(future, null, now, true), [JtRecordAction.record]);
    expect(jtRecordActions(futureSeries, null, now, true), [JtRecordAction.record, JtRecordAction.recordSeries]);
  });

  test('running program without timer: record', () {
    expect(jtRecordActions(running, null, now, true), [JtRecordAction.record]);
  });

  test('scheduled timer: cancel, plus cancel series when it belongs to a series', () {
    expect(jtRecordActions(future, scheduled, now, true), [JtRecordAction.cancel]);
    expect(jtRecordActions(futureSeries, scheduledSeries, now, true),
        [JtRecordAction.cancel, JtRecordAction.cancelSeries]);
  });

  test('in-progress timer: stop only', () {
    expect(jtRecordActions(running, inProgress, now, true), [JtRecordAction.stop]);
  });

  test('without the management right every input gives no actions', () {
    for (final program in [future, futureSeries, running, past]) {
      for (final timer in [null, scheduled, scheduledSeries, inProgress]) {
        expect(jtRecordActions(program, timer, now, false), isEmpty);
      }
    }
  });
}
