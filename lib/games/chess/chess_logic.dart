/// 체스 엔진 (순수 Dart, Flutter 비의존).
///
/// 보드 인코딩:
/// - 64자 String. index = rank*8 + file.
///   index 0 = a8 (상단 좌측, 흑 진영) ... index 63 = h1 (하단 우측).
///   위(8랭크) → 아래(1랭크) 로 row-major.
/// - 말: 백 대문자 PNBRQK, 흑 소문자 pnbrqk, 빈칸 '.'.
/// - seat 0(호스트) = 백(white), seat 1 = 흑(black). 백 선공.
library;

/// 한 수를 표현.
class ChessMove {
  /// 출발 square index (0..63).
  final int from;

  /// 도착 square index (0..63).
  final int to;

  /// 프로모션 말 문자(대문자, 예: 'Q'). 프로모션이 아니면 null.
  final String? promotion;

  /// 앙파상으로 잡는 수인지.
  final bool isEnPassant;

  /// 캐슬링 수인지 (킹이 두 칸 이동).
  final bool isCastle;

  const ChessMove(
    this.from,
    this.to, {
    this.promotion,
    this.isEnPassant = false,
    this.isCastle = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ChessMove &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from, to, promotion);

  @override
  String toString() => 'Move($from->$to${promotion ?? ''})';
}

/// 게임 결과.
enum ChessOutcome { ongoing, checkmate, stalemate }

/// 불변 체스 위치(position). 보드 문자열 + 부가 상태를 들고 합법수를 생성.
class ChessPosition {
  /// 64자 보드 문자열.
  final String board;

  /// 차례: true = 백, false = 흑.
  final bool whiteToMove;

  /// 캐슬링 권리. 'KQkq' 부분집합 또는 '-'.
  final String castling;

  /// 앙파상 타겟 square index, 없으면 -1.
  final int enPassant;

  const ChessPosition({
    required this.board,
    required this.whiteToMove,
    required this.castling,
    required this.enPassant,
  });

  static const String startBoard =
      'rnbqkbnr' // 8랭크 (흑)
      'pppppppp' // 7랭크
      '........' // 6랭크
      '........' // 5랭크
      '........' // 4랭크
      '........' // 3랭크
      'PPPPPPPP' // 2랭크 (백)
      'RNBQKBNR'; // 1랭크

  /// 표준 시작 위치(백 차례).
  factory ChessPosition.initial() => const ChessPosition(
    board: startBoard,
    whiteToMove: true,
    castling: 'KQkq',
    enPassant: -1,
  );

  String pieceAt(int index) => board[index];

  static int fileOf(int index) => index % 8;
  static int rankOf(int index) => index ~/ 8; // 0 = 8랭크(상단), 7 = 1랭크(하단)

  static bool _isWhite(String p) => p != '.' && p == p.toUpperCase();
  static bool _isBlack(String p) => p != '.' && p == p.toLowerCase();

  bool isOwnPiece(String p) =>
      p != '.' && (whiteToMove ? _isWhite(p) : _isBlack(p));
  bool isEnemyPiece(String p) =>
      p != '.' && (whiteToMove ? _isBlack(p) : _isWhite(p));

  /// 보드를 새 문자열로 교체.
  static String _set(String board, int index, String piece) =>
      board.substring(0, index) + piece + board.substring(index + 1);

