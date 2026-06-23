import 'models/room.dart';
import 'services/room_service.dart';

/// 게임 위젯과 방(전송 계층)을 잇는 다리.
///
/// 게임은 보통 다음 패턴으로 사용한다:
/// ```dart
/// StreamBuilder<Room>(
///   stream: session.watch(),
///   builder: (context, snap) {
///     final room = snap.data;
///     ... room.state 를 그려주고 ...
///     // 수를 두면:
///     session.submit(newState, nextTurn: opponentId);
///   },
/// )
/// ```
class GameSession {
  /// 이 기기의 플레이어 id.
  final String myPlayerId;
  final String roomCode;
  final RoomService service;

  /// 핫시트(동일 기기 2인) 모드 여부. true면 한 화면에서 양쪽을 모두 조작.
  final bool hotseat;

  GameSession({
    required this.myPlayerId,
    required this.roomCode,
    required this.service,
    this.hotseat = false,
  });

  Stream<Room> watch() => service.watchRoom(roomCode);

  /// 지금 내가 입력 가능한 차례인가. 핫시트면 항상 true.
  bool isMyTurn(Room room) => hotseat || room.turn == myPlayerId;

  /// 지금 '내가 조작하는' 플레이어 id.
  /// - 온라인: 항상 나.
  /// - 핫시트: 현재 차례인 쪽(없으면 첫 번째 플레이어).
  String actingPlayerId(Room room) {
    if (!hotseat) return myPlayerId;
    if (room.turn != null && room.turn!.isNotEmpty) return room.turn!;
    return room.playerIds.isNotEmpty ? room.playerIds.first : myPlayerId;
  }

  /// 좌석 인덱스(0 = 호스트, 1 = 게스트).
  int seatIndex(Room room, String playerId) => room.playerIds.indexOf(playerId);

  RoomPlayer? opponentOf(Room room, String playerId) =>
      room.opponentOf(playerId);

  /// 게임 상태 전체를 갱신한다(항상 통째로 전달).
  Future<void> submit(
    Map<String, dynamic> state, {
    String? nextTurn,
    RoomStatus? status,
    String? winner,
  }) {
    final patch = <String, dynamic>{'state': state};
    if (nextTurn != null) patch['turn'] = nextTurn;
    if (status != null) patch['status'] = status.name;
    if (winner != null) patch['winner'] = winner;
    return service.updateRoom(roomCode, patch);
  }

  /// 임의의 top-level 필드 패치.
  Future<void> patch(Map<String, dynamic> patch) =>
      service.updateRoom(roomCode, patch);

  /// 재대국: 새 초기 상태로 리셋.
  Future<void> rematch(Map<String, dynamic> freshState, String firstTurn) =>
      service.updateRoom(roomCode, {
        'state': freshState,
        'turn': firstTurn,
        'status': RoomStatus.playing.name,
        'winner': null,
      });
}
