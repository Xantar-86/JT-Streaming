import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jt/dvr/jt_program_dialog.dart';
import 'package:fladder/jt/dvr/jt_scheduled_recordings_page.dart';
import 'package:fladder/jt/guide/jt_guide_toolbar.dart';
import 'package:fladder/jt/guide/jt_live_tv_guide.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';

@RoutePage()
class LiveTvScreen extends ConsumerStatefulWidget {
  final String viewId;
  const LiveTvScreen({
    @QueryParam() this.viewId = "",
    super.key,
  });

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveTvProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0).add(AdaptiveLayout.adaptivePadding(context)),
        child: state.channels.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: MediaQuery.paddingOf(context),
                child: Column(
                  spacing: 16,
                  children: [
                    Row(
                      spacing: 6,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const BackButton(),
                        Text(
                          "TV Guide",
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    JtGuideToolbar( // JT-HOOK: guide-nav
                      horizontalScrollController: _horizontalScrollController,
                      trailing: const JtScheduledRecordingsButton(), // JT-HOOK: dvr-scheduled
                    ),
                    Expanded(
                      child: JtLiveTvGuide( // JT-HOOK: guide-nav
                        horizontalScrollController: _horizontalScrollController,
                        onProgramSelected: (program, channel) async {
                          await showJtProgramDialog(context, // JT-HOOK: dvr-dialog
                              program: program,
                              channel: channel,
                              onWatch: () => program.channel.play(context, ref));
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
