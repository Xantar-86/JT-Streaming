import 'package:flutter/widgets.dart';

import 'package:fladder/jt/jt_theme.dart';
import 'package:fladder/models/view_model.dart';

/// Key die een rij van het startscherm markeert, zodat [JtHome.arrange] ze kan ordenen of verbergen.
/// Gebruik: `PosterRow(key: const JtRowKey(JtHomeRow.liveTv), ...)`.
class JtRowKey extends ValueKey<(JtHomeRow, String?)> {
  const JtRowKey(JtHomeRow row, [String? id]) : super((row, id));

  JtHomeRow get row => value.$1;
}

extension JtArrangeRows on List<Widget> {
  /// Zie [JtHome.arrange].
  List<Widget> jtArrange() => JtHome.arrange(this);
}

/// Startscherm-logica op basis van [JtTheme.homeRows], [JtTheme.homeLibrariesOnly] en
/// [JtTheme.homeLibrariesHidden].
abstract final class JtHome {
  /// Of [row] getoond wordt.
  static bool shows(JtHomeRow row) => JtTheme.homeRows.contains(row);

  static JtHomeRow? _rowOf(Widget child) {
    final key = child.key;
    return key is JtRowKey ? key.row : null;
  }

  /// Sorteert de rijen volgens [JtTheme.homeRows] en laat rijen weg die er niet in staan.
  /// Niet-gemarkeerde widgets komen achteraan; de volgorde binnen een rij-type
  /// (bv. "Recent toegevoegd" per bibliotheek) blijft behouden.
  static List<Widget> arrange(List<Widget> children) {
    int rank(Widget child) {
      final row = _rowOf(child);
      return row == null ? JtTheme.homeRows.length : JtTheme.homeRows.indexOf(row);
    }

    final visible = children.where((child) {
      final row = _rowOf(child);
      return row == null || shows(row);
    }).toList();
    final indexed = visible.indexed.toList()
      ..sort((a, b) {
        final byRank = rank(a.$2).compareTo(rank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return indexed.map((e) => e.$2).toList();
  }

  /// Of de bibliotheek [view] een "Recent toegevoegd"-rij op het startscherm krijgt.
  static bool showLibrary(ViewModel view) {
    final only = JtTheme.homeLibrariesOnly;
    if (only != null && !only.contains(view.name)) return false;
    return !JtTheme.homeLibrariesHidden.contains(view.name);
  }
}
