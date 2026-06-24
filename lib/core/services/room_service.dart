import 'dart:math';

import '../models/room.dart';

/// 방 참가 결과.
enum JoinOutcome { joined, notFound, full }

class JoinResult {
  final JoinOutcome outcome;
  final Room? room;
  const JoinResult(this.outcome, this.room);
}

/// 멀티플레이 전송 계층 추상화.
///
/// 게임 코드는 이 인터페이스에만 의존하므로, 구현체(Firebase / Local / 향후 WebSocket)를
/// 갈아끼워도 게임 로직은 그대로 동작한다.
abstract class RoomService {
  /// 온라인(원격 대전 가능) 여부.
  bool get isOnline;

  /// UI에 표시할 전송 모드 이름.
  String get label;

  /// 방 생성. status=waiting, players=[host]로 시작.
  ///
  /// [gameId]는 선택적이다(기본 ""). 새 흐름에서는 방을 먼저 만들고,
  /// 대기실에서 방장이 게임을 고른 뒤 gameId를 채운다.
  Future<Room> createRoom({String gameId = '', required RoomPlayer host});

  /// 코드로 방 참가.
  Future<JoinResult> joinRoom({
    required String code,
    required RoomPlayer player,
  });

  /// 게임 시작: 초기 상태/첫 차례를 세팅하고 status=playing으로 전환.
  /// 보통 호스트가 두 명이 모인 것을 감지하면 호출한다.
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  });

  /// 방 실시간 구독.
  Stream<Room> watchRoom(String code);

  /// top-level 필드 패치(state/turn/status/winner 등).
  Future<void> updateRoom(String code, Map<String, dynamic> patch);

  /// 방 떠나기.
  Future<void> leaveRoom(String code, String playerId);
}

/// 사람이 읽고 입력하기 쉬운 4자리 방 코드 생성 (헷갈리는 글자 제외).
String generateRoomCode([int length = 4]) {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final rnd = Random();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}
