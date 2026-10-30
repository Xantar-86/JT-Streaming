import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/util/custom_cache_manager.dart';

/// Pijltoetsen = focus verplaatsen, ook op web (daar zijn ze standaard ScrollIntent, zie WP2.8c D3).
const Map<ShortcutActivator, Intent> jtProfileArrowShortcuts = {
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
};

/// Vaste kleuren voor profielen zonder foto; de naam kiest er altijd dezelfde uit.
const List<Color> _jtAvatarColors = [
  Color(0xFFD88F48),
  Color(0xFF4F8A8B),
  Color(0xFF8E5BA8),
  Color(0xFF3F7CC2),
  Color(0xFFC0504D),
  Color(0xFF5E9B4F),
  Color(0xFFB5838D),
  Color(0xFF6C6F93),
];

Color jtAvatarColor(String name) {
  var h = 0;
  for (final c in name.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _jtAvatarColors[h % _jtAvatarColors.length];
}

String jtInitial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// Ronde profielfoto (Jellyfin-gebruikersfoto) of een gekleurde cirkel met de beginletter.
class JtProfileAvatar extends StatelessWidget {
  final AccountModel account;
  final double size;
  const JtProfileAvatar({required this.account, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: jtAvatarColor(account.name),
      alignment: Alignment.center,
      child: Text(
        jtInitial(account.name),
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: account.avatar.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: account.avatar,
                cacheManager: CustomCacheManager.instance,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
                memCacheHeight: (size * 2).round(),
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}

/// Grote ronde tegel met naam eronder. Focus (D-pad/toetsenbord) en muisaanwijzer
/// geven een dikke rand in de accentkleur en een lichte vergroting.
class JtProfileTile extends StatefulWidget {
  final Widget circle;
  final String label;
  final double size;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final IconData? badge;
  const JtProfileTile({
    required this.circle,
    required this.label,
    required this.size,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.badge,
    super.key,
  });

  @override
  State<JtProfileTile> createState() => _JtProfileTileState();
}

class _JtProfileTileState extends State<JtProfileTile> {
  bool focused = false;
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = focused || hovered;
    final ring = widget.size * 0.04 + 2;
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onFocusChange: (value) => setState(() => focused = value),
        onHover: (value) => setState(() => hovered = value),
        customBorder: const CircleBorder(),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: widget.size + ring * 2 + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: active ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.all(ring),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: focused ? scheme.primary : (hovered ? scheme.onSurface : Colors.transparent),
                          width: ring,
                        ),
                      ),
                      child: SizedBox.square(dimension: widget.size - ring * 2, child: widget.circle),
                    ),
                    if (widget.badge != null)
                      Positioned(
                        right: ring,
                        bottom: ring,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                          child: Icon(widget.badge, size: widget.size * 0.14, color: scheme.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.8),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rand in de accentkleur rond elk element dat de focus krijgt (knoppen in dialogen e.d.).
class JtFocusRing extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  const JtFocusRing({required this.child, this.radius = const BorderRadius.all(Radius.circular(28)), super.key});

  @override
  State<JtFocusRing> createState() => _JtFocusRingState();
}

class _JtFocusRingState extends State<JtFocusRing> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final highlight = focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          border: Border.all(
            color: highlight ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: widget.child,
      ),
    );
  }
}
