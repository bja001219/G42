/// 오목(자유 5목) 순수 로직.
///
/// 보드는 15x15, index = row*15+col 인 225자 String으로 인코딩한다.
/// '.' = 빈칸, 'B' = 흑, 'W' = 백.
library;

const int kOmokSize = 15;
const int kOmokCells = kOmokSize * kOmokSize;

/// 빈 보드 문자열.
String emptyOmokBoard() => '.' * kOmokCells;

/// (row, col) → index.
int omokIndex(int row, int col) => row * kOmokSize + col;

/// index → row.
int omokRow(int index) => index ~/ kOmokSize;

/// index → col.
int omokCol(int index) => index % kOmokSize;

/// 좌표가 보드 안인지.
bool _inside(int row, int col) =>
    row >= 0 && row < kOmokSize && col >= 0 && col < kOmokSize;

/// [board]의 [index]가 비어 있는지.
bool isEmptyCell(String board, int index) =>
    index >= 0 && index < kOmokCells && board[index] == '.';

/// [index]에 [stone]('B'|'W')을 둔 새 보드 문자열을 반환.
String placeStone(String board, int index, String stone) {
  final chars = board.split('');
  chars[index] = stone;
  return chars.join();
}

/// 보드가 가득 찼는지(무승부 판정용).
bool isBoardFull(String board) => !board.contains('.');

/// 방금 [lastIndex]에 [stone]을 둔 결과로 5목(이상)이 완성됐는지.
///
/// 가로/세로/두 대각선 4방향을 검사한다. 자유 5목이므로 6목 이상도 승리로 본다.
bool isWin(String board, int lastIndex, String stone) =>
    winningLine(board, lastIndex, stone).isNotEmpty;

/// 방금 [lastIndex]에 [stone]을 둬서 완성된 5목(이상)을 이루는 칸들의 index 목록.
///
/// 승리가 아니면 빈 리스트. 장목(6목 이상)이면 연속된 칸을 모두 포함한다.
/// 가장 먼저 발견된 방향(가로→세로→대각)의 연속 줄을 정렬해 반환한다.
/// 결과 화면에서 "어디로 이겼는지" 승리선을 강조 표시하는 데 쓴다.
List<int> winningLine(String board, int lastIndex, String stone) {
  if (lastIndex < 0 || lastIndex >= kOmokCells) return const [];
  if (board[lastIndex] != stone) return const [];

  final row = omokRow(lastIndex);
  final col = omokCol(lastIndex);

  // (dr, dc): 가로, 세로, 우하향 대각, 우상향 대각.
  const dirs = [
    [0, 1],
    [1, 0],
    [1, 1],
    [1, -1],
  ];

  for (final d in dirs) {
    final dr = d[0];
    final dc = d[1];
    final line = <int>[lastIndex]; // 방금 둔 돌 포함.

    // 정방향으로 연속 카운트.
    var r = row + dr;
    var c = col + dc;
    while (_inside(r, c) && board[omokIndex(r, c)] == stone) {
      line.add(omokIndex(r, c));
      r += dr;
      c += dc;
    }

    // 역방향으로 연속 카운트.
    r = row - dr;
    c = col - dc;
    while (_inside(r, c) && board[omokIndex(r, c)] == stone) {
      line.add(omokIndex(r, c));
      r -= dr;
      c -= dc;
    }

    if (line.length >= 5) {
      line.sort();
      return line;
    }
  }

  return const [];
}

/// seat 0(호스트) → 흑('B'), seat 1(게스트) → 백('W').
String stoneForSeat(int seat) => seat == 0 ? 'B' : 'W';
