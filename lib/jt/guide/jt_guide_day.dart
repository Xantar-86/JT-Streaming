import 'package:fladder/screens/live_tv/widgets/guide_constants.dart';

/// One local calendar day of the guide (ontwerp-gids-navigatie §2.1). Value
/// type: the absolute date is the cache key, so "Today" only moves its label
/// after midnight.
class JtGuideDay implements Comparable<JtGuideDay> {
  final int year;
  final int month;
  final int day;

  const JtGuideDay(this.year, this.month, this.day);

  factory JtGuideDay.of(DateTime t) {
    final local = t.toLocal();
    return JtGuideDay(local.year, local.month, local.day);
  }

  /// Local midnight. Never `start.add(Duration(hours: 24))` for the end: on
  /// 25/10/2026 the day lasts 25 h, on 28/03/2027 23 h.
  DateTime get start => DateTime(year, month, day);
  DateTime get end => DateTime(year, month, day + 1);

  int get minutes => end.difference(start).inMinutes;
  double get timelineWidth => (minutes * GuideConstants.widthPerMinute).toDouble();

  JtGuideDay addDays(int days) => JtGuideDay.of(DateTime(year, month, day + days));

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// The same wall-clock time on this day (PageUp/PageDown, day picker).
  DateTime atClockOf(DateTime t) => clampTime(DateTime(year, month, day, t.hour, t.minute));

  DateTime clampTime(DateTime t) {
    if (t.isBefore(start)) return start;
    final last = end.subtract(const Duration(minutes: 1));
    return t.isAfter(last) ? last : t;
  }

  /// First instant of this day whose local hour is [hour]. On 25/10 "02:00"
  /// is the first (CEST) one; on 28/03 02:00 does not exist and 03:00 is used.
  DateTime hour(int hour) {
    for (var t = start; t.isBefore(end); t = t.add(const Duration(hours: 1))) {
      if (t.hour >= hour) return t;
    }
    return end.subtract(const Duration(hours: 1));
  }

  /// Pixel offset of [t] on this day's timeline (absolute minutes, so the
  /// repeated hour on 25/10 gets its own place).
  double offsetOf(DateTime t) => (t.difference(start).inSeconds * GuideConstants.widthPerMinute / 60.0).toDouble();

  /// Time at pixel offset [px] on this day's timeline.
  DateTime timeAt(double px) => start.add(Duration(seconds: (px * 60 / GuideConstants.widthPerMinute).round()));

  @override
  bool operator ==(Object other) =>
      other is JtGuideDay && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  int compareTo(JtGuideDay other) => start.compareTo(other.start);

  bool isBefore(JtGuideDay other) => compareTo(other) < 0;
  bool isAfter(JtGuideDay other) => compareTo(other) > 0;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// Lead before a jump target, same as the focus autoscroll in ChannelRow.
const jtGuideLeadMinutes = 10;

/// Step of the "Earlier"/"Later" buttons: 0.75 x the visible window, rounded
/// down to 30 min, between 60 and 180 min (§3).
int jtGuideStep(double viewportMinutes) {
  final raw = (viewportMinutes * 0.75).floor();
  final rounded = (raw ~/ 30) * 30;
  return rounded.clamp(60, 180);
}

/// Scroll offset for a jump to [t] on [day]: 10 min lead, clamped to the
/// timeline.
double jtGuideScrollOffset(JtGuideDay day, DateTime t, {double viewport = 0}) {
  final raw = day.offsetOf(t) - GuideConstants.widthPerMinute * jtGuideLeadMinutes;
  final max = (day.timelineWidth - viewport).clamp(0.0, double.infinity);
  return raw.clamp(0.0, max).toDouble();
}

/// Labels every [intervalMinutes] in absolute time from the day start, so
/// "02:00" appears twice on 25/10.
List<DateTime> jtGuideTimeLabels(JtGuideDay day, {int intervalMinutes = 30}) {
  final labels = <DateTime>[];
  for (var t = day.start; t.isBefore(day.end); t = t.add(Duration(minutes: intervalMinutes))) {
    labels.add(t);
  }
  return labels;
}

/// A program belongs to a day when it overlaps it; Jellyfin's bounds are
/// inclusive, so the client filters strictly (§2.2).
bool jtGuideOverlaps(DateTime programStart, DateTime programEnd, JtGuideDay day) =>
    programEnd.isAfter(day.start) && programStart.isBefore(day.end);

/// The days the day picker offers: earliest start through latest end, today
/// always included.
class JtGuideRange {
  final JtGuideDay first;
  final JtGuideDay last;

  const JtGuideRange(this.first, this.last);

  factory JtGuideRange.fromTimes(DateTime? earliestStart, DateTime? latestEnd, DateTime now) {
    final today = JtGuideDay.of(now);
    var first = earliestStart != null ? JtGuideDay.of(earliestStart) : today;
    // A program ending exactly at midnight does not make the next day available.
    var last = latestEnd != null ? JtGuideDay.of(latestEnd.subtract(const Duration(microseconds: 1))) : today;
    if (today.isBefore(first)) first = today;
    if (today.isAfter(last)) last = today;
    return JtGuideRange(first, last);
  }

  factory JtGuideRange.week(DateTime now) {
    final today = JtGuideDay.of(now);
    return JtGuideRange(today, today.addDays(6));
  }

  List<JtGuideDay> get days {
    final result = <JtGuideDay>[];
    for (var d = first; !d.isAfter(last); d = d.addDays(1)) {
      result.add(d);
    }
    return result;
  }

  bool contains(JtGuideDay day) => !day.isBefore(first) && !day.isAfter(last);

  @override
  bool operator ==(Object other) => other is JtGuideRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$first..$last';
}
