import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/game_session.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/core/services/room_service.dart';
import 'package:g42/games/omok/omok_logic.dart';
import 'package:g42/ui/game_host_screen.dart';

/// 테스트용 방 서비스: watchRoom 스트림에 임의의 Room 스냅샷을 밀어넣는다.
class _FakeRoomService implements RoomService {
  final _ctrl = StreamController<Room>.broadcast();
  final List<Map<String, dynamic>> updates = [];

  void emit(Room room) => _ctrl.add(room);

  @override
  bool get isOnline => true;

  @override
  String get label => 'fake';

  @override
  Stream<Room> watchRoom(String code) => _ctrl.stream;

  @override
  Future<void> updateRoom(String code, Map<String, dynamic> patch) async {
    updates.add(patch);
  }

  @override
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  }) async {}

  @override
  Future<void> leaveRoom(String code, String playerId) async {}

  @override
  Future<void> heartbeat(String code, String playerId) async {}

  @override
  Future<Room> createRoom({
    String gameId = '',
    required RoomPlayer host,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<JoinResult> joinRoom({
    required String code,
    required RoomPlayer player,
  }) async {
    throw UnimplementedError();
  }
}

Room _omokRoom({
  required RoomStatus status,
  String? winner,
  String? turn,
  required Map<String, dynamic> state,
}) => Room(
  code: 'TEST',
  gameId: 'omok',
  status: status,
  players: const [
    RoomPlayer(id: 'host', name: '방장'),
    RoomPlayer(id: 'guest', name: '게스트'),
  ],
  hostId: 'host',
  turn: turn,
  winner: winner,
  state: state,
);

/// 0~4번 칸(0행 0~4열)에 흑이 5목을 이룬 보드 + 마지막 착수 = 4.
Map<String, dynamic> _winState() {
  final cells = List<String>.filled(kOmokCells, '.');
  for (var i = 0; i < 5; i++) {
    cells[i] = 'B';
  }
  return {'board': cells.join(), 'lastMove': 4};
}

Future<IdentityService> _identity(String id) async {
  SharedPreferences.setMockInitialValues({
    'playerId': id,
    'playerName': '게스트',
    'nameConfirmed': true,
  });
  return IdentityService.load();
}

Widget _harness(
  _FakeRoomService svc,
  IdentityService identity,
  GameSession s,
) => AppServices(
  identity: identity,
  roomService: svc,
  scoreStore: LocalScoreStore(),
  firebaseReady: true,
  child: MaterialApp(home: GameHostScreen(session: s)),
);

void main() {
  testWidgets('오목 승리: 결과 오버레이는 ~5초 뒤에 뜬다(그 전엔 보드/승리선만 노출)', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('guest'); // 진 쪽 시점.
    final session = GameSession(
      myPlayerId: 'guest',
      roomCode: 'TEST',
      service: svc,
    );
    await tester.pumpWidget(_harness(svc, identity, session));

    // 진행 중 → 종료 전이를 만들어 '방금 끝남'으로 인식되게 한다.
    // (호스트/오목 두 겹의 StreamBuilder가 각각 전달받도록 두 번씩 pump.)
    svc.emit(
      _omokRoom(
        status: RoomStatus.playing,
        turn: 'host',
        state: {'board': emptyOmokBoard(), 'lastMove': -1},
      ),
    );
    await tester.pump();
    await tester.pump();

    // 흑(host)이 5목으로 승리.
    svc.emit(
      _omokRoom(
        status: RoomStatus.finished,
        winner: 'host',
        state: _winState(),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 아직 풀스크린 결과 오버레이는 없다(보드를 보여주는 중).
    expect(find.text('같은 게임 한 판 더'), findsNothing);
    expect(find.text('패배'), findsNothing);
    // 대신 승리선을 확인하라는 안내가 뜬다.
    expect(find.text('대국 종료 · 승리선을 확인하세요'), findsOneWidget);

    // ~5초 경과 후 결과 오버레이가 뜬다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('같은 게임 한 판 더'), findsOneWidget);
    expect(find.text('패배'), findsOneWidget);
  });

  testWidgets('오목 무승부: 볼 승리선이 없으므로 결과 오버레이가 즉시 뜬다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('guest');
    final session = GameSession(
      myPlayerId: 'guest',
      roomCode: 'TEST',
      service: svc,
    );
    await tester.pumpWidget(_harness(svc, identity, session));

    svc.emit(
      _omokRoom(
        status: RoomStatus.playing,
        turn: 'host',
        state: {'board': emptyOmokBoard(), 'lastMove': -1},
      ),
    );
    await tester.pump();
    await tester.pump();

    // 무승부로 종료(승리선 없음) → 지연 0, 즉시 표시.
    svc.emit(
      _omokRoom(
        status: RoomStatus.finished,
        winner: 'draw',
        state: {'board': emptyOmokBoard(), 'lastMove': -1},
      ),
    );
    await tester.pump();
    await tester.pump();

    // 호스트 통합 오버레이가 즉시 떴다('같은 게임 한 판 더'는 이 오버레이에만 있다).
    expect(find.text('같은 게임 한 판 더'), findsOneWidget);
    // '무승부'는 호스트 오버레이 + 오목 인라인 박스 양쪽에 나온다.
    expect(find.text('무승부'), findsWidgets);
  });
}