  /// [move]를 적용한 새 위치 반환. (합법성 검증은 호출자 책임)
  ChessPosition apply(ChessMove move) {
    var b = board;
    final moving = b[move.from];
    final isWhitePiece = _isWhite(moving);

    // 앙파상으로 잡힌 폰 제거.
    if (move.isEnPassant) {
      final capturedPawnIndex =
          move.to + (isWhitePiece ? 8 : -8); // 도착 칸 뒤(차례 진영 기준)의 폰
      b = _set(b, capturedPawnIndex, '.');
    }

    // 출발 칸 비우고 도착 칸에 말 배치(프로모션이면 승급).
    b = _set(b, move.from, '.');
    final placed = move.promotion != null
        ? (isWhitePiece
              ? move.promotion!.toUpperCase()
              : move.promotion!.toLowerCase())
        : moving;
    b = _set(b, move.to, placed);

    // 캐슬링이면 룩 이동.
    if (move.isCastle) {
      final rank = rankOf(move.from);
      final kingFile = fileOf(move.to);
      if (kingFile == 6) {
        // 킹사이드: 룩 h→f
        final rookFrom = rank * 8 + 7;
        final rookTo = rank * 8 + 5;
        b = _set(b, rookTo, b[rookFrom]);
        b = _set(b, rookFrom, '.');
      } else {
        // 퀸사이드: 룩 a→d
        final rookFrom = rank * 8 + 0;
        final rookTo = rank * 8 + 3;
        b = _set(b, rookTo, b[rookFrom]);
        b = _set(b, rookFrom, '.');
      }
    }

    // 캐슬링 권리 갱신.
    var newCastling = castling;
    newCastling = _updateCastlingRights(newCastling, move.from, move.to);

    // 앙파상 타겟 갱신: 폰 두 칸 전진 시.
    var newEnPassant = -1;
    if (moving.toUpperCase() == 'P') {
      final diff = move.to - move.from;
      if (diff == -16) {
        newEnPassant = move.from - 8; // 백 폰 두 칸 (위로)
      } else if (diff == 16) {
        newEnPassant = move.from + 8; // 흑 폰 두 칸 (아래로)
      }
    }

    return ChessPosition(
      board: b,
      whiteToMove: !whiteToMove,
      castling: newCastling.isEmpty ? '-' : newCastling,
      enPassant: newEnPassant,
    );
  }

  static String _updateCastlingRights(String rights, int from, int to) {
    if (rights == '-' || rights.isEmpty) return '-';
    var r = rights;
    // 킹 이동 또는 룩 출발/도착 칸 관여 시 권리 박탈.
    // 칸 인덱스: a1=56, h1=63, a8=0, h8=7. e1=60, e8=4.
    void remove(String c) => r = r.replaceAll(c, '');
    if (from == 60) {
      remove('K');
      remove('Q');
    }
    if (from == 4) {
      remove('k');
      remove('q');
    }
    // 룩이 떠나거나 잡히는 칸.
    for (final sq in [from, to]) {
      if (sq == 63) remove('K');
      if (sq == 56) remove('Q');
      if (sq == 7) remove('k');
      if (sq == 0) remove('q');
    }
    return r;
  }

  /// 현재 차례 진영의 킹이 공격받는지.
  bool inCheck() => _kingAttacked(whiteToMove);

  /// [white] 진영의 킹이 공격받는지.
  bool _kingAttacked(bool white) {
    final king = white ? 'K' : 'k';
    final kingIndex = board.indexOf(king);
    if (kingIndex < 0) return false; // 킹이 없으면(테스트 등) 공격 불가 취급.
    return _isSquareAttacked(kingIndex, byWhite: !white);
  }

  /// [index] 칸이 [byWhite] 진영에게 공격받는지.
  bool _isSquareAttacked(int index, {required bool byWhite}) {
    final f = fileOf(index);
    final r = rankOf(index);

    // 폰 공격.
    // 백 폰은 위로(랭크 인덱스 감소)이동, 흑 폰은 아래로.
    if (byWhite) {
      // 백 폰이 index를 공격하려면 index 아래 대각선에 백 폰.
      for (final df in [-1, 1]) {
        final pf = f + df;
        final pr = r + 1; // 아래(랭크 인덱스 +1)
        if (pf >= 0 && pf < 8 && pr >= 0 && pr < 8) {
          if (board[pr * 8 + pf] == 'P') return true;
        }
      }
    } else {
      for (final df in [-1, 1]) {
        final pf = f + df;
        final pr = r - 1; // 위
        if (pf >= 0 && pf < 8 && pr >= 0 && pr < 8) {
          if (board[pr * 8 + pf] == 'p') return true;
        }
      }
    }

    // 나이트 공격.
    const knightDeltas = [
      [-2, -1],
      [-2, 1],
      [2, -1],
      [2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
    ];
    final knight = byWhite ? 'N' : 'n';
    for (final d in knightDeltas) {
      final nf = f + d[0];
      final nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        if (board[nr * 8 + nf] == knight) return true;
      }
    }

    // 킹 공격(인접).
    final king = byWhite ? 'K' : 'k';
    for (var dr = -1; dr <= 1; dr++) {
      for (var df = -1; df <= 1; df++) {
        if (dr == 0 && df == 0) continue;
        final nf = f + df;
        final nr = r + dr;
        if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
          if (board[nr * 8 + nf] == king) return true;
        }
      }
    }

