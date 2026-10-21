import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/models/items/channel_program.dart';

ChannelProgram guideProgram(String id, String channelId, DateTime start, DateTime end) => ChannelProgram(
      id: id,
      channelId: channelId,
      name: id,
      officialRating: '',
      productionYear: 0,
      indexNumber: 0,
      parentIndexNumber: 0,
      startDate: start,
      endDate: end,
      isSeries: false,
    );

class GuideRequest {
  final List<String> channelIds;
  final DateTime start;
  final DateTime end;
  GuideRequest(this.channelIds, this.start, this.end);
}

/// Fake Jellyfin: per channel one program that ends exactly at the window
/// start ("before", must be filtered), hourly programs, and as last program
/// either one ending exactly at the window end (channel c2) or one running
/// 30 min past it (all other channels). Like Jellyfin, the server bounds are
/// inclusive, so the client has to filter.
class FakeGuideApi implements JtGuideApi {
  final List<GuideRequest> requests = [];
  final Set<String> emptyChannels = {};
  Duration delay = Duration.zero;
  bool fail = false;
  (DateTime?, DateTime?)? coverageResult;
  (DateTime?, DateTime?)? guideInfoResult;

  @override
  Future<List<ChannelProgram>> programs(List<String> channelIds, DateTime start, DateTime end) async {
    requests.add(GuideRequest(List.of(channelIds), start, end));
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw Exception('fake failure');
    final result = <ChannelProgram>[];
    for (final c in channelIds) {
      if (emptyChannels.contains(c)) continue;
      result.add(guideProgram('$c-before', c, start.subtract(const Duration(hours: 1)), start));
      var t = start;
      var i = 0;
      while (t.add(const Duration(hours: 1)).isBefore(end)) {
        final next = t.add(const Duration(hours: 1));
        result.add(guideProgram('$c-h$i', c, t, next));
        t = next;
        i++;
      }
      if (c == 'c2') {
        result.add(guideProgram('$c-ends-at-midnight', c, t, end));
      } else {
        result.add(guideProgram('$c-over-midnight', c, t, end.add(const Duration(minutes: 30))));
      }
    }
    return result;
  }

  @override
  Future<(DateTime?, DateTime?)> coverage() async {
    final r = coverageResult;
    if (r == null) throw Exception('no coverage');
    return r;
  }

  @override
  Future<(DateTime?, DateTime?)> guideInfo() async {
    final r = guideInfoResult;
    if (r == null) throw Exception('no guide info');
    return r;
  }
}
