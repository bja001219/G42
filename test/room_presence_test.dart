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

/// presence 배선 검증용 가짜 서비스(heartbeat 호출 카운트 + 방 emit).
class _FakeRoomService implements RoomService {
  final _ctrl = StreamController<Room>.broadcast();
  int beats = 0;

  void emit(Room room) => _ctrl.add(room);

  @override
  bool get isOnline => true;
  @override
  String get label => 'fake';
  @override
  Stream<Room> watchRoom(String code) => _ctrl.stream;
  @override
  Future<void> heartbeat(String code, String playerId) async => beats++;
  @override
  Future<void> updateRoom(String code, Map<String, dynamic> patch) async {}
  @override
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  }) async {}
  @override
  Future<void> leaveRoom(String code, String playerId) async {}
  @override
  Future<Room> createRoom({String gameId = '', required RoomPlayer host}) async =>
      throw UnimplementedError();
  @override
  Future<JoinResult> joinRoom({
    required String code,
    required RoomPlayer player,
  }) async =>
      throw UnimplementedError();
}

Room _room({int players = 2, Map<String, int> beats = const {}}) => Room(
      code: 'TEST',
      gameId: '',
      status: RoomStatus.waiting,
      players: [
        const RoomPlayer(id: 'host', name: '방장'),
        if (players >= 2) const RoomPlayer(id: 'guest', name: '게스트'),
      ],
      hostId: 'host',
      heartbeats: beats,
    );

Future<IdentityService> _identity() async {
  SharedPreferences.setMockInitialValues({
    'playerId': 'host',
    'playerName': '방장',
    'nameConfirmed': true,
  });
  return IdentityService.load();
}

Widget _harness(_FakeRoomService svc, IdentityService id) => AppServices(
      identity: id,
      roomService: svc,
      scoreStore: LocalScoreStore(),
      firebaseReady: true,
      child: const MaterialApp(home: RoomLobbyScreen(code: 'TEST', isHost: true)),
    );

void main() {
  testWidgets('온라인 입장 시 내 heartbeat 송신을 시작한다', (tester) async {
    final svc = _FakeRoomService();
    final id = await _identity();
    await tester.pumpWidget(_harness(svc, id));
    svc.emit(_room());
    await tester.pump();

    // 입장 즉시 1회 이상 heartbeat 가 나가야 한다(sender 가 배선됨).
    expect(svc.beats, greaterThanOrEqualTo(1));

    // 정리: 위젯을 내려 dispose(타이머 취소)되게 한다.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('정상 세션에서는 "상대 연결 확인" 안내가 뜨지 않는다(보수적)', (tester) async {
    final svc = _FakeRoomService();
    final id = await _identity();
    await tester.pumpWidget(_harness(svc, id));

    // 상대 heartbeat 가 정상적으로 올라가는 동안엔 절대 끊김 안내가 없어야 한다.
    for (var b = 1; b <= 3; b++) {
      svc.emit(_room(beats: {'guest': b}));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('상대 연결 확인'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
