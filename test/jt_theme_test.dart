import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jt/jt_home.dart';
import 'package:fladder/jt/jt_theme.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/theme.dart';

void main() {
  group('JtHome.arrange', () {
    test('orders tagged rows by JtTheme.homeRows and keeps the order within a row type', () {
      const libA = SizedBox(key: JtRowKey(JtHomeRow.latestPerLibrary, 'a'));
      const libB = SizedBox(key: JtRowKey(JtHomeRow.latestPerLibrary, 'b'));
      const nextUp = SizedBox(key: JtRowKey(JtHomeRow.nextUp));
      const live = SizedBox(key: JtRowKey(JtHomeRow.liveTv));
      const untagged = SizedBox(key: ValueKey('other'));

      final arranged = JtHome.arrange([libA, untagged, nextUp, libB, live]);

      final expected = [...JtTheme.homeRows.where((r) => r != JtHomeRow.banner)];
      int pos(JtHomeRow row) => expected.indexOf(row);
      final rows = arranged.map((w) => w.key is JtRowKey ? (w.key as JtRowKey).row : null).toList();
      final tagged = rows.nonNulls.toList();
      for (var i = 1; i < tagged.length; i++) {
        expect(pos(tagged[i - 1]) <= pos(tagged[i]), isTrue);
      }
      expect(arranged.indexOf(libA) < arranged.indexOf(libB), isTrue);
      expect(arranged.last, untagged);
      expect(arranged.length, 5);
    });
  });

  group('JtTheme', () {
    test('channel tiles are landscape', () {
      expect(FladderItemType.tvchannel.aspectRatio, greaterThan(1));
      expect(FladderItemType.movie.aspectRatio, 0.55);
    });

    test('default scheme uses the JT accent', () {
      final scheme = FladderTheme.defaultScheme(Brightness.dark);
      if (JtTheme.exactAccent) expect(scheme.primary, JtTheme.accent);
      final theme = FladderTheme.theme(scheme, DynamicSchemeVariant.tonalSpot);
      if (JtTheme.exactAccent) expect(theme.colorScheme.primary, JtTheme.accent);
    });

    test('radius comes from JtTheme', () {
      expect(FladderTheme.smallShape.borderRadius, BorderRadius.circular(JtTheme.radiusSmall));
    });
  });
}
