import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fladder/jt/jt_theme.dart';

/// Gedempt achtergrondbeeld achter de aanmeldpagina. Alle waarden staan in [JtTheme]
/// (`loginBackground*`); met [JtTheme.loginBackground] = `false` is dit gewoon [child].
class JtLoginBackground extends StatelessWidget {
  final Widget child;
  const JtLoginBackground({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    if (!JtTheme.loginBackground) return child;
    final base = Theme.of(context).scaffoldBackgroundColor;
    Widget image = Image.asset(
      JtTheme.loginBackgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      opacity: const AlwaysStoppedAnimation(JtTheme.loginBackgroundOpacity),
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    if (JtTheme.loginBackgroundBlur > 0) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: JtTheme.loginBackgroundBlur,
          sigmaY: JtTheme.loginBackgroundBlur,
          tileMode: TileMode.clamp,
        ),
        child: image,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        image,
        if (JtTheme.loginBackgroundOverlay > 0)
          ColoredBox(color: base.withValues(alpha: JtTheme.loginBackgroundOverlay)),
        child,
      ],
    );
  }
}
