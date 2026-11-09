import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/api/api_client.dart';
import 'package:musicplayer/models/models.dart';
import 'package:musicplayer/player/player_service.dart';
import 'package:musicplayer/remote/remote_service.dart';
import 'package:musicplayer/screens/stats_screen.dart';
import 'package:musicplayer/stats/listen_tracker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi extends ApiClient {
  final sent = <List<Map<String, dynamic>>>[];
  bool fail = false;
  @override
  bool get isLoggedIn => true;
  @override
  Future<void> postListens(List<Map<String, dynamic>> events) async {
    if (fail) throw Exception('offline');
    sent.add(events.map((e) => Map.of(e)).toList());
  }

  @override
  String coverUrl(int? coverArtId, {int? size}) => '';

  @override
  Future<List<ListenDay>> listenCalendar(DateTime from, DateTime to) async {
    final today = DateTime.now();
    return [
      for (var i = 0; i < 200; i += 3)
        ListenDay(DateTime(today.year, today.month, today.day - i),
            (i * 97 % 7200).toDouble(), i % 9),
    ];
  }

  Track _t(int i) => Track(
      id: i,
      title: 'A fairly long track title number $i that should ellipsize',
      artist: 'Artist with a long name $i',
      format: 'mp3');

  @override
  Future<DayListenDetail> listenDay(DateTime day) async =>
      DayListenDetail(day, 5400, 14, [
        for (var i = 0; i < 5; i++)
          TrackListenStat(i == 4 ? null : _t(i), 'Song $i', 'Artist', 'Album',
              1000.0 + i, 3 + i),
      ]);

  @override
  Future<TopListens> topListens(
          {DateTime? from, DateTime? to, int limit = 10}) async =>
      TopListens(
        123456,
        321,
        28,
        [
          for (var i = 0; i < 10; i++)
            TrackListenStat(_t(i), 'Song $i', 'Artist', 'Album', 3000, 20 - i)
        ],
        [
          for (var i = 0; i < 6; i++)
            AlbumListenStat(null, 'A very long album name $i', 9000, 50 - i)
        ],
        [
          for (var i = 0; i < 6; i++)
            ArtistListenStat(
                'Artist name that is quite long $i', 99999, 1234 - i * 100)
        ],
      );
}

class FakePlayer extends ChangeNotifier implements PlayerService {
  @override
  Future<void> flushListens() async {}
  @override
  Track? get currentTrack => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeRemote extends ChangeNotifier implements RemoteService {
  @override
  bool get isRemote => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ListenTracker', () {
    test('counts only small forward steps while playing', () async {
      final api = FakeApi();
      final t = ListenTracker(api, deviceName: () => 'test');
      t.onTrack(1);
      var pos = Duration.zero;
      t.onPosition(pos, playing: true);
      for (var i = 0; i < 100; i++) {
        pos += const Duration(milliseconds: 200);
        t.onPosition(pos, playing: true); // 20s of play
      }
      t.onPosition(pos + const Duration(seconds: 60), playing: true); // seek
      pos += const Duration(seconds: 60);
      for (var i = 0; i < 10; i++) {
        pos += const Duration(milliseconds: 200);
        t.onPosition(pos, playing: false); // paused: ignored
      }
      t.onTrack(2); // closes listen of track 1
      await t.flush();
      final all = api.sent.expand((b) => b).toList();
      final e = all.lastWhere((e) => e['trackId'] == 1);
      expect(e['seconds'], closeTo(20, 0.01));
      expect(e['day'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      t.dispose();
    });

    test('restart from the top starts a new listen', () async {
      final api = FakeApi();
      final t = ListenTracker(api, deviceName: () => 'test');
      t.onTrack(5);
      var pos = Duration.zero;
      t.onPosition(pos, playing: true);
      for (var i = 0; i < 75; i++) {
        pos += const Duration(milliseconds: 200);
        t.onPosition(pos, playing: true); // 15s
      }
      t.onPosition(const Duration(milliseconds: 100), playing: true); // repeat
      pos = const Duration(milliseconds: 100);
      for (var i = 0; i < 25; i++) {
        pos += const Duration(milliseconds: 200);
        t.onPosition(pos, playing: true); // 5s
      }
      t.endCurrent();
      await t.flush();
      final ids = api.sent.expand((b) => b).map((e) => e['clientId']).toSet();
      expect(ids.length, 2);
      t.dispose();
    });

    test('keeps events while offline and uploads them later', () async {
      final api = FakeApi()..fail = true;
      final t = ListenTracker(api, deviceName: () => 'test');
      t.onTrack(7);
      var pos = Duration.zero;
      t.onPosition(pos, playing: true);
      for (var i = 0; i < 50; i++) {
        pos += const Duration(milliseconds: 200);
        t.onPosition(pos, playing: true);
      }
      t.endCurrent();
      await t.flush();
      expect(api.sent, isEmpty);
      api.fail = false;
      await t.flush();
      expect(api.sent.last.single['seconds'], closeTo(10, 0.01));
      await t.flush(); // outbox emptied: nothing re-sent
      expect(api.sent.length, 1);
      t.dispose();
    });
  });

  for (final size in [const Size(360, 780), const Size(1200, 800)]) {
    testWidgets('StatsScreen lays out at ${size.width}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ApiClient>(create: (_) => FakeApi()),
          ChangeNotifierProvider<PlayerService>(create: (_) => FakePlayer()),
          ChangeNotifierProvider<RemoteService>(create: (_) => FakeRemote()),
        ],
        child: MaterialApp(
          theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF4F7CFF),
                  brightness: Brightness.dark)),
          home: const StatsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Listening stats'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Artists'), findsOneWidget);
      // Tap 30 days -> Year
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
    });
  }
}
