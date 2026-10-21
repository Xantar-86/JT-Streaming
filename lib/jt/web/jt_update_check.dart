import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fladder/jt/web/jt_update_stub.dart' if (dart.library.js_interop) 'package:fladder/jt/web/jt_update_web.dart';
import 'package:fladder/util/localization_helper.dart';

/// Build id baked in by tool/jt/build-web.ps1 (`--dart-define=JT_BUILD_ID`),
/// the same value as `buildId` in jt-buildinfo.json. Empty in dev builds.
const jtBuildId = String.fromEnvironment('JT_BUILD_ID');

/// True when the server's jt-buildinfo.json names another build than the
/// one running.
bool jtIsNewerBuild(String? buildInfoJson, String runningBuildId) {
  if (buildInfoJson == null || runningBuildId.isEmpty) return false;
  try {
    final remote = (jsonDecode(buildInfoJson) as Map<String, dynamic>)['buildId'];
    return remote is String && remote.isNotEmpty && remote != runningBuildId;
  } catch (_) {
    return false;
  }
}

/// Web only: at start and every 30 min fetch jt-buildinfo.json with
/// `cache: no-store`; another build id shows "New version available ·
/// Reload". Reload = service worker update (or unregister + clear caches)
/// and location.reload(). Does nothing on Windows/Android.
class JtUpdateCheck extends StatefulWidget {
  final Widget child;
  final String runningBuildId;

  const JtUpdateCheck({required this.child, this.runningBuildId = jtBuildId, super.key});

  @override
  State<JtUpdateCheck> createState() => _JtUpdateCheckState();
}

class _JtUpdateCheckState extends State<JtUpdateCheck> {
  static const interval = Duration(minutes: 30);
  Timer? _first;
  Timer? _timer;
  bool _available = false;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb || widget.runningBuildId.isEmpty) return;
    final override = jtUpdateIntervalOverride();
    final every = override != null && override >= 5 ? Duration(seconds: override) : interval;
    _first = Timer(const Duration(seconds: 3), _check);
    _timer = Timer.periodic(every, (_) => _check());
  }

  Future<void> _check() async {
    if (_available) return;
    try {
      final json = await jtFetchNoStore('jt-buildinfo.json?t=${DateTime.now().millisecondsSinceEpoch}');
      if (jtIsNewerBuild(json, widget.runningBuildId)) {
        jtUpdateLog('[jt-update] new version on the server (running ${widget.runningBuildId})');
        if (mounted) setState(() => _available = true);
      }
    } catch (e) {
      jtUpdateLog('[jt-update] check failed: $e');
    }
  }

  @override
  void dispose() {
    _first?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return widget.child;
    final theme = Theme.of(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Center(
            child: Material(
              elevation: 6,
              color: theme.colorScheme.inverseSurface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Text(
                      context.localized.jtUpdateAvailable,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onInverseSurface),
                    ),
                    FilledButton(
                      onPressed: _reloading
                          ? null
                          : () {
                              setState(() => _reloading = true);
                              jtHardReload();
                            },
                      child: Text(context.localized.jtUpdateReload),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
