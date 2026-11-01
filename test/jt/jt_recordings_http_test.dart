import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/jt/dvr/jt_recordings_provider.dart';
import 'package:fladder/providers/service_provider.dart';

/// The real generated client over real HTTP, no testWidgets: that replaces
/// HttpClient. JSON keys and status codes as in Jellyfin 10.11.
class _Service extends Fake implements JellyService {
  _Service(this.api);

  @override
  final JellyfinOpenApi api;

  @override
  Future<chopper.Response<dynamic>> deleteItem(String itemId) => api.itemsItemIdDelete(itemId: itemId);
}

void main() {
  late HttpServer server;
  late _Service service;
  final requests = <String>[];

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    service = _Service(JellyfinOpenApi.create(baseUrl: Uri.parse('http://127.0.0.1:${server.port}')));
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      final response = request.response;
      if (request.method == 'GET' && request.uri.path == '/LiveTv/Recordings') {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({
          'Items': [
            {
              'Id': 'a1',
              'Name': 'VTM Nieuws',
              'Type': 'Episode',
              'CanDelete': true,
              'StartDate': '2026-10-28T18:00:00.0000000Z',
            },
            {'Id': 'a2', 'Name': 'VTM Nieuws', 'Type': 'Recording', 'CanDelete': true, 'Status': 'InProgress'},
            {'Id': 'a3', 'Name': 'Thuis', 'Type': 'Video'},
          ],
          'TotalRecordCount': 3,
        }));
      } else if (request.method == 'DELETE') {
        response.statusCode = request.uri.path == '/Items/a1' ? 204 : 401;
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
  });

  test('the list asks CanDelete and parses it per recording', () async {
    final recordings = await service.jtRecordings();

    expect(requests.single, startsWith('GET /LiveTv/Recordings'));
    expect(Uri.parse(requests.single.split(' ').last).queryParametersAll['fields'], contains('CanDelete'));
    expect(recordings.map(jtCanDeleteRecording), [true, false, false]);
  });

  test('delete goes to /Items, 204 is success and 401 is not', () async {
    expect(await service.jtDeleteRecording('a1'), isTrue);
    expect(await service.jtDeleteRecording('a3'), isFalse);
    expect(requests, ['DELETE /Items/a1', 'DELETE /Items/a3']);
  });
}
