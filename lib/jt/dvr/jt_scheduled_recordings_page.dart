import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_program_dialog.dart';
import 'package:fladder/jt/dvr/jt_recordings_provider.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/jt/guide/jt_guide_keys.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';

/// Entry in the tv guide's top button row (ontwerp-dvr §1-E, §4).
class JtScheduledRecordingsButton extends ConsumerWidget {
  const JtScheduledRecordingsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(jtCanSeeRecordingsProvider)) return const SizedBox.shrink();
    return ElevatedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JtScheduledRecordingsPage()),
      ),
      icon: const Icon(Icons.fiber_smart_record),
      label: Text(context.localized.jtDvrRecordings),
    );
  }
}

/// "Recordings": finished recordings with a delete button where the server
/// allows it, then series timers and upcoming/running timers, each with a
/// cancel button. Pushed with Navigator, no auto_route.
class JtScheduledRecordingsPage extends ConsumerWidget {
  const JtScheduledRecordingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(jtTimersProvider);
    final recordings = ref.watch(jtRecordingsProvider);
    final l10n = context.localized;

    // Arrows move the focus, also on web, where they would scroll (WP2.8c D3).
    return Shortcuts(
      shortcuts: jtGuideArrowShortcuts,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8.0).add(AdaptiveLayout.adaptivePadding(context)),
          child: Padding(
            padding: MediaQuery.paddingOf(context),
            child: Column(
              spacing: 16,
              children: [
                Row(
                  spacing: 6,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const BackButton(),
                    Flexible(
                      child: Text(
                        l10n.jtDvrRecordings,
                        style: Theme.of(context).textTheme.displaySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(jtTimersProvider);
                      ref.invalidate(jtRecordingsProvider);
                      await ref.read(jtTimersProvider.future);
                    },
                    child: state.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => ListView(children: [Center(child: Text(l10n.jtDvrError))]),
                      data: (data) => _JtScheduledList(state: data, recordings: recordings),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JtScheduledList extends ConsumerWidget {
  final JtTimersState state;
  final AsyncValue<List<BaseItemDto>> recordings;
  const _JtScheduledList({required this.state, required this.recordings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.localized;
    final theme = Theme.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    // Without management: only the finished recordings, nothing to plan or cancel.
    final canManage = ref.watch(jtCanManageRecordingsProvider);

    final locale = Localizations.localeOf(context).toLanguageTag();
    final byDay = groupBy(state.timers, (TimerInfoDto t) {
      final start = (t.startDate ?? DateTime(0)).toLocal();
      return DateTime(start.year, start.month, start.day);
    });

    String time(DateTime? date) => date == null ? '--:--' : DateFormat('HH:mm').format(date.toLocal());
    int minutes(int? seconds) => ((seconds ?? 0) / 60).round();

    return ListView(
      children: [
        // The first focus: inside the Shortcuts, above the first button, Enter does nothing here.
        Focus(autofocus: true, child: Text(l10n.jtDvrFinished, style: theme.textTheme.titleLarge)),
        ...recordings.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, _) => [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.jtDvrFinishedError),
            ),
          ],
          data: (items) => items.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.jtDvrFinishedNone),
                  ),
                ]
              : items.map((recording) => _JtRecordingTile(recording: recording)).toList(),
        ),
        if (canManage) ...[
          const Divider(),
          if (state.series.isNotEmpty) ...[
            Text(l10n.jtDvrSeriesHeader, style: theme.textTheme.titleLarge),
            ...state.series.map(
              (series) => ListTile(
                leading: const Icon(Icons.fiber_smart_record, color: Colors.red),
                title: Text(series.name ?? ''),
                subtitle: Text([
                  (series.recordAnyChannel ?? false) ? l10n.jtDvrAnyChannelShort : (series.channelName ?? ''),
                  l10n.jtDvrNewOnly((series.recordNewOnly ?? false) ? l10n.jtDvrYes : l10n.jtDvrNo),
                  l10n.jtDvrPadding(
                    minutes(series.prePaddingSeconds),
                    minutes(series.postPaddingSeconds),
                  ),
                ].where((s) => s.isNotEmpty).join(' · ')),
                trailing: ElevatedButton(
                  onPressed: series.id == null
                      ? null
                      : () => jtCancelSeriesWithConfirm(context, container, series.id!, series.name ?? ''),
                  child: Text(l10n.jtDvrCancelSeries),
                ),
              ),
            ),
            const Divider(),
          ],
          Text(l10n.jtDvrUpcoming, style: theme.textTheme.titleLarge),
          if (state.timers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.jtDvrNone),
            ),
          ...byDay.entries.expand(
            (day) => [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(DateFormat.yMMMMd(locale).format(day.key), style: theme.textTheme.titleMedium),
              ),
              ...day.value.map((timer) {
                final running = timer.status == RecordingStatus.inprogress;
                final status = switch (timer.status) {
                  RecordingStatus.inprogress => l10n.jtDvrInProgress,
                  RecordingStatus.$new || null => l10n.jtDvrStatusScheduled,
                  final other => other.value ?? l10n.jtDvrStatusScheduled,
                };
                return ListTile(
                  leading: (timer.seriesTimerId?.isNotEmpty ?? false)
                      ? const Icon(Icons.fiber_smart_record)
                      : const Icon(Icons.fiber_manual_record_outlined),
                  title: Text(timer.name ?? ''),
                  subtitle: Text.rich(TextSpan(children: [
                    TextSpan(text: '${timer.channelName ?? ''} · ${time(timer.startDate)}–${time(timer.endDate)} · '),
                    TextSpan(
                      text: status,
                      style: running ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold) : null,
                    ),
                  ])),
                  trailing: ElevatedButton(
                    onPressed: () => jtCancelTimerWithConfirm(context, container, timer),
                    child: Text(running ? l10n.jtDvrStopRecording : l10n.jtDvrCancelRecording),
                  ),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}

class _JtRecordingTile extends StatelessWidget {
  final BaseItemDto recording;
  const _JtRecordingTile({required this.recording});

  @override
  Widget build(BuildContext context) {
    final l10n = context.localized;
    final running = jtRecordingRunning(recording);
    final title = jtRecordingTitle(recording);
    final minutes = ((recording.runTimeTicks ?? 0) / 600000000).round();
    return ListTile(
      leading: running ? const Icon(Icons.fiber_manual_record, color: Colors.red) : const Icon(Icons.movie_outlined),
      title: Text(title),
      subtitle: Text([
        if (recording.name != null && recording.name != title) recording.name!,
        if (recording.channelName?.isNotEmpty ?? false) recording.channelName!,
        if (jtRecordingDate(recording) case final date?) date,
        if (running) l10n.jtDvrInProgress else if (minutes > 0) '$minutes min',
      ].join(' · ')),
      trailing: jtCanDeleteRecording(recording)
          ? ElevatedButton(
              onPressed: () => jtDeleteRecordingWithConfirm(
                context,
                ProviderScope.containerOf(context, listen: false),
                recording,
              ),
              child: Text(l10n.delete),
            )
          : null,
    );
  }
}
