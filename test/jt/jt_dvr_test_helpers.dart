import 'package:fladder/models/items/channel_program.dart';

ChannelProgram jtTestProgram({
  String id = 'p1',
  required DateTime start,
  required DateTime end,
  bool isSeries = false,
}) =>
    ChannelProgram(
      id: id,
      channelId: 'c1',
      name: 'Journaal',
      officialRating: '',
      productionYear: 0,
      indexNumber: 0,
      parentIndexNumber: 0,
      startDate: start,
      endDate: end,
      isSeries: isSeries,
    );
