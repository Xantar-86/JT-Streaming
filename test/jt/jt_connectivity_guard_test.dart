// WP2.12 (THEAAA-182): valse "Offline" op de Mi Box S (USB-ethernet).
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fladder/jt/net/jt_connectivity_guard.dart';
import 'package:fladder/providers/connectivity_provider.dart';

class _Harness {
  _Harness({List<JtProbeResult> probes = const [], List<ConnectivityResult> hardware = const []})
      : _probes = List.of(probes),
        hardware = List.of(hardware) {
    guard = JtConnectivityGuard(
      probe: () async {
        probeCalls++;
        return _probes.isEmpty ? JtProbeResult.remote : _probes.removeAt(0);
      },
      readHardware: () async => hardware,
      onState: (state, {required isLocal}) => states.add(state),
    );
  }

  final List<JtProbeResult> _probes;
  List<ConnectivityResult> hardware;
  late final JtConnectivityGuard guard;
  final states = <ConnectionState>[];
  int probeCalls = 0;
}

void main() {
  group('jtParseHardwareState', () {
    test('other (USB-ethernet) telt als vaste verbinding', () {
      expect(jtParseHardwareState([ConnectivityResult.other]), ConnectionState.ethernet);
    });
    test('none en lege lijst geven geen online type', () {
      expect(jtParseHardwareState([ConnectivityResult.none]), isNull);
      expect(jtParseHardwareState(const []), isNull);
    });
    test('bekende types blijven zoals upstream', () {
      expect(jtParseHardwareState([ConnectivityResult.wifi]), ConnectionState.wifi);
      expect(jtParseHardwareState([ConnectivityResult.ethernet, ConnectivityResult.vpn]), ConnectionState.vpn);
      expect(jtParseHardwareState([ConnectivityResult.mobile]), ConnectionState.mobile);
    });
  });

  group('trage server', () {
    test('twee mislukte probes na elkaar geven geen offline', () {
      fakeAsync((async) {
        final h = _Harness(probes: [JtProbeResult.unreachable, JtProbeResult.unreachable, JtProbeResult.remote]);
        h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);
        async.elapse(const Duration(seconds: 30));

        expect(h.probeCalls, 3);
        expect(h.states, isNot(contains(ConnectionState.offline)));
        expect(h.states.last, ConnectionState.ethernet);
        expect(h.guard.consecutiveFailures, 0);
      });
    });

    test('pas na drie mislukte probes offline, daarna herstelt de achtergrondprobe', () {
      fakeAsync((async) {
        final h = _Harness(probes: List.filled(3, JtProbeResult.unreachable));
        h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);

        async.elapse(const Duration(seconds: 9)); // probes 1 en 2
        expect(h.states, isEmpty);
        async.elapse(const Duration(seconds: 2)); // probe 3 op t=10 s
        expect(h.states, [ConnectionState.offline]);

        async.elapse(jtConnectivityConfig.offlineReprobe);
        expect(h.states, [ConnectionState.offline, ConnectionState.ethernet]);
      });
    });

    test('8 s timeout: antwoord na 3 s is online (upstream 2 s gaf offline)', () {
      fakeAsync((async) {
        final client = MockClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 3));
          return http.Response(jsonEncode({'Id': 'srv'}), 200);
        });
        Object? info = 'pending';
        fetchSystemInfoDynamic('https://tv.example', client: client).then((v) => info = v);
        async.elapse(const Duration(seconds: 4));
        expect(info, isNotNull);
        expect(info, isNot('pending'));
      });
    });

    test('8 s timeout: antwoord na 9 s telt als mislukt', () {
      fakeAsync((async) {
        final client = MockClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 9));
          return http.Response(jsonEncode({'Id': 'srv'}), 200);
        });
        Object? info = 'pending';
        fetchSystemInfoDynamic('https://tv.example', client: client).then((v) => info = v);
        async.elapse(const Duration(seconds: 10));
        expect(info, isNull);
      });
    });
  });

  group('other', () {
    test('USB-ethernet als other wordt online na een geslaagde probe', () {
      fakeAsync((async) {
        final h = _Harness();
        h.guard.onHardware([ConnectivityResult.other]);
        async.elapse(const Duration(seconds: 1));

        expect(h.probeCalls, 1);
        expect(h.states, [ConnectionState.ethernet]);
      });
    });
  });

  group('kort none', () {
    test('none die binnen de debounce terug online is, geeft geen offline', () {
      fakeAsync((async) {
        final h = _Harness(hardware: [ConnectivityResult.ethernet]);
        h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);
        async.flushMicrotasks();
        expect(h.states, [ConnectionState.ethernet]);

        h.guard.onHardware([ConnectivityResult.none]);
        async.elapse(const Duration(seconds: 1));
        h.guard.onHardware([ConnectivityResult.other]);
        async.elapse(const Duration(seconds: 10));

        expect(h.states, isNot(contains(ConnectionState.offline)));
      });
    });

    test('none zonder nieuw event, maar hardware is na de debounce terug: geen offline', () {
      fakeAsync((async) {
        final h = _Harness(hardware: [ConnectivityResult.other]);
        h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);
        async.flushMicrotasks();

        h.guard.onHardware([ConnectivityResult.none]);
        async.elapse(const Duration(seconds: 10));

        expect(h.states, isNot(contains(ConnectionState.offline)));
        expect(h.probeCalls, 2);
      });
    });

    test('none die blijft en server onbereikbaar: offline pas na de debounce', () {
      fakeAsync((async) {
        final h = _Harness(probes: [JtProbeResult.remote, JtProbeResult.unreachable], hardware: [ConnectivityResult.none]);
        h.guard.onHardware([ConnectivityResult.wifi], immediate: true);
        async.flushMicrotasks();

        h.guard.onHardware([ConnectivityResult.none]);
        async.elapse(jtConnectivityConfig.noneDebounce - const Duration(milliseconds: 1));
        expect(h.states, [ConnectionState.wifi]);

        async.elapse(const Duration(milliseconds: 2));
        expect(h.states, [ConnectionState.wifi, ConnectionState.offline]);
      });
    });

    test('none die blijft maar server wel bereikbaar: online', () {
      fakeAsync((async) {
        final h = _Harness(hardware: [ConnectivityResult.none]);
        h.guard.onHardware([ConnectivityResult.wifi], immediate: true);
        async.flushMicrotasks();

        h.guard.onHardware([ConnectivityResult.none]);
        async.elapse(const Duration(seconds: 5));

        expect(h.states, [ConnectionState.wifi, ConnectionState.wifi]);
      });
    });
  });

  test('geen gebruiker ingelogd: status blijft ongewijzigd', () {
    fakeAsync((async) {
      final h = _Harness(probes: [JtProbeResult.skipped]);
      h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);
      async.elapse(const Duration(minutes: 1));
      expect(h.states, isEmpty);
      expect(h.probeCalls, 1);
    });
  });

  test('dispose stopt de achtergrondprobe', () {
    fakeAsync((async) {
      final h = _Harness(probes: List.filled(10, JtProbeResult.unreachable));
      h.guard.onHardware([ConnectivityResult.ethernet], immediate: true);
      async.elapse(const Duration(seconds: 11));
      expect(h.states, [ConnectionState.offline]);
      final calls = h.probeCalls;

      h.guard.dispose();
      async.elapse(const Duration(minutes: 5));
      expect(h.probeCalls, calls);
    });
  });
}
