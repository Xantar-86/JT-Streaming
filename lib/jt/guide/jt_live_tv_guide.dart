import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/jt/guide/jt_guide_controller.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/jt/guide/jt_guide_keys.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/screens/live_tv/widgets/channel_row.dart';
import 'package:fladder/screens/live_tv/widgets/guide_constants.dart';
import 'package:fladder/screens/live_tv/widgets/timeline_header.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';

/// Copy of LiveTvGuide (lib/screens/live_tv/live_tv_guide.dart) with a local
/// calendar day as timeline, programs from [jtGuideCacheProvider], the now
/// line only on today, and one scroll controller per built row that is
/// released when the row is disposed (ontwerp-gids-navigatie §6).
class JtLiveTvGuide extends ConsumerStatefulWidget {
  final ChannelModel? currentChannel;
  final ChannelProgram? selectedProgram;
  final ScrollController horizontalScrollController;
  final Function(ChannelProgram program, ChannelModel channel)? onProgramSelected;
  final Function(ChannelProgram program, ChannelModel channel)? onLongPressProgram;
  const JtLiveTvGuide({
    this.currentChannel,
    this.selectedProgram,
    required this.horizontalScrollController,
    this.onProgramSelected,
    this.onLongPressProgram,
    super.key,
  });

  @override
  ConsumerState<JtLiveTvGuide> createState() => _JtLiveTvGuideState();
}

class _JtLiveTvGuideState extends ConsumerState<JtLiveTvGuide> {
  final ScrollController _verticalScrollController = ScrollController();
  final Set<ScrollController> _rowControllers = {};
  bool _isSyncingScroll = false;
  Timer? _nowTimer;
  late final JtGuideController _guide = ref.read(jtGuideControllerProvider);

