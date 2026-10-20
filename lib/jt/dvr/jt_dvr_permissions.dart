import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/user_provider.dart';

/// JT-Streaming: recording (DVR) controls are only shown to users with the
/// Jellyfin right "Allow Live TV recording management". The server enforces
/// the same right (403), so this check is convenience, not security.
bool jtCanManageRecordings(AccountModel? account) => account?.policy?.enableLiveTvManagement ?? false;

/// Only notifies dependants when the boolean actually changes.
final jtCanManageRecordingsProvider = Provider<bool>((ref) => jtCanManageRecordings(ref.watch(userProvider)));
