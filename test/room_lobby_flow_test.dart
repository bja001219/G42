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
  testWidgets('상대가 나갔을 때(players<2 && finished) 토스트를 띄운다(자동 홈 복귀)', (
    tester,
  ) async {
    final svc = _FakeRoomService();
    final identity = await _identity('host');
    await tester.pumpWidget(_harness(svc, identity, true));

    svc.emit(_room(status: RoomStatus.finished, players: 1));
    await tester.pump();
    await tester.pump();

    // 자동 홈 복귀 + "상대가 나갔습니다" 토스트.
    expect(find.text('상대가 나갔습니다'), findsOneWidget);
    // 옛 "상대가 방을 나갔어요." 화면/버튼은 더 이상 없다.
    expect(find.text('상대가 방을 나갔어요.'), findsNothing);
  });

  testWidgets('상대 기권(forfeit && 내가 승자)이면 "1점 획득" 토스트를 띄운다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('host');
    await tester.pumpWidget(_harness(svc, identity, true));

    // 게스트가 기권하고 나가서 host가 승점. state에 기권 표식이 남아있다.
    svc.emit(
      _room(
        status: RoomStatus.finished,
        players: 1,
        state: const {'forfeit': true, 'forfeitWinnerId': 'host'},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('상대 기권 — 1점 획득!'), findsOneWidget);
    expect(find.text('상대가 나갔습니다'), findsNothing);
  });

  testWidgets('게임 자연 종료(finished지만 두 명 그대로)는 상대 퇴장 처리를 하지 않는다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('guest');
    await tester.pumpWidget(_harness(svc, identity, false));

    // 게임이 끝나 finished지만 두 명 모두 방에 남아있다.
    svc.emit(_room(status: RoomStatus.finished, players: 2));
    await tester.pump();

    // 상대 퇴장 토스트는 없고, 복귀 대기 UI가 보여야 한다(프롬프트는 게임 화면이 처리).
    expect(find.text('상대가 나갔습니다'), findsNothing);
    expect(find.text('대기실로 돌아가는 중...'), findsOneWidget);
  });

  testWidgets('대칭: 게스트도 활성 제안이 없으면 게임 그리드(picker)를 본다', (tester) async {
    final svc = _FakeRoomService();
    final identity = await _identity('guest');
    await tester.pumpWidget(_harness(svc, identity, false));

    // 둘 다 입장, 제안 없음(gameId='') → 양쪽 picker.
    svc.emit(_room(status: RoomStatus.waiting, players: 2));
    await tester.pump();

    expect(find.text('게임을 골라주세요'), findsOneWidget);
  });

  testWidgets('대칭: 내가 제안자면 picker(수락 대기 안내), 상대면 참가/거절', (tester) async {
    final svc = _FakeRoomService();

    // 1) 호스트가 제안자 → 호스트는 picker + 수락 대기 안내.
    final hostId = await _identity('host');
    await tester.pumpWidget(_harness(svc, hostId, true));
    svc.emit(
      _room(
        status: RoomStatus.waiting,
        players: 2,
        gameId: 'chess',
        state: const {'accept': 'pending', 'proposedBy': 'host'},
      ),
    );
    await tester.pump();
    expect(find.text('게임을 골라주세요'), findsOneWidget);
    expect(find.textContaining('상대 수락 대기 중'), findsOneWidget);

    // 2) 게스트는 같은 제안에 대해 참가/거절을 본다.
    final svc2 = _FakeRoomService();
    final guestId = await _identity('guest');
    await tester.pumpWidget(_harness(svc2, guestId, false));
    svc2.emit(
      _room(
        status: RoomStatus.waiting,
        players: 2,
        gameId: 'chess',
        state: const {'accept': 'pending', 'proposedBy': 'host'},
      ),
    );
    await tester.pump();
    expect(find.text('상대가 선택한 게임'), findsOneWidget);
    expect(find.text('참가'), findsOneWidget);
    expect(find.text('거절'), findsOneWidget);
  });

  testWidgets('피제안자가 [참가]를 누르면 proposedBy를 보존한 채 accept=accepted 패치', (
    tester,
  ) async {
    final svc = _FakeRoomService();
    final guestId = await _identity('guest');
    await tester.pumpWidget(_harness(svc, guestId, false));
    svc.emit(
      _room(
        status: RoomStatus.waiting,
        players: 2,
        gameId: 'chess',
        state: const {'accept': 'pending', 'proposedBy': 'host'},
      ),
    );
    await tester.pump();

    await tester.tap(find.text('참가'));
    await tester.pump();

    final patch = svc.updates.last;
    final state = patch['state'] as Map<String, dynamic>;
    expect(state['accept'], 'accepted');
    expect(state['proposedBy'], 'host'); // 보존.
  });

  testWidgets('호스트가 게임을 고르면 gameId + proposedBy=내id로 제안 패치', (tester) async {
    final svc = _FakeRoomService();
    final hostId = await _identity('host');
    await tester.pumpWidget(_harness(svc, hostId, true));
    svc.emit(_room(status: RoomStatus.waiting, players: 2));
    await tester.pump();

    // 첫 번째 게임 카드를 탭(설정 없는 게임을 가정해 첫 카드를 누른다).
    // 그리드의 GameCard onTap → _pickGame.
    final firstCard = find.text('게임을 골라주세요');
    expect(firstCard, findsOneWidget);
    // 게임 타이틀 중 하나를 탭. 'Chess'/'체스' 등 첫 게임 타이틀로 탭하기 위해
    // GameCard의 InkWell을 직접 탭한다.
    final cards = find.byType(InkWell);
    expect(cards, findsWidgets);
    await tester.tap(cards.first);
    await tester.pumpAndSettle();

    // 설정 없는 게임이면 바로 제안 패치가 남는다.
    final proposalPatch = svc.updates.where(
      (u) => (u['state'] as Map?)?['proposedBy'] == 'host',
    );
    expect(proposalPatch.isNotEmpty, isTrue);
  });
}
