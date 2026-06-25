import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/game_registry.dart';
import 'package:g42/core/game_session.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/ui/game_host_screen.dart';

/// 회귀 가드: 테트리스 인게임이 **작은 폰 + 세이프에어리어(노치/홈 인디케이터)** 에서도
/// 한 화면에 들어와야 한다(오버플로우/세로 스크롤 없음).
///
/// 기존 fit_one_screen_test 는 세이프에어리어 인셋을 0으로 두기 때문에, 노치가 있는
/// 실제 작은 폰에서 SCORE/HOLD/DROP 패널이 화면 밖으로 잘리던 버그를 놓쳤다. 이
/// 테스트는 인셋을 실제처럼 적용해 그 상황을 재현한다.
const _cases = <(Size, EdgeInsets)>[
  (Size(360, 640), EdgeInsets.only(top: 28, bottom: 24)),
  (Size(320, 568), EdgeInsets.zero),
  (Size(320, 568), EdgeInsets.only(top: 24, bottom: 20)),
  (Size(390, 844), EdgeInsets.only(top: 47, bottom: 34)),
];

Future<GameSession> _setup(LocalRoomService svc) async {
  final game = GameRegistry.byId('tetris')!;
  final room = await svc.createRoom(
    gameId: 'tetris',
    host: const RoomPlayer(id: 'host', name: '호스트'),
  );
  await svc.joinRoom(
    code: room.code,
    player: const RoomPlayer(id: 'guest', name: '게스트'),
  );
  final ids = ['host', 'guest'];
  await svc.startGame(
    room.code,
    initialState: game.createInitialStateConfigured(ids, game.defaultConfig),
    firstTurn: game.firstTurn(ids),
  );
  return GameSession(
    myPlayerId: 'host',
    roomCode: room.code,
    service: svc,
    hotseat: false,
  );
}

/// GameHostScreen 하위의 세로 Scrollable 최대 스크롤량(>1 이면 한 화면 위반).
double _verticalScrollExtent(WidgetTester tester) {
  double maxExtent = 0;
  final scrollables = find.descendant(
    of: find.byType(GameHostScreen),
    matching: find.byType(Scrollable),
  );
  for (final el in scrollables.evaluate()) {
    final st = el is StatefulElement ? el.state : null;
    if (st is ScrollableState && st.position.hasContentDimensions) {
      if (axisDirectionToAxis(st.axisDirection) != Axis.vertical) continue;
      final e = st.position.maxScrollExtent;
      if (e > maxExtent) maxExtent = e;
    }
  }
  return maxExtent;
}

void main() {
  for (final (size, pad) in _cases) {
    final label =
        '${size.width.toInt()}x${size.height.toInt()} '
        '(인셋 t${pad.top.toInt()}/b${pad.bottom.toInt()})';
    testWidgets('테트리스 인게임이 $label 에서 한 화면에 들어온다', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final identity = await IdentityService.load();
      final svc = LocalRoomService();
      final session = await _setup(svc);

      await tester.pumpWidget(
        AppServices(
          identity: identity,
          roomService: svc,
          scoreStore: LocalScoreStore(),
          firebaseReady: false,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(padding: pad, viewPadding: pad),
              child: child!,
            ),
            home: GameHostScreen(session: session),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));

      // (1) 레이아웃 오버플로우(RenderFlex 등) 예외가 없어야 한다.
      final ex = tester.takeException();
      expect(ex, isNull, reason: '테트리스 @$label: 레이아웃 오버플로우 — $ex');

      // (2) 세로 스크롤로 가려지는 내용이 없어야 한다.
      final scroll = _verticalScrollExtent(tester);
      expect(
        scroll,
        lessThanOrEqualTo(1.0),
        reason: '테트리스 @$label: 세로로 ${scroll.toStringAsFixed(0)}px 가 잘려 스크롤 필요.',
      );

      // (3) 가독성 회귀 가드: 작은 화면에서 스케일이 줄어도 컨트롤 버튼 라벨이
      //     읽을 수 있는 최소 크기 이상이어야 한다(레이아웃만 검사하던 공백 보완).
      final drop = tester.widget<Text>(find.text('DROP'));
      expect(
        drop.style?.fontSize ?? 0,
        greaterThanOrEqualTo(8.0),
        reason: '테트리스 @$label: DROP 라벨이 너무 작다(${drop.style?.fontSize}px).',
      );
    });
  }
}
