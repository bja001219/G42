import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/room.dart';
import 'room_service.dart';

/// Firestore 기반 온라인 방 서비스.
///
/// 컬렉션 구조: `rooms/{CODE}` 문서 1개가 Room 전체를 담는다.
class FirebaseRoomService implements RoomService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _db.collection('rooms');

  @override
  bool get isOnline => true;

  @override
  String get label => '온라인 (Firebase)';

  @override
  Future<Room> createRoom({
    required String gameId,
    required RoomPlayer host,
  }) async {
    // 코드 충돌 시 재시도.
    for (var i = 0; i < 8; i++) {
      final code = generateRoomCode();
      final doc = _rooms.doc(code);
      final snap = await doc.get();
      if (snap.exists) continue;

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
      await doc.set(room.toMap());
      return room;
    }
    throw Exception('방 코드 생성에 실패했습니다. 다시 시도해 주세요.');
  }

  @override
  Future<JoinResult> joinRoom({
    required String code,
    required RoomPlayer player,
  }) {
    final doc = _rooms.doc(code.toUpperCase());
    return _db.runTransaction<JoinResult>((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) return const JoinResult(JoinOutcome.notFound, null);

      final room = Room.fromMap(snap.data()!);

      // 이미 들어있으면 재입장으로 처리.
      if (room.players.any((p) => p.id == player.id)) {
        return JoinResult(JoinOutcome.joined, room);
      }
      if (room.isFull) return const JoinResult(JoinOutcome.full, null);

      final updatedPlayers = [...room.players, player];
      tx.update(doc, {
        'players': updatedPlayers.map((p) => p.toMap()).toList(),
      });
      return JoinResult(
        JoinOutcome.joined,
        room.copyWith(players: updatedPlayers),
      );
    });
  }

  @override
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  }) {
    return _rooms.doc(code.toUpperCase()).update({
      'state': initialState,
      'turn': firstTurn,
      'status': RoomStatus.playing.name,
      'winner': null,
    });
  }

  @override
  Stream<Room> watchRoom(String code) => _rooms
      .doc(code.toUpperCase())
      .snapshots()
      .where((s) => s.exists)
      .map((s) => Room.fromMap(s.data()!));

  @override
  Future<void> updateRoom(String code, Map<String, dynamic> patch) =>
      _rooms.doc(code.toUpperCase()).update(patch);

  @override
  Future<void> leaveRoom(String code, String playerId) async {
    final doc = _rooms.doc(code.toUpperCase());
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) return;
      final room = Room.fromMap(snap.data()!);
      final remaining = room.players.where((p) => p.id != playerId).toList();
      if (remaining.isEmpty) {
        tx.delete(doc);
      } else {
        tx.update(doc, {
          'players': remaining.map((p) => p.toMap()).toList(),
          'status': RoomStatus.finished.name,
        });
      }
    });
  }
}
