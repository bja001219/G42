import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/game_session.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/games/gostop/gostop_card_widget.dart';
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
  'moveSeq': 0,
};

Future<GameSession> _setupSession(
  LocalRoomService svc, {
  bool hotseat = true,
}) async {
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
    hotseat: hotseat,
  );
}

/// 실제 프로덕션 경로(StreamBuilder 가 session.watch() 갱신을 받아 GoStopView 를
/// 새 room 으로 리빌드 → didUpdateWidget → 안무 트리거)를 재현하는 래퍼.
Widget _wrapLive(GameSession session, IdentityService identity) {
  return AppServices(
    identity: identity,
    roomService: session.service,
    scoreStore: LocalScoreStore(),
    firebaseReady: false,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: StreamBuilder<Room>(
            stream: session.watch(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return GoStopView(
                session: session,
                room: snap.data!,
                createInitialState: (ids) => _testState(),
                firstTurn: (ids) => ids.first,
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('고스톱 인게임이 테이블/카드/점수와 함께 빌드된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    final svc = LocalRoomService();
    final session = await _setupSession(svc);

    await tester.pumpWidget(_wrapLive(session, identity));
    await tester.pumpAndSettle();

    // 테이블에 카드 위젯(손패/바닥/더미)이 그려진다.
    expect(find.byType(GoStopCardWidget), findsWidgets);
    // 점수 표시(영역별 점수 칩)가 존재한다.
    expect(find.textContaining('점'), findsWidgets);
  });

  testWidgets('손패 카드를 탭하면 그 패가 손에서 빠진다(즉시 커밋)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    final svc = LocalRoomService();
    // 온라인 세션(hotseat=false): 수를 둔 뒤 차례가 넘어가도 핫시트 가림막이
    // 뜨지 않아 내 손패가 계속 보인다(낸 카드가 빠졌는지 위젯으로 확인 가능).
    final session = await _setupSession(svc, hotseat: false);

    await tester.pumpWidget(_wrapLive(session, identity));
    await tester.pumpAndSettle();

    // 손패 부채는 오른쪽 카드가 가장 위에 그려져 중앙이 완전히 노출된다.
    // (가장 왼쪽 카드는 다른 카드에 덮여 '중앙' 탭이 빗나갈 수 있어 회피 —
    //  실제 앱에선 노출된 부분을 탭하면 정상 동작한다.) 7월 열끗(id=24) 탭.
    expect(find.byKey(const ValueKey('hand-24')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('hand-24')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // 낸 카드(24)는 손에서 사라지고(즉시 커밋 → 갱신 반영), 다른 손패(2)는 남는다.
    expect(find.byKey(const ValueKey('hand-24')), findsNothing);
    expect(find.byKey(const ValueKey('hand-2')), findsOneWidget);
  });

  testWidgets('수를 두면(StreamBuilder 경로) 카드 비행 애니메이션이 트리거된다', (tester) async {
    // 회귀 방지: GameSession.watch() 허브 + didUpdateWidget 안무 트리거가
    // 실제 갱신 흐름에서 동작하는지(=클릭해도 모션이 없던 버그) 검증한다.
    SharedPreferences.setMockInitialValues({});
    final identity = await IdentityService.load();
    final svc = LocalRoomService();
    final session = await _setupSession(svc);

    await tester.pumpWidget(_wrapLive(session, identity));
    await tester.pumpAndSettle();

    // 연출 시작 전에는 비행 레이어가 없다.
    expect(find.byKey(const ValueKey('gostop-flying')), findsNothing);

    // 1월 피(id=2) 를 내면 바닥 1월 매치 → 비행/캡처 + 더미 뒤집기 안무 시작.
    await tester.tap(find.byKey(const ValueKey('hand-2')), warnIfMissed: false);
    await tester.pump(); // submit → 스트림 갱신 → didUpdateWidget
    await tester.pump(const Duration(milliseconds: 150)); // 안무 진행 중

    // 비행 레이어가 화면에 떠 있어야 한다(모션이 실제로 재생됨).
    expect(find.byKey(const ValueKey('gostop-flying')), findsOneWidget);

    // 안무가 끝나면 비행 레이어는 사라진다.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gostop-flying')), findsNothing);
  });
}
