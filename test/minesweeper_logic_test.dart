import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/minesweeper/minesweeper_logic.dart';

void main() {
  group('MinesweeperLogic', () {
    test('neighbors: 모서리/가장자리/중앙', () {
      const g = MinesweeperLogic(rows: 3, cols: 3);
      expect(g.neighbors(0).toSet(), {1, 3, 4}); // 좌상 모서리
      expect(g.neighbors(4).toSet(), {0, 1, 2, 3, 5, 6, 7, 8}); // 중앙 8칸
      expect(g.neighbors(8).toSet(), {4, 5, 7}); // 우하 모서리
    });

    test('placeMines: 첫 클릭 칸과 (자리가 충분하면) 그 이웃은 안전', () {
      const g = MinesweeperLogic(rows: 9, cols: 9);
      for (final seed in [1, 7, 42, 99, 1234]) {
        const safe = 40; // 중앙
        final mines = g.placeMines(10, safe, Random(seed));
        expect(mines.length, 10, reason: 'seed=$seed');
        final set = mines.toSet();
        expect(set.contains(safe), false, reason: 'seed=$seed 첫 클릭은 안전');
        for (final nb in g.neighbors(safe)) {
          expect(set.contains(nb), false, reason: 'seed=$seed 이웃 $nb 안전');
        }
      }
    });

    test('placeMines: 자리가 빠듯하면 이웃은 안전 보장 못 해도 첫 칸은 안전', () {
      const g = MinesweeperLogic(rows: 3, cols: 3); // 9칸
      // 8개 지뢰: 안전칸은 1개뿐 → 첫 클릭 칸만 비워야 한다.
      final mines = g.placeMines(8, 4, Random(3));
      expect(mines.length, 8);
      expect(mines.toSet().contains(4), false);
    });

    test('placeMines: 지뢰 수는 total-1로 클램프', () {
      const g = MinesweeperLogic(rows: 2, cols: 2); // 4칸
      final mines = g.placeMines(99, 0, Random(1));
      expect(mines.length, 3); // 최대 3
      expect(mines.toSet().contains(0), false);
    });

    test('adjacentMines: 인접 지뢰 수 계산', () {
      const g = MinesweeperLogic(rows: 3, cols: 3);
      final mineSet = {0, 2, 6}; // 세 모서리
      expect(g.adjacentMines(1, mineSet), 2); // 0,2 인접
      expect(g.adjacentMines(4, mineSet), 3); // 0,2,6 인접
      expect(g.adjacentMines(8, mineSet), 0); // 인접 지뢰 없음
    });

    test('revealFrom: 0번 칸에서 빈 영역이 펼쳐진다', () {
      const g = MinesweeperLogic(rows: 3, cols: 3);
      final mineSet = {8}; // 우하단 한 칸만 지뢰
      final revealed = List<int>.filled(9, 0);
      final flags = List<int>.filled(9, 0);
      final opened = g.revealFrom(0, mineSet, revealed, flags);
      // 지뢰(8)를 뺀 나머지 8칸이 모두 열려야 한다(주변이 0으로 연결됨).
      expect(opened, {0, 1, 2, 3, 4, 5, 6, 7});
    });

    test('revealFrom: 숫자 칸은 자기 자신만 열고 멈춘다', () {
      const g = MinesweeperLogic(rows: 1, cols: 5);
      final mineSet = {4}; // [_,_,_,_,X]
      final revealed = List<int>.filled(5, 0);
      final flags = List<int>.filled(5, 0);
      // 3번 칸은 지뢰(4)와 인접 → 숫자 1, 자기 자신만 열림.
      final opened = g.revealFrom(3, mineSet, revealed, flags);
      expect(opened, {3});
    });

    test('revealFrom: 깃발 칸은 펼침을 막는다', () {
      const g = MinesweeperLogic(rows: 1, cols: 3);
      final mineSet = <int>{};
      final revealed = List<int>.filled(3, 0);
      final flags = [0, 1, 0]; // 가운데 깃발
      final opened = g.revealFrom(0, mineSet, revealed, flags);
      expect(opened, {0}); // 깃발(1)에서 막혀 2까지 못 감
    });

    test('isCleared: 지뢰 뺀 모든 칸이 열리면 true', () {
      const g = MinesweeperLogic(rows: 2, cols: 2);
      final mineSet = {3};
      expect(g.isCleared([1, 1, 1, 0], mineSet), true);
      expect(g.isCleared([1, 1, 0, 0], mineSet), false);
    });
  });

  group('MinesweeperState', () {
    test('fresh: 빈 보드 + 미생성 + phase playing', () {
      final s = MinesweeperState.fresh(rows: 9, cols: 9, mines: 10);
      expect(MinesweeperState.rowsOf(s), 9);
      expect(MinesweeperState.colsOf(s), 9);
      expect(MinesweeperState.mineCountOf(s), 10);
      expect(MinesweeperState.generatedOf(s), false);
      expect(MinesweeperState.phaseOf(s), 'playing');
      expect(MinesweeperState.revealedOf(s).every((v) => v == 0), true);
      expect(MinesweeperState.flagsOf(s).every((v) => v == 0), true);
    });

    test('applyReveal: 첫 클릭은 절대 지뢰가 아니고 보드를 생성한다', () {
      for (final seed in [1, 2, 3, 42, 1234]) {
        final s = MinesweeperState.fresh(rows: 9, cols: 9, mines: 10);
        final next = MinesweeperState.applyReveal(s, 40, Random(seed));
        expect(MinesweeperState.generatedOf(next), true, reason: 'seed=$seed');
        expect(MinesweeperState.phaseOf(next), isNot('lost'),
            reason: 'seed=$seed 첫 클릭 패배 없음');
        expect(MinesweeperState.revealedOf(next)[40], 1, reason: 'seed=$seed');
      }
    });

    test('applyReveal: 지뢰를 밟으면 lost + hit 기록', () {
      // 결정적으로: 이미 생성된 보드(지뢰 위치 고정)에서 지뢰 칸을 직접 연다.
      final s = MinesweeperState.fresh(rows: 4, cols: 4, mines: 3);
      s['generated'] = true;
      s['mines'] = <int>[5, 6, 10];
      final after = MinesweeperState.applyReveal(s, 5, Random(1));
      expect(MinesweeperState.phaseOf(after), 'lost');
      expect(MinesweeperState.hitOf(after), 5);
    });

    test('applyReveal: 안전 칸을 모두 열면 won', () {
      var s = MinesweeperState.fresh(rows: 3, cols: 3, mines: 1);
      s = MinesweeperState.applyReveal(s, 0, Random(11));
      // 아직 안 열린 안전 칸들을 모두 연다.
      final mine = MinesweeperState.minesOf(s).first;
      for (var i = 0; i < 9; i++) {
        if (i == mine) continue;
        s = MinesweeperState.applyReveal(s, i, Random(11));
      }
      expect(MinesweeperState.phaseOf(s), 'won');
    });

    test('applyFlag: 토글 + 열린 칸은 깃발 불가', () {
      var s = MinesweeperState.fresh(rows: 3, cols: 3, mines: 1);
      s = MinesweeperState.applyFlag(s, 5);
      expect(MinesweeperState.flagsOf(s)[5], 1);
      s = MinesweeperState.applyFlag(s, 5);
      expect(MinesweeperState.flagsOf(s)[5], 0);

      // 0번을 열고 나면 깃발 토글이 무시된다.
      s = MinesweeperState.applyReveal(s, 0, Random(5));
      final before = MinesweeperState.flagsOf(s)[0];
      s = MinesweeperState.applyFlag(s, 0);
      expect(MinesweeperState.flagsOf(s)[0], before);
    });

    test('applyReveal: 깃발 꽂힌 칸은 탭으로 열리지 않는다', () {
      var s = MinesweeperState.fresh(rows: 3, cols: 3, mines: 1);
      s = MinesweeperState.applyFlag(s, 4);
      final after = MinesweeperState.applyReveal(s, 4, Random(1));
      expect(MinesweeperState.revealedOf(after)[4], 0);
      expect(MinesweeperState.generatedOf(after), false); // 생성도 트리거 안 됨
    });

    test('Firestore 라운드트립(List<dynamic>/num)도 안전하게 파싱', () {
      // Firestore는 List<int>를 List<dynamic>(num)로 돌려준다 — 방어 파싱 확인.
      final raw = <String, dynamic>{
        'rows': 2,
        'cols': 2,
        'mineCount': 1,
        'generated': true,
        'mines': <dynamic>[3],
        'revealed': <dynamic>[1, 1, 1, 0],
        'flags': <dynamic>[0, 0, 0, 1],
        'phase': 'playing',
        'hit': -1,
      };
      expect(MinesweeperState.revealedOf(raw), [1, 1, 1, 0]);
      expect(MinesweeperState.flagsOf(raw), [0, 0, 0, 1]);
      expect(MinesweeperState.minesOf(raw), [3]);
      // 안전칸(0,1,2)이 모두 열렸으니 isCleared = true.
      const g = MinesweeperLogic(rows: 2, cols: 2);
      expect(g.isCleared(MinesweeperState.revealedOf(raw), {3}), true);
    });
  });
}
