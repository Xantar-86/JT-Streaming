import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/screens/live_tv/widgets/guide_constants.dart';

enum JtGuideFocusMode { first, last, at }

/// "Put the focus on this channel" after a jump; fulfilled by the row once its
/// programs are on screen (§4).
class JtGuideFocusRequest {
  final String channelId;
  final JtGuideFocusMode mode;
  final DateTime? time;
  final DateTime requestedAt;

  JtGuideFocusRequest(this.channelId, this.mode, {this.time}) : requestedAt = DateTime.now();

  bool get expired => DateTime.now().difference(requestedAt) > const Duration(seconds: 8);
}

/// What the keys and the controller need from a guide row.
abstract class JtGuideRowHandle {
  String get channelId;
  FocusNode get group;

  /// Focusable program cells, left to right.
  List<FocusNode> get cells;

  /// Programs are shown (not loading).
  bool get ready;

  bool focus(JtGuideFocusRequest request);
}

final jtGuideControllerProvider = ChangeNotifierProvider.autoDispose<JtGuideController>((ref) => JtGuideController(ref));

/// Shown day and the one jump function of the guide (§3): Now, hour, +/- hours
/// and day all go through [jumpTo].
class JtGuideController extends ChangeNotifier {
  final Ref ref;

  JtGuideController(this.ref) : _day = JtGuideDay.of(ref.read(jtGuideClockProvider)()) {
    Future.microtask(() => ref.read(jtGuideCacheProvider.notifier).pin(_day));
  }

  JtGuideDay _day;
  JtGuideDay get day => _day;

  ScrollController? _scroll;
  ScrollController? get scroll => _scroll;

  DateTime? _anchor;
  double? _anchorOffset;

  JtGuideRange? range;
  JtGuideFocusRequest? pendingFocus;
  String? focusedChannelId;
  String? firstVisibleChannelId;

  /// Scrolls the guide vertically to a channel that is not built yet.
  void Function(String channelId)? revealChannel;

  final Map<String, JtGuideRowHandle> rows = {};

  DateTime now() => ref.read(jtGuideClockProvider)();

  bool get isToday => _day == JtGuideDay.of(now());

  void attach(ScrollController controller) => _scroll = controller;

  void detach(ScrollController controller) {
    if (_scroll == controller) _scroll = null;
  }

  double get viewport => (_scroll?.hasClients ?? false) ? _scroll!.position.viewportDimension : 0;
  double get offset => (_scroll?.hasClients ?? false) ? _scroll!.offset : 0;

  DateTime get visibleStart => _day.timeAt(offset);
  DateTime get visibleEnd {
    final end = _day.timeAt(offset + viewport);
    return end.isAfter(_day.end) ? _day.end : end;
  }

  /// The time the user is "at": the last jump target while the scroll has not
  /// moved, else the visible start plus the lead.
  DateTime get anchor {
    if (_anchor != null && _anchorOffset != null && (offset - _anchorOffset!).abs() < 1) return _anchor!;
    return _day.clampTime(visibleStart.add(const Duration(minutes: jtGuideLeadMinutes)));
  }

  int get stepMinutes => jtGuideStep(viewport / GuideConstants.widthPerMinute);

  void jumpTo(DateTime t, {JtGuideFocusRequest? focus, bool animate = true}) {
    var day = JtGuideDay.of(t);
    final range = this.range;
    if (range != null && !range.contains(day)) {
      if (day.isBefore(range.first)) {
        day = range.first;
        t = day.start;
      } else {
        day = range.last;
        t = day.end;
      }
    }
    t = day.clampTime(t);
    final changed = day != _day;
    _day = day;
    ref.read(jtGuideCacheProvider.notifier).pin(day);
    final target = jtGuideScrollOffset(day, t, viewport: viewport);
    _anchor = t;
    _anchorOffset = target;
    pendingFocus = focus;
    notifyListeners();

    void scrollNow() {
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      final max = scroll.position.maxScrollExtent;
      final clamped = target > max ? max : target;
      _anchorOffset = clamped;
      if (animate && !changed) {
        scroll.animateTo(clamped, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      } else {
        scroll.jumpTo(clamped);
      }
    }

    if (changed) {
      // The new day has its own timeline width; scroll after the rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollNow());
    } else {
      scrollNow();
    }
  }

  String? get _focusChannel => focusedChannelId ?? firstVisibleChannelId;

  /// "Earlier"/"Later": +/- [stepMinutes]; over midnight the day changes.
  void step(int direction) => jumpTo(anchor.add(Duration(minutes: direction * stepMinutes)));

  /// "Now": today, now line visible, focus on the running program.
  void goNow({bool focus = true}) {
    final t = now();
    final channel = _focusChannel;
    jumpTo(t, focus: focus && channel != null ? JtGuideFocusRequest(channel, JtGuideFocusMode.at, time: t) : null);
  }

  /// Day picker: today = now, otherwise the same clock time on that day.
  void pickDay(JtGuideDay target) {
    if (target == JtGuideDay.of(now())) {
      goNow(focus: false);
    } else {
      jumpTo(target.atClockOf(anchor));
    }
  }

  void pickHour(int hour) => jumpTo(_day.hour(hour));

  bool canShowDay(JtGuideDay target) => range?.contains(target) ?? true;

  /// PageUp/PageDown (+ aliases): previous/next day, same clock time, same
  /// channel.
  void changeDay(int delta) {
    final target = _day.addDays(delta);
    if (!canShowDay(target)) return;
    final t = target.atClockOf(anchor);
    final channel = _focusChannel;
    jumpTo(t, focus: channel != null ? JtGuideFocusRequest(channel, JtGuideFocusMode.at, time: t) : null);
  }

  /// Arrow past the last/first program of a row: next day 00:00 (first
  /// program) or previous day 23:00 (last program), same channel. Nothing on
  /// the first/last day of the coverage.
  bool edgeJump(int direction, String channelId) {
    final target = _day.addDays(direction);
    if (!canShowDay(target)) return false;
    if (direction > 0) {
      jumpTo(target.start, focus: JtGuideFocusRequest(channelId, JtGuideFocusMode.first));
    } else {
      jumpTo(target.hour(23), focus: JtGuideFocusRequest(channelId, JtGuideFocusMode.last));
    }
    return true;
  }

  /// Called by rows after a build; fulfils the pending focus request.
  void tryFocus() {
    final request = pendingFocus;
    if (request == null) return;
    if (request.expired) {
      pendingFocus = null;
      return;
    }
    final row = rows[request.channelId];
    if (row == null) {
      revealChannel?.call(request.channelId);
      return;
    }
    if (!row.ready) return;
    if (row.focus(request)) pendingFocus = null;
  }

  JtGuideRowHandle? rowOf(FocusNode? node) {
    if (node == null) return null;
    for (final row in rows.values) {
      if (node == row.group || node.ancestors.contains(row.group)) return row;
    }
    return null;
  }
}
