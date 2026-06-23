import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/game_session.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/games/gostop/gostop_view.dart';

/// 테스트용 결정적 진행 상태(랜덤 딜 대신 작은 손패/바닥으로).
Map<String, dynamic> _testState() => <String, dynamic>{
  'phase': 'playing',
  // 바닥에 1월 띠(1) 1장 → 손패 1월 피(2)를 내면 쌍 먹기.
  'floor': <int>[1, 20],
  'stock': <int>[34, 35, 36], // 더미(매칭 안 되는 카드들).
  'hands': <String, List<int>>{
    'host': <int>[2, 16, 24], // 1월 피, 5월 열끗, 7월 열끗.
    'guest': <int>[6, 18, 26],
  },
  'captured': <String, List<int>>{'host': <int>[], 'guest': <int>[]},
  'scores': <String, int>{'host': 0, 'guest': 0},
  'go': <String, int>{'host': 0, 'guest': 0},
  'shaken': <String, int>{'host': 0, 'guest': 0},
  'bomb': <String, int>{'host': 0, 'guest': 0},
  'ppeokCount': <String, int>{'host': 0, 'guest': 0},
  'nagariMult': 1,
  'firstTurn': false,
  'awaitingGoStop': '',
  'lastEvent': 'none',
};

Future<GameSession> _setupSession(LocalRoomService svc) async {
  final room = await svc.createRoom(
    gameId: 'gostop',
    host: const RoomPlayer(id: 'host', name: '호스트'),
  );
  await svc.joinRoom(
    code: room.code,
    player: const RoomPlayer(id: 'guest', name: '게스트'),
  );
  await svc.startGame(room.code, initialState: _testState(), firstTurn: 'host');
  return GameSession(
    myPlayerId: 'host',
    roomCode: room.code,
    service: svc,
    hotseat: true,
  );
}

Widget _wrap(GameSession session, Room room, IdentityService identity) {
  return AppServices(
    identity: identity,
    roomService: session.service,
    scoreStore: LocalScoreStore(),
    firebaseReady: false,
    child: MaterialApp(
      home: Scaffold(
        body: GoStopView(
          session: session,
          room: room,
          createInitialState: (ids) => _testState(),
          firstTurn: (ids) => ids.first,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('고스톱 인게임이 손패/바닥/점수와 함께 빌드된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    final svc = LocalRoomService();
    final session = await _setupSession(svc);

    final room = await session.watch().first;
    await tester.pumpWidget(_wrap(session, room, identity));
    await tester.pump();

    // 핵심 영역 라벨이 표시된다.
    expect(find.textContaining('손패'), findsWidgets);
    expect(find.textContaining('바닥'), findsWidgets);
    expect(find.textContaining('먹은 패'), findsWidgets);
  });

  testWidgets('손패 카드를 탭하면 턴이 처리되어 상태가 갱신된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    final svc = LocalRoomService();
    final session = await _setupSession(svc);

    var room = await session.watch().first;
    await tester.pumpWidget(_wrap(session, room, identity));
    await tester.pumpAndSettle();

    // 탭 가능한(onTap 있는) 손패 카드는 GestureDetector로 감싸진다.
    final cards = find.byType(GestureDetector);
    expect(cards, findsWidgets);
    final card = cards.first;
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card, warnIfMissed: false);
    await tester.pumpAndSettle();

    // submit이 반영되어 호스트 손패가 줄었는지 확인.
    room = await session.watch().first;
    final hostHand = ((room.state['hands'] as Map)['host'] as List).cast<int>();
    expect(hostHand.length, lessThan(3));
  });
}
