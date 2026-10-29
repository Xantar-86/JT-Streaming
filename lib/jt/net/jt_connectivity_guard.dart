// JT-HOOK: connectivity-guard (WP2.12, THEAAA-182)
//
// Upstream ConnectivityStatus sprong bij een enkele trage /System/Info/Public
// (2 s timeout) of bij een netwerktype dat het niet kende (`other`, kort `none`)
// meteen naar `offline`. Op een Mi Box S met USB-ethernet (Realtek) gaf dat
// af en toe een valse "Offline"-melding.
//
// Deze poort beslist wanneer de app echt offline is:
// - `other` (USB-ethernet, onbekende adapter) telt als online: server proben.
// - `none` wordt eerst [JtConnectivityConfig.noneDebounce] uitgesteld, daarna
//   opnieuw gelezen en geprobed; pas als de hardware nog steeds `none` meldt en
//   de server onbereikbaar is, toont de app offline.
// - Een mislukte probe telt; pas na [JtConnectivityConfig.failuresBeforeOffline]
//   mislukkingen na elkaar wordt de status offline. Tussendoor blijft de vorige
//   status staan en wordt na [JtConnectivityConfig.retryDelay] opnieuw geprobed.
// - Eenmaal offline wordt de server elke [JtConnectivityConfig.offlineReprobe]
//   op de achtergrond opnieuw geprobed, zodat de app zelf weer online komt.
//
// De klasse is puur Dart (geen platformkanaal), zodat ze met fake_async getest
// kan worden: test/jt/jt_connectivity_guard_test.dart.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:fladder/providers/connectivity_provider.dart';

/// Uitkomst van een serverprobe.
enum JtProbeResult {
  /// Server bereikt via de lokale URL.
  local,

  /// Server bereikt via de gewone URL.
  remote,

  /// Server niet bereikt (timeout, fout, verkeerde server).
  unreachable,

  /// Niet geprobed (geen gebruiker ingelogd); status blijft ongewijzigd.
  skipped;

  bool get reached => this == local || this == remote;
}

class JtConnectivityConfig {
  const JtConnectivityConfig({
    this.probeTimeout = const Duration(seconds: 8),
    this.hardwareDebounce = const Duration(milliseconds: 500),
    this.noneDebounce = const Duration(seconds: 3),
    this.failuresBeforeOffline = 3,
    this.retryDelay = const Duration(seconds: 5),
    this.offlineReprobe = const Duration(seconds: 30),
  });

  /// Timeout per aanvraag op /System/Info/Public (upstream: 2 s).
  final Duration probeTimeout;

  /// Uitstel na een netwerkwissel naar een online type (upstream: 500 ms).
  final Duration hardwareDebounce;

  /// Uitstel na `none` voor de hardware opnieuw gelezen wordt.
  final Duration noneDebounce;

  /// Aantal mislukte probes na elkaar voor de status offline wordt.
  final int failuresBeforeOffline;

  /// Wachttijd tussen twee probes zolang de drempel niet bereikt is.
  final Duration retryDelay;

  /// Interval van de achtergrondprobe zolang de status offline is.
  final Duration offlineReprobe;
}

const jtConnectivityConfig = JtConnectivityConfig();

/// Vertaalt connectivity_plus-resultaten naar een online type, of `null`
/// als er geen netwerk gemeld wordt (`none` of lege lijst).
ConnectionState? jtParseHardwareState(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.vpn)) return ConnectionState.vpn;
  if (results.contains(ConnectivityResult.ethernet)) return ConnectionState.ethernet;
  if (results.contains(ConnectivityResult.wifi)) return ConnectionState.wifi;
  if (results.contains(ConnectivityResult.mobile)) return ConnectionState.mobile;
  // USB-ethernetadapters (bv. Realtek op de Mi Box S) en onbekende types komen
  // als `other` binnen: behandelen als vaste verbinding en de server laten proben.
  if (results.contains(ConnectivityResult.other)) return ConnectionState.ethernet;
  return null;
}

class JtConnectivityGuard {
  JtConnectivityGuard({
    required this.probe,
    required this.readHardware,
    required this.onState,
    this.config = jtConnectivityConfig,
    ConnectionState initialState = ConnectionState.mobile,
  }) : _current = initialState;

