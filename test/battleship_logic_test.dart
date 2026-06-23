import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/battleship/battleship_logic.dart';

void main() {
  String fullBoard() {
    var b = BattleshipLogic.emptyBoard();
    b = BattleshipLogic.place(b, BattleshipLogic.shipCells(0, 0, 5, true)!, 0);
    b = BattleshipLogic.place(b, BattleshipLogic.shipCells(1, 0, 4, true)!, 1);
    b = BattleshipLogic.place(b, BattleshipLogic.shipCells(2, 0, 3, true)!, 2);
    b = BattleshipLogic.place(b, BattleshipLogic.shipCells(3, 0, 2, true)!, 3);
    return b;
  }

  test('빈 보드는 100칸 모두 물', () {
    final b = BattleshipLogic.emptyBoard();
    expect(b.length, 100);
    expect(b.split('').every((c) => c == '.'), true);
  });

  test('shipCells: 범위 밖이면 null', () {
    expect(BattleshipLogic.shipCells(0, 8, 5, true), isNull); // 가로 8..12
    expect(BattleshipLogic.shipCells(8, 0, 5, false), isNull); // 세로 8..12
    expect(BattleshipLogic.shipCells(0, 0, 5, true), [0, 1, 2, 3, 4]);
    expect(BattleshipLogic.shipCells(0, 0, 3, false), [0, 10, 20]);
  });

  test('isFree: 겹치면 false', () {
    var b = BattleshipLogic.emptyBoard();
    b = BattleshipLogic.place(b, [0, 1, 2, 3, 4], 0);
    expect(BattleshipLogic.isFree(b, [4, 5, 6]), false); // 4 겹침
    expect(BattleshipLogic.isFree(b, [5, 6, 7]), true);
  });

  test('isComplete: 4척 모두 정확한 길이여야 true', () {
    expect(BattleshipLogic.isComplete(fullBoard()), true);
    // 함선 하나 제거하면 미완성.
    final missing = BattleshipLogic.removeShip(fullBoard(), 2);
    expect(BattleshipLogic.isComplete(missing), false);
  });

  test('randomBoard(시드 고정): 항상 완성된 함대', () {
    for (final seed in [1, 7, 42, 99, 1234]) {
      final b = BattleshipLogic.randomBoard(Random(seed));
      expect(BattleshipLogic.isComplete(b), true, reason: 'seed=$seed');
    }
  });

  test('fire: 함선이면 X, 물이면 O', () {
    final b = fullBoard();
    var shots = BattleshipLogic.emptyShots();
    shots = BattleshipLogic.fire(shots, b, 0); // ship0
    shots = BattleshipLogic.fire(shots, b, 99); // 물
    expect(shots[0], 'X');
    expect(shots[99], 'O');
  });

  test('isShipSunk / sunkShipAt / remainingShips', () {
    final b = fullBoard();
    var shots = BattleshipLogic.emptyShots();
    // ship3(인덱스 30,31)만 격침.
    shots = BattleshipLogic.fire(shots, b, 30);
    shots = BattleshipLogic.fire(shots, b, 31);
    expect(BattleshipLogic.isShipSunk(shots, b, 3), true);
    expect(BattleshipLogic.isShipSunk(shots, b, 0), false);
    expect(BattleshipLogic.sunkShipAt(shots, b, 31), 3);
    expect(BattleshipLogic.sunkShipAt(shots, b, 30), 3);
    expect(BattleshipLogic.remainingShips(shots, b), 3);
  });

  test('allSunk: 모든 함선 칸 명중 시 승리', () {
    final b = fullBoard();
    var shots = BattleshipLogic.emptyShots();
    expect(BattleshipLogic.allSunk(shots, b), false);
    for (var i = 0; i < b.length; i++) {
      if (b[i] != '.') shots = BattleshipLogic.fire(shots, b, i);
    }
    expect(BattleshipLogic.allSunk(shots, b), true);
    expect(BattleshipLogic.remainingShips(shots, b), 0);
  });
}
