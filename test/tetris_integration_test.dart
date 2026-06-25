import 'package:flutter_test/flutter_test.dart';
import 'package:g42/core/models/room.dart';
import 'package:g42/games/tetris/tetris_engine.dart';
import 'package:g42/games/tetris/tetris_game.dart';
import 'package:g42/games/tetris/tetris_net.dart';

void main() {
  Room baseRoom(Map<String, dynamic> state) => Room(
        code: 'ABCD',
        gameId: 'tetris',
        status: RoomStatus.playing,
        players: const [
          RoomPlayer(id: 'p0', name: '호스트'),
          RoomPlayer(id: 'p1', name: '게스트'),
        ],
        hostId: 'p0',
        state: state,
      );

  group('Room.applyPatch dotted state paths (per-seat merge)', () {
    test('두 좌석이 서로 덮어쓰지 않는다', () {
      final initial = TetrisGame().createInitialState(['p0', 'p1']);
      var room = baseRoom(initial);

      // seat 0 가 자기 칸만 갱신.
      room = room.applyPatch({
        'state.s0': {'board': 'AAA', 'lines': 2, 'garbage': 1},
      });
      // seat 1 가 자기 칸만 갱신.
      room = room.applyPatch({
        'state.s1': {'board': 'BBB', 'lines': 5, 'garbage': 3},
      });

      // 두 칸 모두 보존되어야 한다(클로버 없음).
      expect((room.state['s0'] as Map)['board'], 'AAA');
      expect((room.state['s0'] as Map)['lines'], 2);
      expect((room.state['s1'] as Map)['board'], 'BBB');
      expect((room.state['s1'] as Map)['garbage'], 3);
    });

    test('dotted 패치 + top-level(status/winner) 동시 적용', () {
      var room = baseRoom(TetrisGame().createInitialState(['p0', 'p1']));
      room = room.applyPatch({
        'status': RoomStatus.finished.name,
        'winner': 'p0',
        'state.s1': {'board': 'X', 'lines': 0, 'garbage': 0},
      });
      expect(room.status, RoomStatus.finished);
      expect(room.winner, 'p0');
      expect((room.state['s1'] as Map)['board'], 'X');
      // 상대 좌석은 그대로.
      expect(room.state['s0'], isA<Map>());
    });

    test('full state 교체는 기존 동작 유지', () {
      var room = baseRoom({'s0': {}, 's1': {}});
      room = room.applyPatch({
        'state': {'accept': 'pending'},
      });
      expect(room.state['accept'], 'pending');
      expect(room.state.containsKey('s0'), false);
    });
  });

  group('TetrisNet board codec', () {
    test('빈 보드 round-trip', () {
      final engine = TetrisEngine();
      final encoded = TetrisNet.encodeBoard(engine);
      expect(encoded.length, TetrisEngine.rows * TetrisEngine.cols);
      final decoded = TetrisNet.decodeBoard(encoded);
      expect(decoded.length, TetrisEngine.rows);
      expect(decoded[0].length, TetrisEngine.cols);
      engine.dispose();
    });

    test('활성 피스가 인코딩에 포함된다', () {
      final engine = TetrisEngine();
      // 스폰된 활성 피스가 있으므로 적어도 한 칸은 비어있지 않아야 한다.
      final encoded = TetrisNet.encodeBoard(engine);
      expect(encoded.split('').any((ch) => ch != '0'), true);
      engine.dispose();
    });

    test('짧은/널 문자열은 빈 보드로 디코드', () {
      final decoded = TetrisNet.decodeBoard(null);
      expect(decoded.every((row) => row.every((c) => c == null)), true);
      final short = TetrisNet.decodeBoard('123');
      expect(short.every((row) => row.every((c) => c == null)), true);
    });
  });

  group('TetrisEngine attack table', () {
    test('기본 가비지: 1줄=0, 2줄=1, 3줄=2, 4줄=4', () {
      expect(TetrisEngine.baseGarbage(1), 0);
      expect(TetrisEngine.baseGarbage(2), 1);
      expect(TetrisEngine.baseGarbage(3), 2);
      expect(TetrisEngine.baseGarbage(4), 4);
    });

    test('백투백 테트리스는 +1', () {
      expect(TetrisEngine.attackFor(4, 0, false), 4);
      expect(TetrisEngine.attackFor(4, 0, true), 5);
    });

    test('콤보가 보너스를 더한다', () {
      final noCombo = TetrisEngine.attackFor(2, 0, false);
      final withCombo = TetrisEngine.attackFor(2, 3, false);
      expect(withCombo, greaterThan(noCombo));
    });
  });
}