  @override
  void initState() {
    super.initState();
    _guide.attach(widget.horizontalScrollController);
    _guide.revealChannel = _revealChannel;
    widget.horizontalScrollController.addListener(_onHorizontalScroll);
    _verticalScrollController.addListener(_onVerticalScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onVerticalScroll();
      _guide.goNow(focus: false);
    });
    _startNowTimer();
  }

  void _startNowTimer() {
    _nowTimer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(minutes: 1));
    _nowTimer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    });
  }

  @override
  void dispose() {
    widget.horizontalScrollController.removeListener(_onHorizontalScroll);
    _guide.detach(widget.horizontalScrollController);
    if (_guide.revealChannel == _revealChannel) _guide.revealChannel = null;
    _verticalScrollController.dispose();
    _nowTimer?.cancel();
    super.dispose();
  }

  void _onVerticalScroll() {
    final channels = ref.read(liveTvProvider).channels;
    if (channels.isEmpty || !_verticalScrollController.hasClients) return;
    final index = (_verticalScrollController.offset / GuideConstants.channelRowHeight).floor();
    _guide.firstVisibleChannelId = channels[index.clamp(0, channels.length - 1)].id;
  }

  void _revealChannel(String channelId) {
    final channels = ref.read(liveTvProvider).channels;
    final index = channels.indexWhere((c) => c.id == channelId);
    if (index < 0 || !_verticalScrollController.hasClients) return;
    final max = _verticalScrollController.position.maxScrollExtent;
    final target = (index * GuideConstants.channelRowHeight).clamp(0.0, max).toDouble();
    if ((_verticalScrollController.offset - target).abs() > 1) _verticalScrollController.jumpTo(target);
  }

  void _onHorizontalScroll() {
    if (_isSyncingScroll) return;
    _syncScrollPositions(widget.horizontalScrollController);
  }

  void _syncScrollPositions(ScrollController source) {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    final offset = source.offset;
    for (final controller in [widget.horizontalScrollController, ..._rowControllers]) {
      if (controller != source && controller.hasClients && controller.offset != offset) {
        final max = controller.position.maxScrollExtent;
        controller.jumpTo(offset > max ? max : offset);
      }
    }
    _isSyncingScroll = false;
  }

  void _scrollAllTo(double value) {
    if (value < 0) value = 0;
    _isSyncingScroll = true;
    for (final controller in [widget.horizontalScrollController, ..._rowControllers]) {
      if (controller.hasClients) {
        controller.animateTo(value, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    }
    Future.delayed(const Duration(milliseconds: 300), () => _isSyncingScroll = false);
  }

  ScrollController _registerRow() {
    final initial = widget.horizontalScrollController.hasClients ? widget.horizontalScrollController.offset : 0.0;
    final controller = ScrollController(initialScrollOffset: initial);
    controller.addListener(() {
      if (_isSyncingScroll) return;
      _syncScrollPositions(controller);
    });
    _rowControllers.add(controller);
    return controller;
  }

  void _unregisterRow(ScrollController controller) {
    _rowControllers.remove(controller);
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(liveTvProvider.select((s) => s.channels));
    final guide = ref.watch(jtGuideControllerProvider);
    final range = ref.watch(jtGuideRangeProvider).valueOrNull;
    if (range != null && guide.range != range) guide.range = range;

    final day = guide.day;
    final startDate = day.start;
    final endDate = day.end;
    final now = ref.watch(jtGuideClockProvider)();
    final showNow = day.contains(now);
    final timelineWidth = day.timelineWidth;
    final nowLeft = day.offsetOf(now).clamp(0.0, timelineWidth).toDouble();
    const timeLineTopPadding = 60.0;
    final tvMargin = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad ? 24.0 : 0.0;

    return JtGuideKeys(
      controller: guide,
      child: Padding(
        padding: EdgeInsets.only(left: tvMargin, right: tvMargin, bottom: tvMargin),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8.0)),
          width: double.infinity,
          child: Stack(
            children: [
              Column(
                children: [
                  TimelineHeader(
                    horizontalScrollController: widget.horizontalScrollController,
                    startDate: startDate,
                    endDate: endDate,
                    timeLabels: jtGuideTimeLabels(day),
                    timelineWidth: timelineWidth,
                    now: now,
                    nowLeft: nowLeft,
                    timeLineTopPadding: timeLineTopPadding,
                  ),
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(50),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      controller: _verticalScrollController,
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return _JtGuideRow(
                          key: ValueKey(channel.id),
                          channel: channel,
                          day: day,
                          guide: guide,
                          selected: channel.id == widget.currentChannel?.id,
                          selectedProgram: widget.selectedProgram,
                          register: _registerRow,
                          unregister: _unregisterRow,
                          scrollAllTo: _scrollAllTo,
                          onProgramSelected: (program) => widget.onProgramSelected?.call(program, channel),
                          onLongPressProgram: (program) => widget.onLongPressProgram?.call(program, channel),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (showNow)
                AnimatedBuilder(
                  animation: widget.horizontalScrollController,
                  builder: (context, child) {
                    final scrollOffset =
                        widget.horizontalScrollController.hasClients ? widget.horizontalScrollController.offset : 0.0;
                    final start = (GuideConstants.leftColumnWidth + nowLeft - scrollOffset);
                    final lineStart =
                        start.clamp(GuideConstants.leftColumnWidth, GuideConstants.leftColumnWidth + timelineWidth);
                    final bubbleStart = (start - 24)
                        .clamp(GuideConstants.leftColumnWidth, GuideConstants.leftColumnWidth + timelineWidth);
                    return Stack(
                      children: [
                        PositionedDirectional(
                          key: const ValueKey('jt-guide-now-line'),
                          start: lineStart - 2,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 2,
                              color: Theme.of(context).colorScheme.primary.withAlpha(200),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: bubbleStart,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JtGuideRow extends ConsumerStatefulWidget {
  final ChannelModel channel;
  final JtGuideDay day;
  final JtGuideController guide;
  final bool selected;
  final ChannelProgram? selectedProgram;
  final ScrollController Function() register;
  final void Function(ScrollController controller) unregister;
  final void Function(double offset) scrollAllTo;
  final Function(ChannelProgram program) onProgramSelected;
  final Function(ChannelProgram program) onLongPressProgram;

  const _JtGuideRow({
    required this.channel,
    required this.day,
    required this.guide,
    required this.selected,
    required this.selectedProgram,
    required this.register,
    required this.unregister,
    required this.scrollAllTo,
    required this.onProgramSelected,
    required this.onLongPressProgram,
    super.key,
  });

  @override
  ConsumerState<_JtGuideRow> createState() => _JtGuideRowState();
}

class _JtGuideRowState extends ConsumerState<_JtGuideRow> implements JtGuideRowHandle {
  late final ScrollController _scroll = widget.register();
  final FocusNode _group = FocusNode(debugLabel: 'jt-guide-row', skipTraversal: true, canRequestFocus: false);
  final GlobalKey _contentKey = GlobalKey();
  bool _ready = false;

  @override
  String get channelId => widget.channel.id;

  @override
  FocusNode get group => _group;

  @override
  bool get ready => _ready;

  @override
  List<FocusNode> get cells {
    final nodes = _group.traversalDescendants.where((n) => n.canRequestFocus && n.context != null).toList()
      ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    return nodes;
  }

  @override
  bool focus(JtGuideFocusRequest request) {
    final nodes = cells;
    if (nodes.isEmpty) return false;
    final FocusNode target;
    switch (request.mode) {
      case JtGuideFocusMode.first:
        target = nodes.first;
      case JtGuideFocusMode.last:
        target = nodes.last;
      case JtGuideFocusMode.at:
        final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
        final time = request.time;
        if (box == null || time == null) {
          target = nodes.first;
        } else {
          final x = box.localToGlobal(Offset(widget.day.offsetOf(time), 0)).dx;
          target = nodes.firstWhere(
            (n) => n.rect.left <= x && x < n.rect.right,
            orElse: () => nodes.lastWhere((n) => n.rect.left <= x, orElse: () => nodes.first),
          );
        }
    }
    target.requestFocus();
    return true;
  }

  @override
  void initState() {
    super.initState();
    widget.guide.rows[channelId] = this;
    _ensure();
  }

  @override
  void didUpdateWidget(covariant _JtGuideRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      widget.guide.rows.remove(oldWidget.channel.id);
      widget.guide.rows[channelId] = this;
    }
    _ensure();
  }

  void _ensure() {
    final day = widget.day;
    Future.microtask(() {
      if (mounted) ref.read(jtGuideCacheProvider.notifier).ensure(day, channelId);
    });
  }

  @override
  void dispose() {
    if (widget.guide.rows[channelId] == this) widget.guide.rows.remove(channelId);
    widget.unregister(_scroll);
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final (entry, loading) =
        ref.watch(jtGuideCacheProvider.select((s) => (s.entry(day, channelId), s.isLoading(day, channelId))));
    final showSpinner = entry == null;
    _ready = !showSpinner;
    if (widget.guide.pendingFocus?.channelId == channelId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.guide.tryFocus();
      });
    }
    final channel = widget.channel;

    return RepaintBoundary(
      child: SizedBox(
        height: GuideConstants.channelRowHeight,
        child: Row(
          children: [
            Container(
              width: GuideConstants.leftColumnWidth,
              height: GuideConstants.channelRowHeight,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      child: channel.images != null
                          ? AspectRatio(
                              aspectRatio: 1,
                              child: FladderImage(
                                image: channel.images?.primary,
                                fit: BoxFit.contain,
                              ),
                            )
                          : const Icon(Icons.tv),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _group,
                onFocusChange: (hasFocus) {
                  if (hasFocus) widget.guide.focusedChannelId = channelId;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    key: _contentKey,
                    width: day.timelineWidth,
                    height: GuideConstants.channelRowHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ChannelRow(
                          channel: channel,
                          selectedProgram: widget.selectedProgram,
                          onProgramSelected: widget.onProgramSelected,
                          onLongPressProgram: widget.onLongPressProgram,
                          timelineStart: day.start,
                          timelineEnd: day.end,
                          programs: entry?.programs ?? const [],
                          loading: showSpinner && loading,
                          scrollToPosition: widget.scrollAllTo,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
