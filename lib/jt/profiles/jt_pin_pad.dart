import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/jt/profiles/jt_profile_widgets.dart';
import 'package:fladder/util/localization_helper.dart';

/// Resultaat van [showJtPinPad]: de aanvaarde code, "vergeten" of geannuleerd (beide `null`).
class JtPinPadOutcome {
  final String? pin;
  final bool forgot;
  const JtPinPadOutcome._(this.pin, this.forgot);
  static const cancelled = JtPinPadOutcome._(null, false);
  static const forgotten = JtPinPadOutcome._(null, true);
}

/// Controle van een ingevoerde code: `null` = goed, anders de foutmelding.
typedef JtPinCheck = Future<String?> Function(String pin);

/// Numeriek toetsenblok op het scherm (D-pad) plus cijfertoetsen van afstandsbediening of toetsenbord.
/// Na het vierde cijfer gaat de code meteen naar [check]. [lockedUntil] wordt na elke poging opnieuw
/// gelezen; zolang die in de toekomst ligt, is het blok uitgeschakeld en loopt er een aftelling.
Future<JtPinPadOutcome> showJtPinPad(
  BuildContext context, {
  required String title,
  Widget? header,
  JtPinCheck? check,
  DateTime? Function()? lockedUntil,
  bool showForgot = false,
}) async {
  final result = await showDialog<JtPinPadOutcome>(
    context: context,
    barrierDismissible: true,
    builder: (context) => JtPinPadDialog(
      title: title,
      header: header,
      check: check,
      lockedUntil: lockedUntil,
      showForgot: showForgot,
    ),
  );
  return result ?? JtPinPadOutcome.cancelled;
}

class JtPinPadDialog extends StatefulWidget {
  final String title;
  final Widget? header;
  final JtPinCheck? check;
  final DateTime? Function()? lockedUntil;
  final bool showForgot;
  const JtPinPadDialog({
    required this.title,
    this.header,
    this.check,
    this.lockedUntil,
    this.showForgot = false,
    super.key,
  });

  @override
  State<JtPinPadDialog> createState() => _JtPinPadDialogState();
}

class _JtPinPadDialogState extends State<JtPinPadDialog> {
  String entered = '';
  String? error;
  bool busy = false;
  Timer? ticker;

  static final _digitKeys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  DateTime? get _lockedUntil {
    final until = widget.lockedUntil?.call();
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    if (_lockedUntil != null) {
      ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_lockedUntil == null) {
          ticker?.cancel();
          ticker = null;
          error = null;
        }
      });
    }
  }

  Future<void> _add(String digit) async {
    if (busy || _lockedUntil != null || entered.length >= JtPin.length) return;
    setState(() {
      entered += digit;
      error = null;
    });
    if (entered.length < JtPin.length) return;
    final pin = entered;
    setState(() => busy = true);
    final message = await widget.check?.call(pin);
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(JtPinPadOutcome._(pin, false));
      return;
    }
    setState(() {
      busy = false;
      entered = '';
      error = message;
    });
    _syncTicker();
  }

  void _backspace() {
    if (busy || _lockedUntil != null || entered.isEmpty) return;
    setState(() => entered = entered.substring(0, entered.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final digit = _digitKeys[event.logicalKey];
    if (digit != null) {
      _add(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lockedUntil = _lockedUntil;
    final locked = lockedUntil != null;
    final seconds = locked ? (lockedUntil.difference(DateTime.now()).inMilliseconds / 1000).ceil() : 0;
    final message = locked ? context.localized.jtPinLocked(seconds.toString()) : error;
    final height = MediaQuery.sizeOf(context).height;
    final keySize = (height / 9).clamp(44.0, 64.0);

    Widget key(String label, {VoidCallback? onTap, IconData? icon, bool autofocus = false, String? semantics}) {
      return JtFocusRing(
        radius: BorderRadius.circular(keySize),
        child: SizedBox.square(
          dimension: keySize,
          child: FilledButton.tonal(
            autofocus: autofocus,
            // Niet uitschakelen tijdens het slot: dan zou de focus van het blok verdwijnen.
            onPressed: onTap,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              textStyle: theme.textTheme.headlineSmall,
            ),
            child: icon != null ? Icon(icon, semanticLabel: semantics) : Text(label),
          ),
        ),
      );
    }

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Focus(
      onKeyEvent: _onKey,
      child: Shortcuts(
        shortcuts: jtProfileArrowShortcuts,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.header != null) ...[widget.header!, const SizedBox(height: 8)],
                  Text(widget.title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(JtPin.length, (i) {
                      final filled = i < entered.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? scheme.primary : Colors.transparent,
                          border: Border.all(color: filled ? scheme.primary : scheme.onSurfaceVariant, width: 2),
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: message == null
                          ? null
                          : Text(
                              message,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                            ),
                    ),
                  ),
                  FocusTraversalGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        for (final row in rows)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 16,
                            children: [
                              for (final d in row) key(d, onTap: () => _add(d), autofocus: d == '1'),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 16,
                          children: [
                            key('', icon: IconsaxPlusLinear.close_circle, semantics: context.localized.cancel,
                                onTap: () => Navigator.of(context).pop(JtPinPadOutcome.cancelled)),
                            key('0', onTap: () => _add('0')),
                            key('', icon: IconsaxPlusLinear.arrow_left_1, semantics: context.localized.jtPinBackspace,
                                onTap: _backspace),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.showForgot) ...[
                    const SizedBox(height: 12),
                    JtFocusRing(
                      child: TextButton(
                        onPressed: busy ? null : () => Navigator.of(context).pop(JtPinPadOutcome.forgotten),
                        child: Text(context.localized.jtPinForgot),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
