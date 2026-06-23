import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/chess/chess_logic.dart';

/// FEN 문자열 → ChessPosition. FEN의 말 배치는 8랭크→1랭크, a→h 순서라
/// 엔진의 index(0=a8 ... 63=h1)와 정확히 일치한다.
ChessPosition fromFen(String fen) {
  final parts = fen.split(' ');
  final sb = StringBuffer();
  for (final ch in parts[0].split('')) {
    if (ch == '/') continue;
    final n = int.tryParse(ch);
    if (n != null) {
      sb.write('.' * n);
    } else {
      sb.write(ch);
    }
  }
  final board = sb.toString();
  assert(board.length == 64, 'FEN board length ${board.length}');
  final whiteToMove = parts[1] == 'w';
  final castling = parts[2];
  var ep = -1;
  if (parts.length > 3 && parts[3] != '-') {
    final file = parts[3].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rankChar = int.parse(parts[3][1]);
    ep = (8 - rankChar) * 8 + file;
  }
  return ChessPosition(
    board: board,
    whiteToMove: whiteToMove,
    castling: castling,
    enPassant: ep,
  );
}

/// 표준 perft: depth까지 도달 가능한 합법 노드(리프) 수.
int perft(ChessPosition pos, int depth) {
  if (depth == 0) return 1;
  var nodes = 0;
  for (final m in pos.legalMoves()) {
    nodes += perft(pos.apply(m), depth - 1);
  }
  return nodes;
}

void main() {
  group('ChessPosition', () {
    test('초기 위치는 합법수 20개 (백)', () {
      final pos = ChessPosition.initial();
      expect(pos.legalMoves().length, 20);
    });

    test('초기 위치에서 체크 아님', () {
      final pos = ChessPosition.initial();
      expect(pos.inCheck(), false);
      expect(pos.outcome(), ChessOutcome.ongoing);
    });

    test('1.e4 후 흑도 합법수 20개', () {
      final pos = ChessPosition.initial();
      // e2 = index 52, e4 = index 36.
      final next = pos.apply(const ChessMove(52, 36));
      expect(next.whiteToMove, false);
      expect(next.legalMoves().length, 20);
      expect(next.enPassant, 44); // e3
    });

    test("바보 메이트(Fool's mate): 체크메이트 판정", () {
      var pos = ChessPosition.initial();
      // 1. f3 (f2=53 -> f3=45)
      pos = pos.apply(const ChessMove(53, 45));
      // 1... e5 (e7=12 -> e5=28)
      pos = pos.apply(const ChessMove(12, 28));
      // 2. g4 (g2=54 -> g4=38)
      pos = pos.apply(const ChessMove(54, 38));
      // 2... Qh4# (d8=3 -> h4=39)
      pos = pos.apply(const ChessMove(3, 39));
      expect(pos.inCheck(), true);
      expect(pos.outcome(), ChessOutcome.checkmate);
    });

    test('스테일메이트 판정', () {
      // 흑 킹 a8, 백 퀸 b6, 백 킹 c6, 흑 차례 → 스테일메이트.
      const board =
          'k.......'
          '........'
          '.QK.....'
          '........'
          '........'
          '........'
          '........'
          '........';
      const pos = ChessPosition(
        board: board,
        whiteToMove: false,
        castling: '-',
        enPassant: -1,
      );
      expect(pos.inCheck(), false);
      expect(pos.legalMoves(), isEmpty);
      expect(pos.outcome(), ChessOutcome.stalemate);
    });

    test('킹사이드 캐슬링 합법수 포함', () {
      // 백 킹 e1(60), 룩 h1(63), 경로 비어있음.
      const board =
          'rnbqkbnr'
          'pppppppp'
          '........'
          '........'
          '........'
          '........'
          'PPPPPPPP'
          'RNBQK..R';
      const pos = ChessPosition(
        board: board,
        whiteToMove: true,
        castling: 'KQkq',
        enPassant: -1,
      );
      final castles = pos.legalMovesFrom(60).where((m) => m.isCastle).toList();
      expect(castles.length, 1);
      expect(castles.first.to, 62); // g1
    });

    test('앙파상 잡기', () {
      // 백 폰 e5(28), 흑 폰 d7->d5로 방금 두칸, ep 타겟 d6(19).
      const board =
          '....k...'
          '........'
          '........'
          '...pP...'
          '........'
          '........'
          '........'
          '....K...';
      const pos = ChessPosition(
        board: board,
        whiteToMove: true,
        castling: '-',
        enPassant: 19,
      );
      final ep = pos.legalMovesFrom(28).where((m) => m.isEnPassant).toList();
      expect(ep.length, 1);
      expect(ep.first.to, 19);
      final after = pos.apply(ep.first);
      expect(after.board[27], '.'); // d5의 흑 폰 제거됨
    });

    test('프로모션은 퀸으로', () {
      // 백 폰 a7(8), 승급 a8(0). 흑 킹 멀리.
      const board =
          '.......k'
          'P.......'
          '........'
          '........'
          '........'
          '........'
          '........'
          'K.......';
      const pos = ChessPosition(
        board: board,
        whiteToMove: true,
        castling: '-',
        enPassant: -1,
      );
      final promo = pos.legalMovesFrom(8).where((m) => m.to == 0).toList();
      expect(promo.length, 1);
      expect(promo.first.promotion, 'Q');
      final after = pos.apply(promo.first);
      expect(after.board[0], 'Q');
    });

    test('핀된 말은 킹을 노출시키는 수를 둘 수 없음', () {
      // 백 킹 e1(60), 백 비숍 e2(52), 흑 룩 e8(4) — e파일 핀.
      const board =
          '....r...'
          '........'
          '........'
          '........'
          '........'
          '........'
          '....B...'
          '....K...';
      const pos = ChessPosition(
        board: board,
        whiteToMove: true,
        castling: '-',
        enPassant: -1,
      );
      // 비숍은 e파일을 벗어나면 킹이 노출되므로 합법수 없음.
      expect(pos.legalMovesFrom(52), isEmpty);
    });
  });

  // perft = 이동생성/합법성/특수수(캐슬링·앙파상·프로모션·핀·체크)의 정확성을
  // 검증하는 표준 기법. 공인 기준값과 일치하면 룰 구현이 사실상 증명된다.
  group('perft (공인 기준값 대조)', () {
    test('초기 위치 perft 1~4', () {
      final pos = ChessPosition.initial();
      expect(perft(pos, 1), 20);
      expect(perft(pos, 2), 400);
      expect(perft(pos, 3), 8902);
      expect(perft(pos, 4), 197281);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Kiwipete 위치 perft 1~3 (캐슬링·앙파상 다수)', () {
      final pos = fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -',
      );
      expect(perft(pos, 1), 48);
      expect(perft(pos, 2), 2039);
      expect(perft(pos, 3), 97862);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Position 3 perft 1~4 (앙파상·핀 엣지케이스)', () {
      final pos = fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -');
      expect(perft(pos, 1), 14);
      expect(perft(pos, 2), 191);
      expect(perft(pos, 3), 2812);
      expect(perft(pos, 4), 43238);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
