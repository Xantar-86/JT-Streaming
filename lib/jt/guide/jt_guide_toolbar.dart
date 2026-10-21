import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/jt/guide/jt_guide_controller.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/jt/guide/jt_guide_keys.dart';
import 'package:fladder/jt/guide/jt_guide_pickers.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';

/// Button row above the guide (§3):
/// `[◀ Earlier] [Now] [Later ▶] | [Day: Wed 21 Oct ▾] [Hour: 18:00 ▾] | Refresh | [trailing]`
/// with the shown date and window on the right.
class JtGuideToolbar extends ConsumerWidget {
  final ScrollController horizontalScrollController;
  final Widget? trailing;

  const JtGuideToolbar({
    required this.horizontalScrollController,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(jtGuideControllerProvider);
    final range = ref.watch(jtGuideRangeProvider).valueOrNull;
    if (range != null && guide.range != range) guide.range = range;
    final l10n = context.localized;
    final tvMargin = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad ? 24.0 : 0.0;

    return JtGuideKeys(
      controller: guide,
      rowArrows: false,
      child: Padding(
        padding: EdgeInsets.only(left: tvMargin, right: tvMargin, top: tvMargin),
        child: AnimatedBuilder(
          animation: Listenable.merge([guide, horizontalScrollController]),
          builder: (context, _) => Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => guide.step(-1),
                icon: const Icon(Icons.chevron_left),
                label: Text(l10n.jtGuideEarlier),
              ),
              FilledButton(
                onPressed: guide.goNow,
                child: Text(l10n.now),
              ),
              ElevatedButton.icon(
                onPressed: () => guide.step(1),
                icon: const Icon(Icons.chevron_right),
                iconAlignment: IconAlignment.end,
                label: Text(l10n.jtGuideLater),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => showJtGuideDayPicker(
                  context,
                  guide,
                  range ?? JtGuideRange(JtGuideDay.of(guide.now()), JtGuideDay.of(guide.now())),
                ),
                icon: const Icon(Icons.arrow_drop_down),
                iconAlignment: IconAlignment.end,
                label: Text('${l10n.jtGuideDay}: ${jtGuideShortDay(context, guide.day)}'),
              ),
              ElevatedButton.icon(
                onPressed: () => showJtGuideHourPicker(context, guide),
                icon: const Icon(Icons.arrow_drop_down),
                iconAlignment: IconAlignment.end,
                label: Text('${l10n.jtGuideHour}: ${guide.anchor.hour.toString().padLeft(2, '0')}:00'),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: () {
                  ref.read(jtGuideCacheProvider.notifier).clear();
                  ref.invalidate(jtGuideRangeProvider);
                  ref.read(liveTvProvider.notifier).fetchDashboard();
                },
                child: Text(l10n.refresh),
              ),
              if (trailing != null) trailing!,
              const SizedBox(width: 12),
              Text(
                jtGuideWindowText(context, guide.visibleStart, guide.visibleEnd),
                key: const ValueKey('jt-guide-window'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
