import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/game_definition.dart';
import 'package:g42/core/game_registry.dart';
import 'package:g42/core/game_session.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_room_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/ui/game_host_screen.dart';

/// 회귀 가드: 모든 게임의 인게임 화면이 핸드폰 한 화면 안에 들어와야 한다.
///
/// 각 게임을 실제 호스트(상단바 + 상대바 + Expanded(게임))에 폰 크기로 마운트한 뒤
///  (1) RenderFlex 오버플로우가 없고
///  (2) 세로 스크롤로 내용이 화면 밖으로 잘리지 않는다(가로 손패 부채는 허용)
/// 를 검증한다. 작은 폰(360x640)까지 통과해야 한다.
///
/// "한 화면" 기준 패턴은 lib/games/chess/chess_board.dart 참고:
///   Column[ 고정 상태바, Expanded(Center(AspectRatio(메인영역))), 고정 컨트롤 ]
const _phoneSizes = <Size>[
  Size(390, 844), // 보통 폰 (iPhone 14급)
  Size(360, 640), // 작은 폰 (구형 안드로이드급)
];

Future<GameSession> _setup(GameDefinition game, LocalRoomService svc) async {
  final room = await svc.createRoom(
    gameId: game.id,
    host: const RoomPlayer(id: 'host', name: '호스트'),
  );
  await svc.joinRoom(
    code: room.code,
    player: const RoomPlayer(id: 'guest', name: '게스트'),
  );
  final ids = ['host', 'guest'];
  final state = game.createInitialStateConfigured(ids, game.defaultConfig);
  await svc.startGame(
    room.code,
    initialState: state,
    firstTurn: game.firstTurn(ids),
  );
  return GameSession(
    myPlayerId: 'host',
    roomCode: room.code,
    service: svc,
    hotseat: false,
  );
}

Widget _wrap(GameSession session, IdentityService identity) {
  return AppServices(
    identity: identity,
    roomService: session.service,
    scoreStore: LocalScoreStore(),
    firebaseReady: false,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameHostScreen(session: session),
    ),
  );
}

/// 세로 Scrollable 의 최대 스크롤량. >1 이면 내용이 화면 아래로 잘려 스크롤이
/// 필요하다는 뜻(= "한 화면" 위반). 가로 손패 부채(horizontal)는 허용이라 제외.
double _verticalScrollExtent(WidgetTester tester) {
  double maxExtent = 0;
  for (final el in find.byType(Scrollable).evaluate()) {
    final state = el is StatefulElement ? el.state : null;
    if (state is ScrollableState && state.position.hasContentDimensions) {
      if (axisDirectionToAxis(state.axisDirection) != Axis.vertical) continue;
      final e = state.position.maxScrollExtent;
      if (e > maxExtent) maxExtent = e;
    }
  }
  return maxExtent;
}

void main() {
  for (final game in GameRegistry.games) {
    for (final size in _phoneSizes) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('${game.id} 인게임이 폰 한 화면($label)에 들어온다', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({});
        final identity = await IdentityService.load();
        final svc = LocalRoomService();
        final session = await _setup(game, svc);

        await tester.pumpWidget(_wrap(session, identity));
        // 애니메이션 게임(reaction/gostop)은 pumpAndSettle 이 멈추지 않으므로 고정 프레임.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 350));

        // (1) 오버플로우(RenderFlex 등) 예외가 없어야 한다.
        final ex = tester.takeException();
        expect(ex, isNull, reason: '${game.id} @$label: 레이아웃 오버플로우 — $ex');

        // (2) 세로 스크롤로 가려지는 내용이 없어야 한다.
        final scroll = _verticalScrollExtent(tester);
        expect(
          scroll,
          lessThanOrEqualTo(1.0),
          reason:
              '${game.id} @$label: 세로로 ${scroll.toStringAsFixed(0)}px 가 화면 밖으로 '
              '잘려 스크롤이 필요하다(한 화면에 안 들어옴).',
        );
      });
    }
  }
}
