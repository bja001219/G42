import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/omok/omok_logic.dart';

/// 여러 (row, col)에 같은 돌을 차례로 놓은 보드 문자열을 만든다.
String _boardWith(String stone, List<List<int>> cells) {
  var board = emptyOmokBoard();
  for (final cell in cells) {
    board = placeStone(board, omokIndex(cell[0], cell[1]), stone);
  }
  return board;
}

void main() {
  group('보드 인코딩', () {
    test('빈 보드는 225자이고 전부 빈칸', () {
      final board = emptyOmokBoard();
      expect(board.length, kOmokCells);
      expect(board.length, 225);
      expect(board.split('').every((c) => c == '.'), true);
    });

    test('index <-> (row, col) 왕복 변환', () {
      for (final rc in [
        [0, 0],
        [0, 14],
        [14, 0],
        [14, 14],
        [7, 7],
        [3, 11],
      ]) {
        final idx = omokIndex(rc[0], rc[1]);
        expect(omokRow(idx), rc[0]);
        expect(omokCol(idx), rc[1]);
      }
      // 모서리 인덱스 값.
      expect(omokIndex(0, 0), 0);
      expect(omokIndex(0, 14), 14);
      expect(omokIndex(14, 14), 224);
    });

    test('placeStone은 해당 칸만 바꾸고 길이를 유지', () {
      final board = placeStone(emptyOmokBoard(), omokIndex(7, 7), 'B');
      expect(board.length, kOmokCells);
      expect(board[omokIndex(7, 7)], 'B');
      expect(isEmptyCell(board, omokIndex(7, 7)), false);
      expect(isEmptyCell(board, omokIndex(7, 8)), true);
    });

    test('stoneForSeat: 0=흑(B), 1=백(W)', () {
      expect(stoneForSeat(0), 'B');
      expect(stoneForSeat(1), 'W');
    });
  });

  group('승리 판정 (자유 5목)', () {
    test('가로 5목 승리', () {
      final cells = [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ];
      final board = _boardWith('B', cells);
      // 마지막에 어느 칸을 두어도 5목이 완성되어 있어야 한다.
      expect(isWin(board, omokIndex(7, 7), 'B'), true);
      expect(isWin(board, omokIndex(7, 3), 'B'), true);
      expect(isWin(board, omokIndex(7, 5), 'B'), true);
    });

    test('세로 5목 승리', () {
      final cells = [
        [2, 6],
        [3, 6],
        [4, 6],
        [5, 6],
        [6, 6],
      ];
      final board = _boardWith('W', cells);
      expect(isWin(board, omokIndex(6, 6), 'W'), true);
      expect(isWin(board, omokIndex(2, 6), 'W'), true);
    });

    test('우하향 대각 5목 승리', () {
      final cells = [
        [4, 4],
        [5, 5],
        [6, 6],
        [7, 7],
        [8, 8],
      ];
      final board = _boardWith('B', cells);
      expect(isWin(board, omokIndex(6, 6), 'B'), true);
      expect(isWin(board, omokIndex(8, 8), 'B'), true);
    });

    test('우상향 대각 5목 승리', () {
      final cells = [
        [8, 2],
        [7, 3],
        [6, 4],
        [5, 5],
        [4, 6],
      ];
      final board = _boardWith('W', cells);
      expect(isWin(board, omokIndex(6, 4), 'W'), true);
      expect(isWin(board, omokIndex(4, 6), 'W'), true);
    });

    test('4목은 승리가 아님', () {
      final cells = [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
      ];
      final board = _boardWith('B', cells);
      expect(isWin(board, omokIndex(7, 6), 'B'), false);
    });

    test('자유 5목: 6목(장목)도 승리로 인정', () {
      final cells = [
        [7, 2],
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ];
      final board = _boardWith('B', cells);
      // 가운데 두어 양쪽으로 이어진 경우에도 승리.
      expect(isWin(board, omokIndex(7, 4), 'B'), true);
      expect(isWin(board, omokIndex(7, 7), 'B'), true);
    });

    test('보드 모서리에서의 5목 승리', () {
      final cells = [
        [0, 0],
        [0, 1],
        [0, 2],
        [0, 3],
        [0, 4],
      ];
      final board = _boardWith('B', cells);
      expect(isWin(board, omokIndex(0, 4), 'B'), true);
    });

    test('줄바꿈을 가로지르는 가짜 가로줄은 승리가 아님', () {
      // (0,12),(0,13),(0,14),(1,0),(1,1) — 인덱스는 연속이지만 같은 가로줄이 아님.
      final cells = [
        [0, 12],
        [0, 13],
        [0, 14],
        [1, 0],
        [1, 1],
      ];
      final board = _boardWith('B', cells);
      expect(isWin(board, omokIndex(0, 14), 'B'), false);
      expect(isWin(board, omokIndex(1, 0), 'B'), false);
    });

    test('다른 색 돌이 끼면 5목이 아님', () {
      var board = _boardWith('B', [
        [7, 3],
        [7, 4],
        [7, 6],
        [7, 7],
      ]);
      board = placeStone(board, omokIndex(7, 5), 'W');
      expect(isWin(board, omokIndex(7, 7), 'B'), false);
    });

    test('마지막 착수 칸의 돌 색이 다르면 false', () {
      final board = _boardWith('B', [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ]);
      // 흑 5목이지만 백으로 질의하면 false.
      expect(isWin(board, omokIndex(7, 7), 'W'), false);
    });

    test('범위를 벗어난 lastIndex는 false', () {
      final board = emptyOmokBoard();
      expect(isWin(board, -1, 'B'), false);
      expect(isWin(board, kOmokCells, 'B'), false);
    });
  });

  group('승리선 (winningLine)', () {
    test('가로 5목의 승리선 = 그 5칸', () {
      final cells = [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ];
      final board = _boardWith('B', cells);
      final line = winningLine(board, omokIndex(7, 7), 'B');
      expect(line.toSet(), {
        omokIndex(7, 3),
        omokIndex(7, 4),
        omokIndex(7, 5),
        omokIndex(7, 6),
        omokIndex(7, 7),
      });
    });

    test('세로 5목의 승리선 = 그 5칸', () {
      final cells = [
        [2, 6],
        [3, 6],
        [4, 6],
        [5, 6],
        [6, 6],
      ];
      final board = _boardWith('W', cells);
      final line = winningLine(board, omokIndex(4, 6), 'W');
      expect(line.length, 5);
      expect(line.toSet(), {
        for (final cell in cells) omokIndex(cell[0], cell[1]),
      });
    });

    test('우하향 대각 승리선', () {
      final cells = [
        [4, 4],
        [5, 5],
        [6, 6],
        [7, 7],
        [8, 8],
      ];
      final board = _boardWith('B', cells);
      final line = winningLine(board, omokIndex(6, 6), 'B');
      expect(line.toSet(), {
        for (final cell in cells) omokIndex(cell[0], cell[1]),
      });
    });

    test('우상향 대각 승리선', () {
      final cells = [
        [8, 2],
        [7, 3],
        [6, 4],
        [5, 5],
        [4, 6],
      ];
      final board = _boardWith('W', cells);
      final line = winningLine(board, omokIndex(6, 4), 'W');
      expect(line.toSet(), {
        for (final cell in cells) omokIndex(cell[0], cell[1]),
      });
    });

    test('6목(장목)이면 6칸 이상을 모두 포함', () {
      final cells = [
        [7, 2],
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ];
      final board = _boardWith('B', cells);
      final line = winningLine(board, omokIndex(7, 4), 'B');
      expect(line.length, greaterThanOrEqualTo(5));
      expect(line.contains(omokIndex(7, 2)), true);
      expect(line.contains(omokIndex(7, 7)), true);
    });

    test('승리선은 정렬되어 반환된다', () {
      final cells = [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ];
      final board = _boardWith('B', cells);
      final line = winningLine(board, omokIndex(7, 5), 'B');
      final sorted = List<int>.from(line)..sort();
      expect(line, sorted);
    });

    test('4목은 승리선이 비어 있음', () {
      final cells = [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
      ];
      final board = _boardWith('B', cells);
      expect(winningLine(board, omokIndex(7, 6), 'B'), isEmpty);
    });

    test('다른 색 돌이 끼면 승리선이 비어 있음', () {
      var board = _boardWith('B', [
        [7, 3],
        [7, 4],
        [7, 6],
        [7, 7],
      ]);
      board = placeStone(board, omokIndex(7, 5), 'W');
      expect(winningLine(board, omokIndex(7, 7), 'B'), isEmpty);
    });

    test('범위를 벗어나거나 색이 다르면 승리선이 비어 있음', () {
      final board = _boardWith('B', [
        [7, 3],
        [7, 4],
        [7, 5],
        [7, 6],
        [7, 7],
      ]);
      expect(winningLine(board, -1, 'B'), isEmpty);
      expect(winningLine(board, kOmokCells, 'B'), isEmpty);
      expect(winningLine(board, omokIndex(7, 7), 'W'), isEmpty);
    });
  });

  group('무승부 판정', () {
    test('빈 보드는 가득 차지 않음', () {
      expect(isBoardFull(emptyOmokBoard()), false);
    });

    test('한 칸이라도 비면 가득 차지 않음', () {
      var board = ('B' * kOmokCells);
      board = placeStone(board, 0, '.');
      expect(isBoardFull(board), false);
    });

    test('빈칸이 없으면 가득 참', () {
      final board = 'B' * kOmokCells;
      expect(isBoardFull(board), true);
    });
  });
}
