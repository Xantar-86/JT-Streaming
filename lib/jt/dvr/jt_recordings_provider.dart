import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/providers/api_provider.dart';

/// A recording that is still being written: the server reports it with type
/// Recording and status InProgress. Stop it first, then it can be deleted.
bool jtRecordingRunning(BaseItemDto recording) =>
    recording.type == BaseItemKind.recording || recording.status == RecordingStatus.inprogress.value;

/// The server's own answer for this user decides, not the user's policy.
bool jtCanDeleteRecording(BaseItemDto recording) =>
    recording.canDelete == true && (recording.id?.isNotEmpty ?? false) && !jtRecordingRunning(recording);

String jtRecordingTitle(BaseItemDto recording) => recording.seriesName ?? recording.name ?? '';

/// A daily show has one name for every recording: only the date tells them apart.
String? jtRecordingDate(BaseItemDto recording) {
  final date = recording.startDate ?? recording.dateCreated;
  return date == null ? null : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}

/// Refetched each time the page opens: recordings finish while nobody looks.
final jtRecordingsProvider = FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  if (!ref.watch(jtCanSeeRecordingsProvider)) return const [];
  return ref.read(jellyApiProvider).jtRecordings();
});
