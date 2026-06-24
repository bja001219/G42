import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g42/app.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/identity_service.dart';
import 'package:g42/core/services/local_score_store.dart';
import 'package:g42/core/services/room_service.dart';
import 'package:g42/ui/room_lobby_screen.dart';

/// 테스트용 방 서비스: watchRoom 스트림에 임의의 Room 스냅샷을 밀어넣을 수 있다.
/// (게임 위젯/엔진은 건드리지 않고 대기실의 복귀 핸드셰이크 분기만 검증한다.)
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

Room _room({
  required RoomStatus status,
  required int players,
  String gameId = '',
  Map<String, dynamic> state = const {},
}) => Room(
  code: 'TEST',
  gameId: gameId,
  status: status,
  players: [
    const RoomPlayer(id: 'host', name: '방장'),
    if (players >= 2) const RoomPlayer(id: 'guest', name: '게스트'),
  ],
  hostId: 'host',
  state: state,
);

Widget _harness(_FakeRoomService svc, IdentityService identity, bool isHost) =>
    AppServices(
      identity: identity,
      roomService: svc,
      scoreStore: LocalScoreStore(),
      firebaseReady: true,
      child: MaterialApp(
        home: RoomLobbyScreen(code: 'TEST', isHost: isHost),
      ),
    );

Future<IdentityService> _identity(String id) async {
  SharedPreferences.setMockInitialValues({
    'playerId': id,
    'playerName': id == 'host' ? '방장' : '게스트',
    'nameConfirmed': true,
  });
  return IdentityService.load();
}

void main() {
  testWidgets('상대가 실제로 나갔을 때(players<2 && finished)만 "상대 퇴장" 화면을 보여준다', (
    tester,
  ) async {
    final svc = _FakeRoomService();
    final identity = await _identity('host');
    await tester.pumpWidget(_harness(svc, identity, true));

    svc.emit(_room(status: RoomStatus.finished, players: 1));
    await tester.pump();

    expect(find.text('상대가 방을 나갔어요.'), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
  });

  testWidgets('게임 자연 종료(finished지만 두 명 그대로)는 "상대 퇴장" 화면을 띄우지 않는다', (
    tester,
  ) async {
    final svc = _FakeRoomService();
    final identity = await _identity('guest');
    await tester.pumpWidget(_harness(svc, identity, false));

    // 게임이 끝나 finished지만 두 명 모두 방에 남아있다.
    svc.emit(_room(status: RoomStatus.finished, players: 2));
    await tester.pump();

    // '상대 퇴장' 대신 대기실 복귀 대기 UI가 보여야 한다.
    expect(find.text('상대가 방을 나갔어요.'), findsNothing);
    expect(find.text('대기실로 돌아가는 중...'), findsOneWidget);
  });

  testWidgets('방장은 두 명이 남은 채 복귀하면 대기실을 waiting으로 리셋한다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('host');
    await tester.pumpWidget(_harness(svc, identity, true));

    // playing 진입 → 게임 화면 push. gameId는 비워서 GameHostScreen이 실제
    // 게임 위젯이 아니라 대기 스피너만 그리게 한다(게임 위젯 비의존).
    svc.emit(_room(status: RoomStatus.playing, players: 2, gameId: ''));
    await tester.pump();
    await tester.pump();

    // 게임 화면(GameHostScreen)이 떠 있어야 한다(중복 push 가드 동작).
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    // 복귀 전 finished로 전이(게임 종료, 두 명 그대로).
    svc.emit(_room(status: RoomStatus.finished, players: 2));
    await tester.pump();
    navigator.pop();
    // _goToGame의 await가 풀리며 _resetToWaiting이 호출된다(무한 스피너라
    // pumpAndSettle은 못 쓰므로 명시적 pump로 마이크로태스크를 흘린다).
    await tester.pump();
    await tester.pump();

    // 방장이 _resetToWaiting을 호출했어야 한다(status=waiting 패치).
    expect(
      svc.updates.any((u) => u['status'] == RoomStatus.waiting.name),
      isTrue,
    );
  });

  testWidgets('상대 퇴장(players<2)으로 복귀하면 방장은 리셋하지 않는다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('host');
    await tester.pumpWidget(_harness(svc, identity, true));

    svc.emit(_room(status: RoomStatus.playing, players: 2, gameId: ''));
    await tester.pump();
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    // 상대 퇴장: players<2 && finished.
    svc.emit(_room(status: RoomStatus.finished, players: 1));
    await tester.pump();
    navigator.pop();
    await tester.pump();
    await tester.pump();

    // 리셋(waiting 패치)이 일어나면 안 된다.
    expect(
      svc.updates.any((u) => u['status'] == RoomStatus.waiting.name),
      isFalse,
    );
    // 상대 퇴장 화면이 떠야 한다.
    expect(find.text('상대가 방을 나갔어요.'), findsOneWidget);
  });
}
