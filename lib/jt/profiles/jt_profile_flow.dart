import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/jt/profiles/jt_pin_pad.dart';
import 'package:fladder/jt/profiles/jt_profile_pin_store.dart';
import 'package:fladder/jt/profiles/jt_profile_widgets.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// Profielen die nooit op "Wie kijkt er?" verschijnen (testaccount van The Forge).
const Set<String> jtHiddenProfiles = {'forge-test'};

List<AccountModel> jtVisibleProfiles(List<AccountModel> accounts) =>
    accounts.where((a) => !jtHiddenProfiles.contains(a.name.trim().toLowerCase())).toList();

/// Haalt de actuele stand op; bij een verlopen token eerst het wachtwoord.
/// `null` = niet verder (geannuleerd of server onbereikbaar zonder lokale kopie).
Future<({AccountModel account, JtPinRecord record, bool viaPassword})?> _resolve(
  BuildContext context,
  WidgetRef ref,
  AccountModel account,
) async {
  final store = ref.read(jtProfilePinStoreProvider);
  final fetch = await store.fetch(account);
  if (!context.mounted) return null;
  switch (fetch) {
    case JtPinFetched(:final record):
      return (account: account, record: record, viaPassword: false);
    case JtPinUnauthorized():
      final updated = await jtAskPassword(context, ref, account);
      if (updated == null || !context.mounted) return null;
      final again = await store.fetch(updated);
      final record = switch (again) {
        JtPinFetched(:final record) => record,
        JtPinOffline(:final cached) => cached ?? JtPinRecord.none,
        JtPinUnauthorized() => JtPinRecord.none,
      };
      return (account: updated, record: record, viaPassword: true);
    case JtPinOffline(:final cached):
      if (cached == null) {
        FladderSnack.show(context.localized.jtServerUnreachable, context: context);
        return null;
      }
      return (account: account, record: cached, viaPassword: false);
  }
}

/// Vraagt de huidige code (met "vergeten" = wachtwoord). Geeft het (eventueel vernieuwde) profiel
/// terug als de persoon bewezen is, anders `null`.
Future<AccountModel?> _verifyPin(
  BuildContext context,
  WidgetRef ref,
  AccountModel account,
  JtPinRecord record,
  String title,
) async {
  final store = ref.read(jtProfilePinStoreProvider);
  final outcome = await showJtPinPad(
    context,
    title: title,
    header: JtProfileAvatar(account: account, size: 72),
    showForgot: true,
    lockedUntil: () => store.lockout(account).normalize(DateTime.now()).lockedUntil,
    check: (pin) async {
      final now = DateTime.now();
      var lock = store.lockout(account).normalize(now);
      if (lock.isLocked(now)) return context.localized.jtPinLocked(lock.remaining(now).inSeconds.toString());
      if (JtPin.verify(pin, record.hash)) {
        await store.resetLockout(account);
        return null;
      }
      lock = lock.fail(now);
      await store.setLockout(account, lock);
      if (!context.mounted) return '';
      return lock.isLocked(now)
          ? context.localized.jtPinLocked(lock.remaining(now).inSeconds.toString())
          : context.localized.jtPinWrong(lock.attemptsLeft.toString());
    },
  );
  if (!context.mounted) return null;
  if (outcome.forgot) return jtAskPassword(context, ref, account);
  return outcome.pin == null ? null : account;
}

/// Profiel kiezen op "Wie kijkt er?": pincode (indien ingesteld), dan inloggen met het bewaarde token.
Future<void> jtEnterProfile(BuildContext context, WidgetRef ref, AccountModel account) async {
  final resolved = await _resolve(context, ref, account);
  if (resolved == null || !context.mounted) return;
  var current = resolved.account;
  if (resolved.record.hasPin && !resolved.viaPassword) {
    final verified = await _verifyPin(context, ref, current, resolved.record, context.localized.jtPinEnter(current.name));
    if (verified == null || !context.mounted) return;
    current = verified;
  }
  // Upstream-afhandeling (houdt een eventueel oud lokaal slot van Fladder in stand).
  tapLoggedInAccount(context, current, ref);
}

