import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/net/jt_connectivity_guard.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/services/local_network_permission.dart';

part 'connectivity_provider.g.dart';

enum ConnectionState {
  offline,
  mobile,
  wifi,
  ethernet,
  vpn;

  bool get homeInternet => switch (this) {
        ConnectionState.offline => false,
        ConnectionState.mobile => false,
        ConnectionState.wifi => true,
        ConnectionState.ethernet => true,
        ConnectionState.vpn => true,
      };
}

final offlineStateProvider = Provider<bool>((ref) {
  final isLoggedIn = ref.watch(userProvider.select((value) => value != null));
  return ref.watch(connectivityStatusProvider.select((value) => value == ConnectionState.offline)) && isLoggedIn;
});

final localConnectionAvailableProvider = StateProvider<bool>((ref) => false);

@Riverpod(keepAlive: true)
class ConnectivityStatus extends _$ConnectivityStatus {
  // JT-HOOK: connectivity-guard. Wanneer de app offline is, beslist
  // JtConnectivityGuard (lib/jt/net/): `other` = online, `none` met debounce,
  // offline pas na meerdere mislukte probes, achtergrondprobe terwijl offline.
  late JtConnectivityGuard _guard;

  @override
  ConnectionState build() {
    _guard = JtConnectivityGuard(
      probe: _probeReachability,
      readHardware: () => Connectivity().checkConnectivity(),
      onState: _updateState,
    );

    ref.listen(
      userProvider.select((value) => value?.credentials.localUrl),
      (previous, next) {
        if (previous != next) {
          _guard.reprobe();
        }
      },
    );

    final subscription = Connectivity().onConnectivityChanged.listen((results) {
      _guard.onHardware(results);
    });

    ref.onDispose(() {
      subscription.cancel();
      _guard.dispose();
    });

    checkConnectivity(immediate: true);

    return ConnectionState.mobile;
  }

  Future<void> checkConnectivity({bool immediate = false}) async {
    final results = await Connectivity().checkConnectivity();
    _guard.onHardware(results, immediate: immediate);
  }

  Future<void> waitForProbe() => _guard.waitForProbe();

  Future<JtProbeResult> _probeReachability() async {
    final user = ref.read(userProvider);
    if (user == null) return JtProbeResult.skipped;

    final localUrl = user.credentials.localUrl;
    if (localUrl != null && localUrl.isNotEmpty) {
      final permission = await checkLocalNetworkPermission();
      if (permission == LocalNetworkPermissionStatus.granted) {
        final localConnection = await fetchSystemInfoDynamic(normalizeUrl(localUrl));
        if (localConnection?.id == user.credentials.serverId) {
          return JtProbeResult.local;
        }
      }
    }

    final remoteUrl = user.credentials.url;
    if (remoteUrl.isNotEmpty) {
      final checkServer = await fetchSystemInfoDynamic(normalizeUrl(remoteUrl));
      if (checkServer != null) {
        return JtProbeResult.remote;
      }
    }

    return JtProbeResult.unreachable;
  }

  void _updateState(ConnectionState newState, {required bool isLocal}) {
    ref.read(localConnectionAvailableProvider.notifier).state = isLocal;
    state = newState;
  }
}

Future<PublicSystemInfo?> fetchSystemInfoDynamic(String baseUrl, {http.Client? client}) async {
  if (baseUrl.isEmpty) return null;
  try {
    final uri = buildServerUriFromBase(baseUrl, pathSegments: const ['System', 'Info', 'Public']);
    if (uri == null) return null;

    // JT-HOOK: connectivity-guard. 8 s i.p.v. 2 s: een trage TLS-handshake op
    // de Mi Box S (tijdens afspelen, na stand-by) is geen offline server.
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(jtConnectivityConfig.probeTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return PublicSystemInfo.fromJson(jsonDecode(response.body));
    }
    return null;
  } catch (e) {
    log(e.toString());
    return null;
  }
}
