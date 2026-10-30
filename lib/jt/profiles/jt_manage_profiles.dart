import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jt/jt_defaults.dart';
import 'package:fladder/jt/profiles/jt_profile_flow.dart';
import 'package:fladder/jt/profiles/jt_profile_pin_store.dart';
import 'package:fladder/jt/profiles/jt_profile_widgets.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// "Profielen beheren": profiel toevoegen, pincode instellen/wijzigen/weghalen, profiel van dit
/// toestel verwijderen en (onder "Geavanceerd") een ander serveradres.
Future<void> showJtManageProfiles(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => const _JtManageProfilesDialog(),
    );

class _JtManageProfilesDialog extends ConsumerStatefulWidget {
  const _JtManageProfilesDialog();

  @override
  ConsumerState<_JtManageProfilesDialog> createState() => _JtManageProfilesDialogState();
}

class _JtManageProfilesDialogState extends ConsumerState<_JtManageProfilesDialog> {
  late final TextEditingController server =
      TextEditingController(text: JtDefaults.serverOverride(ref.read(sharedPreferencesProvider)) ?? '');

  @override
  void dispose() {
    server.dispose();
    super.dispose();
  }

  Future<void> _then(Future<void> action) async {
    await action;
    if (mounted) setState(() {});
  }

  Future<void> _saveServer() async {
    final value = server.text.trim();
    final lower = value.toLowerCase();
    if (value.isNotEmpty && !(lower.startsWith('https://') || lower.startsWith('http://'))) {
      FladderSnack.show(context.localized.invalidUrl, context: context);
      return;
    }
    await JtDefaults.setServerOverride(ref.read(sharedPreferencesProvider), value);
    ref.read(authProvider.notifier).jtServerChanged();
    if (!mounted) return;
    server.text = JtDefaults.serverOverride(ref.read(sharedPreferencesProvider)) ?? '';
    FladderSnack.show(context.localized.jtServerSaved, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = jtVisibleProfiles(ref.watch(authProvider.select((value) => value.accounts)));
    final store = ref.read(jtProfilePinStoreProvider);

    return Shortcuts(
      shortcuts: jtProfileArrowShortcuts,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.localized.jtProfilesManage, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        for (final (i, account) in accounts.indexed)
                          _profileRow(context, account, store, autofocus: i == 0),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: JtFocusRing(
                            child: TextButton.icon(
                              autofocus: accounts.isEmpty,
                              onPressed: () {
                                Navigator.of(context).pop();
                                ref.read(authProvider.notifier).addNewUser();
                              },
                              icon: const Icon(IconsaxPlusLinear.add),
                              label: Text(context.localized.jtProfilesAdd),
                            ),
                          ),
                        ),
                        const Divider(),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          leading: const Icon(IconsaxPlusLinear.setting_2),
                          title: Text(context.localized.jtAdvanced),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          children: [
                            TextField(
                              controller: server,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onSubmitted: (_) => _saveServer(),
                              decoration: InputDecoration(
                                labelText: context.localized.jtServerAddress,
                                hintText: JtDefaults.defaultServer,
                                helperText: context.localized.jtServerDefault(JtDefaults.defaultServer),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              spacing: 8,
                              children: [
                                JtFocusRing(
                                  child: TextButton(
                                    onPressed: () {
                                      server.text = '';
                                      _saveServer();
                                    },
                                    child: Text(context.localized.jtServerReset),
                                  ),
                                ),
                                JtFocusRing(
                                  child: FilledButton.tonal(
                                    onPressed: _saveServer,
                                    child: Text(context.localized.save),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: JtFocusRing(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.localized.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileRow(BuildContext context, AccountModel account, JtProfilePinStore store, {bool autofocus = false}) {
    final cached = store.cached(account);
    final status = switch (cached?.hasPin) {
      true => context.localized.jtPinActive,
      false => context.localized.jtPinNone,
      null => '',
    };
    final hasPin = cached?.hasPin ?? false;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  JtProfileAvatar(account: account, size: 44),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.name, style: Theme.of(context).textTheme.titleMedium),
                      if (status.isNotEmpty) Text(status, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            JtFocusRing(
              child: FilledButton.tonalIcon(
                autofocus: autofocus,
                onPressed: () => _then(jtSetPin(context, ref, account)),
                icon: const Icon(IconsaxPlusLinear.password_check),
                label: Text(hasPin ? context.localized.jtPinChange : context.localized.jtPinSet),
              ),
            ),
            if (cached == null || hasPin)
              JtFocusRing(
                child: TextButton(
                  onPressed: () => _then(jtRemovePin(context, ref, account)),
                  child: Text(context.localized.jtPinRemove),
                ),
              ),
            JtFocusRing(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => _then(jtRemoveProfile(context, ref, account)),
                icon: const Icon(IconsaxPlusLinear.trash),
                label: Text(context.localized.jtProfileRemove),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