/// Pincode instellen of wijzigen (bestaande code eerst bevestigen).
Future<void> jtSetPin(BuildContext context, WidgetRef ref, AccountModel account) async {
  final resolved = await _resolve(context, ref, account);
  if (resolved == null || !context.mounted) return;
  var current = resolved.account;
  if (resolved.record.hasPin && !resolved.viaPassword) {
    final verified = await _verifyPin(context, ref, current, resolved.record, context.localized.jtPinCurrent);
    if (verified == null || !context.mounted) return;
    current = verified;
  }
  final first = await showJtPinPad(
    context,
    title: context.localized.jtPinNew,
    header: JtProfileAvatar(account: current, size: 72),
  );
  if (first.pin == null || !context.mounted) return;
  final second = await showJtPinPad(
    context,
    title: context.localized.jtPinConfirm,
    header: JtProfileAvatar(account: current, size: 72),
    check: (pin) async => pin == first.pin ? null : context.localized.jtPinMismatch,
  );
  if (second.pin == null || !context.mounted) return;
  final ok = await ref.read(jtProfilePinStoreProvider).save(current, second.pin);
  if (!context.mounted) return;
  FladderSnack.show(ok ? context.localized.jtPinSaved : context.localized.jtServerUnreachable, context: context);
}

/// Pincode weghalen (huidige code of wachtwoord vereist).
Future<void> jtRemovePin(BuildContext context, WidgetRef ref, AccountModel account) async {
  final resolved = await _resolve(context, ref, account);
  if (resolved == null || !context.mounted) return;
  if (!resolved.record.hasPin) {
    FladderSnack.show(context.localized.jtPinNone, context: context);
    return;
  }
  var current = resolved.account;
  if (!resolved.viaPassword) {
    final verified = await _verifyPin(context, ref, current, resolved.record, context.localized.jtPinCurrent);
    if (verified == null || !context.mounted) return;
    current = verified;
  }
  final ok = await ref.read(jtProfilePinStoreProvider).save(current, null);
  if (!context.mounted) return;
  FladderSnack.show(ok ? context.localized.jtPinRemoved : context.localized.jtServerUnreachable, context: context);
}

/// Profiel van dit toestel weghalen, na bevestiging. `true` als het weg is.
Future<bool> jtRemoveProfile(BuildContext context, WidgetRef ref, AccountModel account) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.localized.jtProfileRemoveTitle(account.name)),
      content: Text(context.localized.jtProfileRemoveDesc),
      actions: [
        JtFocusRing(
          child: TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.localized.cancel),
          ),
        ),
        JtFocusRing(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.localized.delete),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await ref.read(sharedUtilityProvider).removeAccount(account);
  await ref.read(jtProfilePinStoreProvider).forget(account);
  ref.read(authProvider.notifier).getSavedAccounts();
  return true;
}

/// Opnieuw inloggen met het Jellyfin-wachtwoord (code vergeten of token verlopen).
Future<AccountModel?> jtAskPassword(BuildContext context, WidgetRef ref, AccountModel account) {
  return showDialog<AccountModel>(
    context: context,
    builder: (context) => _JtPasswordDialog(account: account),
  );
}

class _JtPasswordDialog extends ConsumerStatefulWidget {
  final AccountModel account;
  const _JtPasswordDialog({required this.account});

  @override
  ConsumerState<_JtPasswordDialog> createState() => _JtPasswordDialogState();
}

class _JtPasswordDialogState extends ConsumerState<_JtPasswordDialog> {
  final controller = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final updated = await ref.read(jtProfilePinStoreProvider).reauthenticate(widget.account, controller.text);
    if (!mounted) return;
    if (updated != null) {
      Navigator.of(context).pop(updated);
      return;
    }
    setState(() {
      busy = false;
      error = context.localized.somethingWentWrongPasswordCheck;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: jtProfileArrowShortcuts,
      child: AlertDialog(
        title: Text(context.localized.jtPasswordTitle(widget.account.name)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 12,
                children: [
                  JtProfileAvatar(account: widget.account, size: 48),
                  Expanded(child: Text(context.localized.jtPasswordDesc)),
                ],
              ),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: context.localized.password,
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          JtFocusRing(
            child: TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: Text(context.localized.cancel),
            ),
          ),
          JtFocusRing(
            child: FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.localized.login),
            ),
          ),
        ],
      ),
    );
  }
}