    // 슬라이딩: 비숍/퀸(대각), 룩/퀸(직선).
    const diagonal = [
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1],
    ];
    const straight = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    final bishop = byWhite ? 'B' : 'b';
    final rook = byWhite ? 'R' : 'r';
    final queen = byWhite ? 'Q' : 'q';

    for (final d in diagonal) {
      var nf = f + d[1];
      var nr = r + d[0];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final p = board[nr * 8 + nf];
        if (p != '.') {
          if (p == bishop || p == queen) return true;
          break;
        }
        nf += d[1];
        nr += d[0];
      }
    }
    for (final d in straight) {
      var nf = f + d[1];
      var nr = r + d[0];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final p = board[nr * 8 + nf];
        if (p != '.') {
          if (p == rook || p == queen) return true;
          break;
        }
        nf += d[1];
        nr += d[0];
      }
    }

    return false;
  }

  /// 검증 없는 의사 합법수(pseudo-legal) 생성.
  List<ChessMove> _pseudoMoves() {
    final moves = <ChessMove>[];
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == '.' || !isOwnPiece(p)) continue;
      switch (p.toUpperCase()) {
        case 'P':
          _pawnMoves(i, moves);
          break;
        case 'N':
          _knightMoves(i, moves);
          break;
        case 'B':
          _slideMoves(i, moves, const [
            [-1, -1],
            [-1, 1],
            [1, -1],
            [1, 1],
          ]);
          break;
        case 'R':
          _slideMoves(i, moves, const [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1],
          ]);
          break;
        case 'Q':
          _slideMoves(i, moves, const [
            [-1, -1],
            [-1, 1],
            [1, -1],
            [1, 1],
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1],
          ]);
          break;
        case 'K':
          _kingMoves(i, moves);
          break;
      }
    }
    return moves;
  }

  void _pawnMoves(int index, List<ChessMove> moves) {
    final f = fileOf(index);
    final r = rankOf(index);
    final forward = whiteToMove ? -1 : 1; // 랭크 인덱스 변화량(백은 위로)
    final startRank = whiteToMove ? 6 : 1; // 백 폰 시작=2랭크(인덱스6), 흑=7랭크(인덱스1)
    final promoteRank = whiteToMove ? 0 : 7; // 백 승급=8랭크(인덱스0)

    // 한 칸 전진.
    final oneR = r + forward;
    if (oneR >= 0 && oneR < 8) {
      final oneIndex = oneR * 8 + f;
      if (board[oneIndex] == '.') {
        _addPawnMove(index, oneIndex, oneR == promoteRank, moves);
        // 두 칸 전진.
        if (r == startRank) {
          final twoR = r + 2 * forward;
          final twoIndex = twoR * 8 + f;
          if (board[twoIndex] == '.') {
            moves.add(ChessMove(index, twoIndex));
          }
        }
      }
    }

    // 대각 잡기 + 앙파상.
    for (final df in [-1, 1]) {
      final cf = f + df;
      final cr = r + forward;
      if (cf < 0 || cf >= 8 || cr < 0 || cr >= 8) continue;
      final capIndex = cr * 8 + cf;
      final target = board[capIndex];
      if (target != '.' && isEnemyPiece(target)) {
        _addPawnMove(index, capIndex, cr == promoteRank, moves);
      } else if (capIndex == enPassant && enPassant >= 0) {
        moves.add(ChessMove(index, capIndex, isEnPassant: true));
      }
    }
  }

  void _addPawnMove(int from, int to, bool promote, List<ChessMove> moves) {
    if (promote) {
      // 자동 퀸 허용 — 퀸만 생성(요구사항).
      moves.add(ChessMove(from, to, promotion: 'Q'));
    } else {
      moves.add(ChessMove(from, to));
    }
  }

  void _knightMoves(int index, List<ChessMove> moves) {
    final f = fileOf(index);
    final r = rankOf(index);
    const deltas = [
      [-2, -1],
      [-2, 1],
      [2, -1],
      [2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
    ];
    for (final d in deltas) {
      final nf = f + d[1];
      final nr = r + d[0];
      if (nf < 0 || nf >= 8 || nr < 0 || nr >= 8) continue;
      final ni = nr * 8 + nf;
      final t = board[ni];
      if (t == '.' || isEnemyPiece(t)) moves.add(ChessMove(index, ni));
    }
  }

  void _slideMoves(int index, List<ChessMove> moves, List<List<int>> dirs) {
    final f = fileOf(index);
    final r = rankOf(index);
    for (final d in dirs) {
      var nf = f + d[1];
      var nr = r + d[0];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final ni = nr * 8 + nf;
        final t = board[ni];
        if (t == '.') {
          moves.add(ChessMove(index, ni));
        } else {
          if (isEnemyPiece(t)) moves.add(ChessMove(index, ni));
          break;
        }
        nf += d[1];
        nr += d[0];
      }
    }
  }

  void _kingMoves(int index, List<ChessMove> moves) {
    final f = fileOf(index);
    final r = rankOf(index);
    for (var dr = -1; dr <= 1; dr++) {
      for (var df = -1; df <= 1; df++) {
        if (dr == 0 && df == 0) continue;
        final nf = f + df;
        final nr = r + dr;
        if (nf < 0 || nf >= 8 || nr < 0 || nr >= 8) continue;
        final ni = nr * 8 + nf;
        final t = board[ni];
        if (t == '.' || isEnemyPiece(t)) moves.add(ChessMove(index, ni));
      }
    }
    _castleMoves(index, moves);
  }

  void _castleMoves(int index, List<ChessMove> moves) {
    // 킹이 자기 시작 칸에 있어야 함.
    final rank = rankOf(index);
    final homeRank = whiteToMove ? 7 : 0; // 백 1랭크=인덱스7, 흑 8랭크=인덱스0
    if (rank != homeRank || fileOf(index) != 4) return;
    if (inCheck()) return; // 체크 중에는 캐슬링 불가.

    final kingSide = whiteToMove ? 'K' : 'k';
    final queenSide = whiteToMove ? 'Q' : 'q';
    final enemyWhite = !whiteToMove;

    // 킹사이드: f,g 비고 e,f,g 비공격, h룩 존재.
    if (castling.contains(kingSide)) {
      final fSq = homeRank * 8 + 5;
      final gSq = homeRank * 8 + 6;
      final rookSq = homeRank * 8 + 7;
      final rook = whiteToMove ? 'R' : 'r';
      if (board[fSq] == '.' &&
          board[gSq] == '.' &&
          board[rookSq] == rook &&
          !_isSquareAttacked(fSq, byWhite: enemyWhite) &&
          !_isSquareAttacked(gSq, byWhite: enemyWhite)) {
        moves.add(ChessMove(index, gSq, isCastle: true));
      }
    }
    // 퀸사이드: b,c,d 비고 c,d,e 비공격, a룩 존재.
    if (castling.contains(queenSide)) {
      final bSq = homeRank * 8 + 1;
      final cSq = homeRank * 8 + 2;
      final dSq = homeRank * 8 + 3;
      final rookSq = homeRank * 8 + 0;
      final rook = whiteToMove ? 'R' : 'r';
      if (board[bSq] == '.' &&
          board[cSq] == '.' &&
          board[dSq] == '.' &&
          board[rookSq] == rook &&
          !_isSquareAttacked(dSq, byWhite: enemyWhite) &&
          !_isSquareAttacked(cSq, byWhite: enemyWhite)) {
        moves.add(ChessMove(index, cSq, isCastle: true));
      }
    }
  }

  /// 현재 차례 진영의 모든 합법수(자기 킹이 체크되는 수 제외).
  List<ChessMove> legalMoves() {
    final result = <ChessMove>[];
    final mover = whiteToMove;
    for (final m in _pseudoMoves()) {
      final next = apply(m);
      // apply 후 차례가 바뀌므로, 방금 둔 진영(mover)의 킹 검사.
      if (!next._kingAttacked(mover)) {
        result.add(m);
      }
    }
    return result;
  }

  /// [from]에서 출발하는 합법수 목록.
  List<ChessMove> legalMovesFrom(int from) =>
      legalMoves().where((m) => m.from == from).toList();

  /// 현재 위치의 결과(진행/체크메이트/스테일메이트).
  ChessOutcome outcome() {
    if (legalMoves().isNotEmpty) return ChessOutcome.ongoing;
    return inCheck() ? ChessOutcome.checkmate : ChessOutcome.stalemate;
  }

  /// 현재 차례 진영 킹의 square index (없으면 -1).
  int kingIndex() {
    final king = whiteToMove ? 'K' : 'k';
    return board.indexOf(king);
  }
}