  final Future<JtProbeResult> Function() probe;
  final Future<List<ConnectivityResult>> Function() readHardware;
  final void Function(ConnectionState state, {required bool isLocal}) onState;
  final JtConnectivityConfig config;

  ConnectionState _current;
  ConnectionState? _candidate;
  int _failures = 0;
  int _generation = 0;
  Timer? _timer;
  Completer<void>? _probeCompleter;
  bool _disposed = false;

  ConnectionState get current => _current;
  int get consecutiveFailures => _failures;

  /// Wacht tot de lopende probe (indien die er is) klaar is.
  Future<void> waitForProbe() async => _probeCompleter?.future;

  /// Nieuwe hardwarestatus van connectivity_plus.
  void onHardware(List<ConnectivityResult> results, {bool immediate = false}) {
    if (_disposed) return;
    _timer?.cancel();
    final gen = ++_generation;
    _probeCompleter ??= Completer<void>();

    final parsed = jtParseHardwareState(results);
    if (parsed == null) {
      _timer = Timer(config.noneDebounce, () => unawaited(_confirmNone(gen)));
      return;
    }

    _candidate = parsed;
    if (immediate) {
      unawaited(_probe(gen));
    } else {
      _timer = Timer(config.hardwareDebounce, () => unawaited(_probe(gen)));
    }
  }

  /// Vraagt een nieuwe probe aan zonder netwerkwissel (bv. gewijzigde lokale URL).
  void reprobe() {
    if (_disposed) return;
    _timer?.cancel();
    final gen = ++_generation;
    _probeCompleter ??= Completer<void>();
    unawaited(_probe(gen));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _generation++;
    _resolveProbe();
  }

  Future<void> _confirmNone(int gen) async {
    final List<ConnectivityResult> results;
    try {
      results = await readHardware();
    } catch (_) {
      if (gen == _generation) _goOffline(gen);
      return;
    }
    if (gen != _generation || _disposed) return;

    final parsed = jtParseHardwareState(results);
    if (parsed != null) {
      // Korte `none` tijdens een netwerkwissel: gewoon verder als online type.
      _candidate = parsed;
      await _probe(gen);
      return;
    }

    // Hardware meldt nog steeds geen netwerk: één probe, daarna offline.
    final result = await _safeProbe();
    if (gen != _generation || _disposed) return;
    if (result.reached) {
      _failures = 0;
      _emit(_onlineState, isLocal: result == JtProbeResult.local);
      _resolveProbe();
    } else if (result == JtProbeResult.skipped) {
      _resolveProbe();
    } else {
      _goOffline(gen);
    }
  }

  Future<void> _probe(int gen) async {
    final result = await _safeProbe();
    if (gen != _generation || _disposed) return;

    switch (result) {
      case JtProbeResult.local:
      case JtProbeResult.remote:
        _failures = 0;
        _emit(_onlineState, isLocal: result == JtProbeResult.local);
        _resolveProbe();
      case JtProbeResult.skipped:
        _resolveProbe();
      case JtProbeResult.unreachable:
        _failures++;
        if (_failures >= config.failuresBeforeOffline) {
          _goOffline(gen);
        } else {
          // Status blijft staan; straks opnieuw proberen.
          _timer = Timer(config.retryDelay, () => unawaited(_probe(gen)));
        }
    }
  }

  void _goOffline(int gen) {
    _emit(ConnectionState.offline, isLocal: false);
    _resolveProbe();
    _timer?.cancel();
    _timer = Timer(config.offlineReprobe, () => unawaited(_probe(gen)));
  }

  Future<JtProbeResult> _safeProbe() async {
    try {
      return await probe();
    } catch (_) {
      return JtProbeResult.unreachable;
    }
  }

  ConnectionState get _onlineState =>
      _candidate ?? (_current != ConnectionState.offline ? _current : ConnectionState.ethernet);

  void _emit(ConnectionState state, {required bool isLocal}) {
    _current = state;
    onState(state, isLocal: isLocal);
  }

  void _resolveProbe() {
    if (!(_probeCompleter?.isCompleted ?? true)) {
      _probeCompleter?.complete();
    }
    _probeCompleter = null;
  }
}
