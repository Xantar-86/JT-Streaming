import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/screens/live_tv/widgets/guide_constants.dart';

/// Red recording marker on a guide cell (ontwerp-dvr §1-B): one dot for a
/// scheduled timer, two for a timer of a series, a ringed record icon while
/// recording. Only cells whose timer changes rebuild.
class JtRecordingBadge extends ConsumerWidget {
  final String programId;
  final Widget child;

  const JtRecordingBadge({
    required this.programId,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(jtTimersProvider.select((s) => s.valueOrNull?.byProgramId[programId]));
    if (timer == null) return child;

    final Widget marker;
    if (timer.status == RecordingStatus.inprogress) {
      marker = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.red, width: 1.5),
        ),
        child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
      );
    } else {
      const dot = SizedBox.square(
        dimension: 10,
        child: DecoratedBox(decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      );
      marker = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          dot,
          if (timer.seriesTimerId?.isNotEmpty ?? false) dot,
        ],
      );
    }

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: 5,
          end: GuideConstants.padding + 5,
          child: IgnorePointer(child: marker),
        ),
      ],
    );
  }
}
