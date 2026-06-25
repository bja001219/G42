import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:g42/core/models/room.dart';
import 'package:g42/core/services/presence.dart';
import 'package:g42/core/services/room_service.dart';

class _CountingRoomService implements RoomService {
  int beats = 0;
  final List<String> beatPlayers = [];

  @override
  Future<void> heartbeat(String code, String playerId) async {
    beats++;
    beatPlayers.add(playerId);
  }

  // --- 미사용 ---
  @override
  bool get isOnline => true;
  @override
  String get label => 'count';
  @override
  Stream<Room> watchRoom(String code) => const Stream.empty();
  @override
  Future<void> updateRoom(String code, Map<String, dynamic> p) async {}
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
  @override
  Future<void> startGame(
    String code, {
    required Map<String, dynamic> initialState,
    required String firstTurn,
  }) async {}
}

void main() {
  group('OpponentPresence (단조 시계)', () {
    // 테스트에서 제어 가능한 단조 경과 시간.
    late Duration clk;
    OpponentPresence make([int staleSec = 45]) => OpponentPresence(
          staleAfter: Duration(seconds: staleSec),
          clock: () => clk,
        );

    setUp(() => clk = Duration.zero);

    test('관측 전에는 절대 stale 이 아니다(보수적 arm)', () {
      final p = make();
      expect(p.isArmed, isFalse);
      clk = const Duration(seconds: 10000);
      // 아무리 시간이 지나도, 상대를 한 번도 못 봤으면 끊김 판정 안 함.
      expect(p.isStale(), isFalse);
    });

    test('null heartbeat 은 arm 시키지 않는다', () {
      final p = make();
      expect(p.observe(null), isFalse);
      expect(p.isArmed, isFalse);
      clk = const Duration(seconds: 10000);
      expect(p.isStale(), isFalse);
    });

    test('첫 관측에서 arm 되고, 임계 전에는 stale 아님', () {
      final p = make(45);
      clk = const Duration(seconds: 0);
      expect(p.observe(5), isTrue); // 살아있음 신호.
      expect(p.isArmed, isTrue);
      clk = const Duration(seconds: 44);
      expect(p.isStale(), isFalse);
      clk = const Duration(seconds: 45);
      expect(p.isStale(), isTrue); // 임계 도달.
    });

    test('값이 계속 바뀌면(상대 살아있음) 절대 stale 되지 않는다', () {
      final p = make(45);
      p.observe(1);
      clk = const Duration(seconds: 40);
      p.observe(2);
      clk = const Duration(seconds: 80);
      expect(p.isStale(), isFalse); // 40초 전에 바뀜 → 아직 살아있음.
      clk = const Duration(seconds: 82);
      p.observe(3);
      clk = const Duration(seconds: 120);
      expect(p.isStale(), isFalse);
    });

    test('같은 값 반복은 침묵으로 보고 임계 후 stale', () {
      final p = make(30);
      expect(p.observe(7), isTrue);
      clk = const Duration(seconds: 10);
      expect(p.observe(7), isFalse); // 변화 없음.
      clk = const Duration(seconds: 29);
      expect(p.isStale(), isFalse);
      clk = const Duration(seconds: 30);
      expect(p.isStale(), isTrue);
    });

    test('값이 다시 바뀌면 stale 상태에서 회복된다', () {
      final p = make(30);
      p.observe(1);
      clk = const Duration(seconds: 31);
      expect(p.isStale(), isTrue);
      expect(p.observe(2), isTrue); // 복귀 신호.
      clk = const Duration(seconds: 40);
      expect(p.isStale(), isFalse);
    });

    test('snooze 는 다음 임계까지 다시 기다린다', () {
      final p = make(30);
      p.observe(1);
      clk = const Duration(seconds: 30);
      expect(p.isStale(), isTrue);
      p.snooze();
      clk = const Duration(seconds: 45);
      expect(p.isStale(), isFalse); // 15초 경과 → 아직.
      clk = const Duration(seconds: 60);
      expect(p.isStale(), isTrue); // 다시 30초 → stale.
    });

    test('disarm(백그라운드) 후엔 새 관측 전까지 stale 판정 안 함', () {
      final p = make(30);
      p.observe(1);
      clk = const Duration(seconds: 20);
      // 백그라운드 진입.
      p.disarm();
      clk = const Duration(seconds: 100); // 백그라운드에서 한참 지남.
      expect(p.isStale(), isFalse); // 무장 해제 → 끊김 판정 안 함.
      // 복귀 후 새 heartbeat 관측 → 다시 arm.
      expect(p.observe(2), isTrue);
      clk = const Duration(seconds: 129);
      expect(p.isStale(), isFalse); // 재무장 시점부터 29초.
      clk = const Duration(seconds: 130);
      expect(p.isStale(), isTrue); // 30초 도달.
    });

    test('벽시계가 바뀌어도 영향 없다(단조 시계 사용)', () {
      // clock 주입이 단조 경과를 보장하므로 DateTime.now() 점프와 무관함을 표현.
      final p = make(30);
      p.observe(1);
      clk = const Duration(seconds: 5); // 시간이 거꾸로 갈 수 없는 단조 소스.
      expect(p.isStale(), isFalse);
      clk = const Duration(seconds: 35);
      expect(p.isStale(), isTrue);
    });
  });

  group('HeartbeatSender', () {
    test('start 는 즉시 1회 + 주기마다 전송, stop 은 멈춘다', () {
      fakeAsync((async) {
        final svc = _CountingRoomService();
        final sender = HeartbeatSender(
          service: svc,
          code: 'ROOM',
          playerId: 'me',
          interval: const Duration(seconds: 10),
        );
        sender.start();
        expect(svc.beats, 1); // 즉시 1회.

        async.elapse(const Duration(seconds: 35));
        expect(svc.beats, 4); // 0s + 10/20/30s.
        expect(svc.beatPlayers, everyElement('me'));

        sender.stop();
        async.elapse(const Duration(seconds: 60));
        expect(svc.beats, 4); // 멈춘 뒤엔 안 늘어남.
      });
    });

    test('start 중복 호출은 타이머를 하나만 유지한다', () {
      fakeAsync((async) {
        final svc = _CountingRoomService();
        final sender = HeartbeatSender(
          service: svc,
          code: 'ROOM',
          playerId: 'me',
          interval: const Duration(seconds: 10),
        );
        sender.start();
        sender.start(); // 두 번째는 무시되어야 한다.
        expect(svc.beats, 1);
        async.elapse(const Duration(seconds: 10));
        expect(svc.beats, 2); // 타이머가 둘이면 3 이 됐을 것.
        sender.stop();
      });
    });
  });
}
