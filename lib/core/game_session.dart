import 'dart:async';

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

  // 단일 소스 구독 허브 + 최신값(replay-1). 아래 watch() 설명 참고.
  Room? _lastRoom;
  StreamController<Room>? _hub;
  StreamSubscription<Room>? _hubSub;

  void _ensureHub() {
    if (_hub != null) return;
    final hub = StreamController<Room>.broadcast();
    _hub = hub;
    _hubSub = service
        .watchRoom(roomCode)
        .listen(
          (r) {
            _lastRoom = r;
            if (!hub.isClosed) hub.add(r);
          },
          onError: (Object e, StackTrace st) {
            if (!hub.isClosed) hub.addError(e, st);
          },
        );
  }

  /// 방 상태 스트림.
  ///
  /// 전송 계층(`watchRoom`)을 **한 번만** 구독(단일 소스)하고, 호출자에게는
  /// "최신값 즉시(replay-1) + 이후 갱신" 스트림을 준다. 두 가지를 동시에 만족:
  ///  1) 호출마다 현재 상태를 즉시 받는다(`watch().first` 가 바로 값을 받음) —
  ///     기존 재방출 의미 유지.
  ///  2) 여러 위젯(GameHostScreen + 각 게임 buildGame)이 watch() 를 각각 호출해도
  ///     **소스 구독은 1개**다. 호출마다 새 소스 스트림을 만들면(특히 Firebase 의
  ///     snapshots().map()) 바깥 위젯 리빌드 때 안쪽 StreamBuilder 가 새 스트림으로
  ///     재구독·리셋되어 didUpdateWidget 기반 애니메이션 트리거가 깨진다.
  Stream<Room> watch() async* {
    _ensureHub();
    final last = _lastRoom;
    if (last != null) yield last;
    yield* _hub!.stream;
  }

  /// 허브 정리(방을 떠날 때 호출 권장). 미호출 시에도 앱 종료까지 소스 1개만 유지.
  void dispose() {
    _hubSub?.cancel();
    _hubSub = null;
    _hub?.close();
    _hub = null;
  }

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
