import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fladder/jt/guide/jt_guide_controller.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/util/localization_helper.dart';

String jtGuideLocale(BuildContext context) => Localizations.localeOf(context).toString();

/// "wo 21 okt" / "Wed 21 Oct".
String jtGuideShortDay(BuildContext context, JtGuideDay day) =>
    DateFormat('EEE d MMM', jtGuideLocale(context)).format(day.start);

/// "Vandaag", "Morgen", "Gisteren", else "vr 23 okt".
String jtGuideDayLabel(BuildContext context, JtGuideDay day, DateTime now) {
  final today = JtGuideDay.of(now);
  if (day == today) return context.localized.jtGuideToday;
  if (day == today.addDays(1)) return context.localized.jtGuideTomorrow;
  if (day == today.addDays(-1)) return context.localized.jtGuideYesterday;
  return jtGuideShortDay(context, day);
}

/// "woensdag 21 oktober · 18:00–20:45" (EN "Wednesday 21 October · 18:00–20:45").
String jtGuideWindowText(BuildContext context, DateTime from, DateTime to) {
  final locale = jtGuideLocale(context);
  final hm = DateFormat('HH:mm', locale);
  return context.localized.jtGuideWindow(DateFormat('EEEE d MMMM', locale).format(from), hm.format(from), hm.format(to));
}

/// Day picker (§3): one button per day of the EPG coverage, autofocus on the
/// shown day.
Future<void> showJtGuideDayPicker(BuildContext context, JtGuideController guide, JtGuideRange range) {
  final now = guide.now();
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.localized.jtGuidePickDay),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            for (final day in range.days)
              ElevatedButton(
                autofocus: day == guide.day,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  guide.pickDay(day);
                },
                child: Text(jtGuideDayLabel(dialogContext, day, now)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.localized.close),
        ),
      ],
    ),
  );
}

/// Hour picker (§3): 24 buttons 00:00 … 23:00 in a 6 x 4 grid, no clock dial
/// (which works badly with a D-pad). Autofocus on the current hour.
Future<void> showJtGuideHourPicker(BuildContext context, JtGuideController guide) {
  final current = guide.anchor.hour;
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.localized.jtGuidePickHour),
      content: SizedBox(
        width: 6 * 96,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var hour = 0; hour < 24; hour++)
              SizedBox(
                width: 88,
                child: ElevatedButton(
                  autofocus: hour == current,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    guide.pickHour(hour);
                  },
                  child: Text('${hour.toString().padLeft(2, '0')}:00'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.localized.close),
        ),
      ],
    ),
  );
}
