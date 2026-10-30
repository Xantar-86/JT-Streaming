import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jt/jt_brand.dart';
import 'package:fladder/jt/profiles/jt_manage_profiles.dart';
import 'package:fladder/jt/profiles/jt_profile_flow.dart';
import 'package:fladder/jt/profiles/jt_profile_widgets.dart';
import 'package:fladder/jt/widgets/jt_login_background.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/util/localization_helper.dart';

/// `false` = upstream gebruikersraster en zwevende knoppen terug op de aanmeldpagina.
const bool jtProfilesEnabled = true;

/// "Wie kijkt er?" (WP3.1): de profielen die op dit toestel al eens ingelogd zijn, plus
/// "Profiel toevoegen" en "Profielen beheren". Vervangt bij JT-Streaming het upstream gebruikersraster.
class JtProfilesScreen extends ConsumerStatefulWidget {
  final List<AccountModel> accounts;
  const JtProfilesScreen({required this.accounts, super.key});

  @override
  ConsumerState<JtProfilesScreen> createState() => _JtProfilesScreenState();
}

class _JtProfilesScreenState extends ConsumerState<JtProfilesScreen> {
  bool busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final profiles = jtVisibleProfiles(widget.accounts);
    final lastUsed = profiles.sorted((a, b) => a.lastUsed.compareTo(b.lastUsed)).lastOrNull;
    final avatar = (size.shortestSide * 0.2).clamp(84.0, 150.0);
    final compact = size.width < 600;

    return JtLoginBackground(
      child: Shortcuts(
        shortcuts: jtProfileArrowShortcuts,
        child: FocusTraversalGroup(
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: 24,
                  top: 16,
                  child: ExcludeSemantics(
                    child: Row(
                      spacing: 12,
                      children: [
                        JtBrand.icon(compact ? 36 : 48),
                        if (!compact)
                          Text(JtBrand.appName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  top: compact ? 64 : 80,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.localized.jtProfilesTitle,
                            textAlign: TextAlign.center,
                            style: (compact ? theme.textTheme.headlineMedium : theme.textTheme.displaySmall)
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: compact ? 24 : 40),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: compact ? 12 : 32,
                              runSpacing: 24,
                              children: [
                                for (final profile in profiles)
                                  JtProfileTile(
                                    key: ValueKey('jt-profile-${profile.credentials.serverId}-${profile.id}'),
                                    size: avatar,
                                    label: profile.name,
                                    autofocus: lastUsed != null && profile.sameIdentity(lastUsed),
                                    circle: JtProfileAvatar(account: profile, size: avatar),
                                    onTap: () => _run(() => jtEnterProfile(context, ref, profile)),
                                  ),
                                JtProfileTile(
                                  key: const ValueKey('jt-profile-add'),
                                  size: avatar,
                                  label: context.localized.jtProfilesAdd,
                                  autofocus: lastUsed == null,
                                  circle: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                                    ),
                                    child: Icon(IconsaxPlusLinear.add, size: avatar * 0.4),
                                  ),
                                  onTap: () => ref.read(authProvider.notifier).addNewUser(),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? 32 : 48),
                          JtFocusRing(
                            child: OutlinedButton.icon(
                              key: const ValueKey('jt-profiles-manage'),
                              onPressed: () => showJtManageProfiles(context),
                              icon: const Icon(IconsaxPlusLinear.edit_2),
                              label: Text(context.localized.jtProfilesManage),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
