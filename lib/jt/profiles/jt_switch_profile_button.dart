import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_button.dart';

/// Terug naar "Wie kijkt er?". `logoutUser` stopt eerst een lopende afspeelsessie
/// (videoPlayerProvider.stop, meldt het einde aan Jellyfin); het profiel blijft op dit toestel.
Future<void> jtSwitchProfile(BuildContext context, WidgetRef ref) async {
  await ref.read(userProvider.notifier).logoutUser();
  if (context.mounted) await context.router.replaceAll([LoginRoute()]);
}

/// Knop "Wissel van profiel" in de zijbalk en de lade, onder de gebruikersavatar.
class JtSwitchProfileButton extends ConsumerWidget {
  final bool expanded;
  const JtSwitchProfileButton({required this.expanded, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavigationButton(
      key: const ValueKey('jt-switch-profile'),
      label: context.localized.jtProfileSwitch,
      selectedIcon: const Icon(IconsaxPlusBold.arrow_swap_horizontal),
      icon: const Icon(IconsaxPlusLinear.arrow_swap_horizontal),
      horizontal: true,
      expanded: expanded,
      onPressed: () => jtSwitchProfile(context, ref),
    );
  }
}
