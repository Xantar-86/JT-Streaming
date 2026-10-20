import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_program_dialog.dart';
import 'package:fladder/jt/dvr/jt_record_actions.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/util/localization_helper.dart';

String jtRecordActionLabel(AppLocalizations l10n, JtRecordAction action) => switch (action) {
      JtRecordAction.record => l10n.jtDvrRecord,
      JtRecordAction.recordSeries => l10n.jtDvrRecordSeries,
      JtRecordAction.cancel => l10n.jtDvrCancelRecording,
      JtRecordAction.cancelSeries => l10n.jtDvrCancelSeries,
      JtRecordAction.stop => l10n.jtDvrStopRecording,
    };

/// Record / Record series / Cancel / Stop for one program. Renders nothing
/// without the Live TV management right or for programs in the past.
class JtRecordButtons extends ConsumerWidget {
  final ChannelProgram program;
  final String? channelName;
  final bool dense;

  /// Called after a successful action (e.g. to close the guide dialog).
  final VoidCallback? onDone;

  const JtRecordButtons({
    required this.program,
    this.channelName,
    this.dense = false,
    this.onDone,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(jtCanManageRecordingsProvider);
    if (!canManage) return const SizedBox.shrink();
    final timer = ref.watch(jtTimersProvider.select((s) => s.valueOrNull?.byProgramId[program.id]));
    final actions = jtRecordActions(program, timer, DateTime.now(), canManage);
    if (actions.isEmpty) return const SizedBox.shrink();

    final style = dense ? ElevatedButton.styleFrom(visualDensity: VisualDensity.compact) : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions
          .map(
            (action) => ElevatedButton.icon(
              style: style,
              icon: Icon(
                action == JtRecordAction.record || action == JtRecordAction.recordSeries
                    ? Icons.fiber_manual_record
                    : Icons.stop_circle_outlined,
                color: Colors.red,
              ),
              onPressed: () async {
                final ok = await jtRunRecordAction(
                  context,
                  action,
                  program: program,
                  timer: timer,
                  channelName: channelName,
                );
                if (ok) onDone?.call();
              },
              label: Text(jtRecordActionLabel(context.localized, action)),
            ),
          )
          .toList(),
    );
  }
}
