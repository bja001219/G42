import 'package:flutter_test/flutter_test.dart';
import 'package:g42/core/models/room.dart';

/// 반응속도/보글의 "동시 입력 시 무한 대기" 버그 회귀 방지.
///
/// 두 게임 모두 좌석별 칸(반응시간 / done / 점수)을 각자 기록하는데, 예전엔
/// 전체 state 를 통째로 submit 해서 두 명이 거의 동시에 쓰면 서로의 칸을
/// 덮어써(clobber) 한쪽 값이 사라졌다. 그 결과:
///  - 반응속도: 두 반응시간이 모두 모이지 않아 라운드 판정이 영원히 막힘.
///  - 보글: 두 done 이 모두 모이지 않아 종료가 확정되지 않음.
///
/// 수정은 좌석별 점(dotted) 패치(`state.<map>.<playerId>`)다. Room.applyPatch 는
/// (로컬 서비스가 쓰고, Firestore 중첩 필드 업데이트와 동일 의미로) 해당 칸만
/// 깊게 머지하므로 동시 기록이 서로를 보존한다. 아래 테스트가 그 불변식을 고정한다.
void main() {
  Room baseRoom(String gameId, Map<String, dynamic> state) => Room(
        code: 'ABCD',
        gameId: gameId,
        status: RoomStatus.playing,
        players: const [
          RoomPlayer(id: 'p0', name: '호스트'),
          RoomPlayer(id: 'p1', name: '게스트'),
        ],
        hostId: 'p0',
        state: state,
      );

  group('반응속도 — 동시 탭이 서로를 덮어쓰지 않는다', () {
    test('(버그 재현) 전체 state 통째 제출은 한쪽 반응시간을 0으로 덮어쓴다', () {
      var room = baseRoom('reaction', {
        'reaction': {'p0': 0, 'p1': 0},
      });
      // p0, p1 이 거의 동시에 탭 → 각자 상대 값이 0인 stale 전체 state 를 제출.
      room = room.applyPatch({
        'state': {
          'reaction': {'p0': 120, 'p1': 0},
        },
      });
      room = room.applyPatch({
        'state': {
          'reaction': {'p0': 0, 'p1': 150},
        },
      });
      final reaction = room.state['reaction'] as Map;
      // 나중 제출이 이김 → p0 의 120 이 사라져 판정 불가(데드락).
      expect(reaction['p0'], 0);
      expect(reaction['p1'], 150);
    });

    test('(수정) 좌석별 dotted 패치는 두 반응시간을 모두 보존한다', () {
      var room = baseRoom('reaction', {
        'reaction': {'p0': 0, 'p1': 0},
      });
      room = room.applyPatch({'state.reaction.p0': 120});
      room = room.applyPatch({'state.reaction.p1': 150});
      final reaction = room.state['reaction'] as Map;
      expect(reaction['p0'], 120);
      expect(reaction['p1'], 150);
      // 두 값이 모두 0 이 아니므로 라운드 판정 게이트가 통과한다.
      final bothRecorded =
          (reaction['p0'] as int) != 0 && (reaction['p1'] as int) != 0;
      expect(bothRecorded, true);
    });
  });

  group('보글 — 동시 종료/제출이 서로를 덮어쓰지 않는다', () {
    test('(수정) 좌석별 done 패치는 두 done 을 모두 보존 → 종료 확정 가능', () {
      var room = baseRoom('boggle', {
        'done': {'p0': false, 'p1': false},
        'scores': {'p0': 0, 'p1': 0},
      });
      // 두 명이 동시에 끝내기.
      room = room.applyPatch({'state.done.p0': true});
      room = room.applyPatch({'state.done.p1': true});
      final done = room.state['done'] as Map;
      final everyoneDone =
          room.playerIds.every((p) => (done[p] as bool?) ?? false);
      expect(everyoneDone, true); // 호스트가 결과를 확정할 수 있다.
    });

    test('(수정) 동시 단어 제출(점수)도 서로 보존된다', () {
      var room = baseRoom('boggle', {
        'scores': {'p0': 0, 'p1': 0},
        'found': {
          'p0': <String>[],
          'p1': <String>[],
        },
      });
      room = room.applyPatch({
        'state.scores.p0': 10,
        'state.found.p0': ['APPLE'],
      });
      room = room.applyPatch({
        'state.scores.p1': 20,
        'state.found.p1': ['BANANA'],
      });
      final scores = room.state['scores'] as Map;
      final found = room.state['found'] as Map;
      expect(scores['p0'], 10);
      expect(scores['p1'], 20);
      expect((found['p0'] as List), ['APPLE']);
      expect((found['p1'] as List), ['BANANA']);
    });
  });
}
