import 'dart:async';

import '../models/room.dart';
import 'room_service.dart';

/// 인메모리 방 서비스 (Firebase 미설정 시 폴백).
///
/// 같은 앱 인스턴스 안에서만 동작하므로 "동일 기기 핫시트"(한 화면에서 둘이
/// 번갈아) 용도다. 실제 원격 대전은 FirebaseRoomService를 써야 한다.
class LocalRoomService implements RoomService {
  final Map<String, Room> _rooms = {};
  final Map<String, StreamController<Room>> _controllers = {};

  @override
  bool get isOnline => false;

  @override
  String get label => '로컬 (동일 기기)';

  StreamController<Room> _ctrl(String code) =>
      _controllers.putIfAbsent(code, () => StreamController<Room>.broadcast());

  void _emit(String code) {
    final r = _rooms[code];
    if (r != null && _controllers.containsKey(code)) {
      _controllers[code]!.add(r);
    }
  }

  @override
  Future<Room> createRoom({
    required String gameId,
    required RoomPlayer host,
  }) async {
    String code;
    do {
      code = generateRoomCode();
    } while (_rooms.containsKey(code));

    final room = Room(
      code: code,
      gameId: gameId,
      status: RoomStatus.waiting,
      players: [host],
      hostId: host.id,
      turn: null,
      winner: null,
      state: const {},
    );
    _rooms[code] = room;
    scheduleMicrotask(() => _emit(code));
    return room;
  }

  @override
  Future<JoinResult> joinRoom({
    required String code,
    required RoomPlayer player,
  }) async {
    code = code.toUpperCase();
    final room = _rooms[code];
    if (room == null) return const JoinResult(JoinOutcome.notFound, null);
    if (room.players.any((p) => p.id == player.id)) {
      return JoinResult(JoinOutcome.joined, room);
    }
    if (room.isFull) return const JoinResult(JoinOutcome.full, null);

    final updated = room.copyWith(players: [...room.players, player]);
    _rooms[code] = updated;
    _emit(code);
    return JoinResult(JoinOutcome.joined, updated);
  }

  @override
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  }) async {
    code = code.toUpperCase();
    final room = _rooms[code];
    if (room == null) return;
    _rooms[code] = Room(
      code: room.code,
      gameId: room.gameId,
      status: RoomStatus.playing,
      players: room.players,
      hostId: room.hostId,
      turn: firstTurn,
      winner: null,
      state: initialState,
    );
    _emit(code);
  }

  @override
  Stream<Room> watchRoom(String code) {
    code = code.toUpperCase();
    final ctrl = _ctrl(code);
    scheduleMicrotask(() => _emit(code));
    return ctrl.stream;
  }

  @override
  Future<void> updateRoom(String code, Map<String, dynamic> patch) async {
    code = code.toUpperCase();
    final room = _rooms[code];
    if (room == null) return;
    _rooms[code] = room.applyPatch(patch);
    _emit(code);
  }

  @override
  Future<void> leaveRoom(String code, String playerId) async {
    code = code.toUpperCase();
    final room = _rooms[code];
    if (room == null) return;
    final remaining = room.players.where((p) => p.id != playerId).toList();
    if (remaining.isEmpty) {
      _rooms.remove(code);
    } else {
      _rooms[code] = room.copyWith(
        players: remaining,
        status: RoomStatus.finished,
      );
      _emit(code);
    }
  }
}
