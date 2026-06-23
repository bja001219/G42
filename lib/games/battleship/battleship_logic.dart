import 'dart:math';

/// 배틀쉽 순수 로직 (UI / Firestore 의존 없음).
///
/// 보드 인코딩:
/// - 100자 String, index = row*10 + col.
/// - 보드(board): '.'=물, '0'~'3'=함선 인덱스(크기 5,4,3,2 → 0,1,2,3).
/// - 사격(shots): '.'=미발사, 'O'=빗나감, 'X'=명중.
abstract class BattleshipLogic {
  static const int size = 10;
  static const int cells = size * size; // 100

  /// 함선 크기. 인덱스 0,1,2,3 → 길이 5,4,3,2.
  static const List<int> shipSizes = [5, 4, 3, 2];

  static String emptyBoard() => '.' * cells;
  static String emptyShots() => '.' * cells;

  static int idx(int row, int col) => row * size + col;
  static int rowOf(int index) => index ~/ size;
  static int colOf(int index) => index % size;

  static bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;

  /// 특정 함선(길이 [len])을 ([row],[col])에서 [horizontal] 방향으로 놓을 때
  /// 차지하는 셀 인덱스 목록. 범위를 벗어나면 null.
  static List<int>? shipCells(int row, int col, int len, bool horizontal) {
    final cellsList = <int>[];
    for (var i = 0; i < len; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (!inBounds(r, c)) return null;
      cellsList.add(idx(r, c));
    }
    return cellsList;
  }

  /// [board]에 함선 인덱스 [shipIndex]를 [cellsList]에 배치한 새 보드 String.
  static String place(String board, List<int> cellsList, int shipIndex) {
    final chars = board.split('');
    final mark = shipIndex.toString();
    for (final c in cellsList) {
      chars[c] = mark;
    }
    return chars.join();
  }

  /// 보드에서 특정 함선 인덱스를 모두 지운 새 보드 String.
  static String removeShip(String board, int shipIndex) {
    final mark = shipIndex.toString();
    return board.replaceAll(mark, '.');
  }

  /// [cellsList]가 이미 함선이 놓인 칸과 겹치지 않는지 검사.
  static bool isFree(String board, List<int> cellsList) {
    for (final c in cellsList) {
      if (board[c] != '.') return false;
    }
    return true;
  }

  /// 보드에 4척(인덱스 0~3)이 모두 올바른 길이로 배치되었는지 검사.
  static bool isComplete(String board) {
    for (var s = 0; s < shipSizes.length; s++) {
      final count = shipSizes[s];
      final mark = s.toString();
      var found = 0;
      for (var i = 0; i < board.length; i++) {
        if (board[i] == mark) found++;
      }
      if (found != count) return false;
    }
    return true;
  }

  /// 무작위로 4척을 배치한 보드 String을 생성.
  static String randomBoard([Random? rng]) {
    final r = rng ?? Random();
    var board = emptyBoard();
    for (var s = 0; s < shipSizes.length; s++) {
      final len = shipSizes[s];
      var placed = false;
      var attempts = 0;
      while (!placed && attempts < 1000) {
        attempts++;
        final horizontal = r.nextBool();
        final row = r.nextInt(size);
        final col = r.nextInt(size);
        final cellsList = shipCells(row, col, len, horizontal);
        if (cellsList == null) continue;
        if (!isFree(board, cellsList)) continue;
        board = place(board, cellsList, s);
        placed = true;
      }
    }
    return board;
  }

  /// [shots]에서 ([index]) 칸에 사격을 가했을 때의 새 shots String.
  /// 상대 [targetBoard]가 그 칸에 함선이면 'X', 아니면 'O'.
  static String fire(String shots, String targetBoard, int index) {
    final chars = shots.split('');
    final hit = targetBoard[index] != '.';
    chars[index] = hit ? 'X' : 'O';
    return chars.join();
  }

  /// 상대 [targetBoard]의 모든 함선 칸이 내 [shots]에서 'X'로 명중되었는지.
  static bool allSunk(String shots, String targetBoard) {
    for (var i = 0; i < targetBoard.length; i++) {
      if (targetBoard[i] != '.' && shots[i] != 'X') return false;
    }
    return true;
  }

  /// 상대 [targetBoard]에서 함선 인덱스 [shipIndex]가 완전히 격침되었는지
  /// (그 함선의 모든 칸이 내 [shots]에서 'X').
  static bool isShipSunk(String shots, String targetBoard, int shipIndex) {
    final mark = shipIndex.toString();
    var any = false;
    for (var i = 0; i < targetBoard.length; i++) {
      if (targetBoard[i] == mark) {
        any = true;
        if (shots[i] != 'X') return false;
      }
    }
    return any;
  }

  /// 내 [shots] 기준으로 상대 [targetBoard]에서 방금 명중한 칸이
  /// 속한 함선이 격침되었는지. 격침이면 함선 인덱스, 아니면 null.
  static int? sunkShipAt(String shots, String targetBoard, int index) {
    final ch = targetBoard[index];
    if (ch == '.') return null;
    final shipIndex = int.tryParse(ch);
    if (shipIndex == null) return null;
    return isShipSunk(shots, targetBoard, shipIndex) ? shipIndex : null;
  }

  /// 상대 [targetBoard]에서 아직 격침되지 않은 함선 수.
  static int remainingShips(String shots, String targetBoard) {
    var remaining = 0;
    for (var s = 0; s < shipSizes.length; s++) {
      if (!isShipSunk(shots, targetBoard, s)) remaining++;
    }
    return remaining;
  }
}
