import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/jt/dvr/jt_record_actions.dart';
import 'package:fladder/jt/dvr/jt_record_buttons.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';

/// Copy of showDefaultAlertDialog ("Switch channel", Decline/Watch) with the
/// recording buttons in between (ontwerp-dvr §1-A).
Future<void> showJtProgramDialog(
  BuildContext context, {
  required ChannelProgram program,
  required ChannelModel channel,
  required VoidCallback onWatch,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.localized.switchChannel),
      content: Text(dialogContext.localized.switchChannelDesc(program.name, channel.name)),
      actions: [
        ElevatedButton(
          autofocus: AdaptiveLayout.inputDeviceOf(dialogContext) == InputDevice.dPad,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.localized.decline),
        ),
        JtRecordButtons(
          program: program,
          channelName: channel.name,
          onDone: () {
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
            foregroundColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
            iconColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
          ),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onWatch();
          },
          child: Text(dialogContext.localized.watch),
        ),
      ],
    ),
  );
}

/// Same AlertDialog style as "Switch channel"; returns true on accept.
Future<bool> _confirm(BuildContext context, String title, String content, String acceptTitle) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        ElevatedButton(
          autofocus: AdaptiveLayout.inputDeviceOf(dialogContext) == InputDevice.dPad,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.localized.decline),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
            foregroundColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
            iconColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(acceptTitle),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Confirmation for Record / Record series: shows the server defaults
/// (padding, new-only, any-channel) read-only (ontwerp-dvr §1, §7.3).
Future<bool> showJtRecordConfirmDialog(
  BuildContext context, {
  required SeriesTimerInfoDto defaults,
  required ChannelProgram program,
  required bool series,
  String? channelName,
}) {
  final l10n = context.localized;
  final start = (defaults.startDate ?? program.startDate).toLocal();
  final end = (defaults.endDate ?? program.endDate).toLocal();
  final yes = l10n.jtDvrYes;
  final no = l10n.jtDvrNo;
  final lines = [
    defaults.name ?? program.name,
    if ((defaults.channelName ?? channelName ?? '').isNotEmpty) defaults.channelName ?? channelName!,
    '${DateFormat('dd/MM HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}',
    l10n.jtDvrPadding(
      ((defaults.prePaddingSeconds ?? 0) / 60).round(),
      ((defaults.postPaddingSeconds ?? 0) / 60).round(),
    ),
    if (series) l10n.jtDvrNewOnly((defaults.recordNewOnly ?? false) ? yes : no),
    if (series) l10n.jtDvrAnyChannel((defaults.recordAnyChannel ?? false) ? yes : no),
  ];
  final title = series ? l10n.jtDvrRecordSeries : l10n.jtDvrRecord;
  return _confirm(context, title, lines.join('\n'), title);
}

/// Runs one recording action: confirm, call Jellyfin, refresh only the
/// timers provider, report through FladderSnack. Returns true on success.
Future<bool> jtRunRecordAction(
  BuildContext context,
  JtRecordAction action, {
  required ChannelProgram program,
  TimerInfoDto? timer,
  String? channelName,
}) async {
  // The container outlives the widget that started the action.
  final container = ProviderScope.containerOf(context, listen: false);
  switch (action) {
    case JtRecordAction.record:
    case JtRecordAction.recordSeries:
      return _createWithConfirm(context, container, program, action == JtRecordAction.recordSeries, channelName);
    case JtRecordAction.cancel:
    case JtRecordAction.stop:
      if (timer == null) return false;
      return jtCancelTimerWithConfirm(context, container, timer);
    case JtRecordAction.cancelSeries:
      final seriesTimerId = timer?.seriesTimerId;
      if (seriesTimerId == null) return false;
      return jtCancelSeriesWithConfirm(context, container, seriesTimerId, timer?.name ?? program.name);
  }
}

Future<bool> _createWithConfirm(
  BuildContext context,
  ProviderContainer container,
  ChannelProgram program,
  bool series,
  String? channelName,
) async {
  final l10n = context.localized;
  final api = container.read(jellyApiProvider);
  final defaults = await api.jtTimerDefaults(program.id);
  if (defaults == null) {
    FladderSnack.show(l10n.jtDvrError);
    return false;
  }
  if (!context.mounted) return false;
  final confirmed = await showJtRecordConfirmDialog(
    context,
    defaults: defaults,
    program: program,
    series: series,
    channelName: channelName,
  );
  if (!confirmed) return false;
  final ok = series ? await api.jtCreateSeriesTimer(defaults) : await api.jtCreateTimer(defaults);
  FladderSnack.show(ok ? (series ? l10n.jtDvrSeriesSuccess : l10n.jtDvrRecordSuccess) : l10n.jtDvrError);
  if (ok) {
    container.invalidate(jtTimersProvider);
    // Jellyfin creates the episode timers of a series asynchronously.
    if (series) Timer(const Duration(seconds: 3), () => container.invalidate(jtTimersProvider));
  }
  return ok;
}

/// Cancel or stop a single timer (guide buttons and "Scheduled recordings").
Future<bool> jtCancelTimerWithConfirm(BuildContext context, ProviderContainer container, TimerInfoDto timer) async {
  final l10n = context.localized;
  final timerId = timer.id;
  if (timerId == null) return false;
  final stop = timer.status == RecordingStatus.inprogress;
  final name = timer.name ?? '';
  final title = stop ? l10n.jtDvrStopRecording : l10n.jtDvrCancelRecording;
  final confirmed = await _confirm(
    context,
    title,
    stop ? l10n.jtDvrStopConfirm(name) : l10n.jtDvrCancelConfirm(name),
    title,
  );
  if (!confirmed) return false;
  final ok = await container.read(jellyApiProvider).jtCancelTimer(timerId);
  FladderSnack.show(ok ? l10n.jtDvrCancelSuccess : l10n.jtDvrError);
  if (ok) container.invalidate(jtTimersProvider);
  return ok;
}

/// Cancel a series timer (guide buttons and "Scheduled recordings").
Future<bool> jtCancelSeriesWithConfirm(
  BuildContext context,
  ProviderContainer container,
  String seriesTimerId,
  String name,
) async {
  final l10n = context.localized;
  final confirmed = await _confirm(
    context,
    l10n.jtDvrCancelSeries,
    l10n.jtDvrCancelSeriesConfirm(name),
    l10n.jtDvrCancelSeries,
  );
  if (!confirmed) return false;
  final ok = await container.read(jellyApiProvider).jtCancelSeriesTimer(seriesTimerId);
  FladderSnack.show(ok ? l10n.jtDvrCancelSuccess : l10n.jtDvrError);
  if (ok) container.invalidate(jtTimersProvider);
  return ok;
}
