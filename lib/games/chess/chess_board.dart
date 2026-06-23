import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'chess_logic.dart';

/// 체스 보드 위젯. 동기화 상태는 room.state에서만 읽고,
/// 선택칸 등 임시 상태는 로컬에서 관리한다.
class ChessBoard extends StatefulWidget {
  final GameSession session;
  final Room room;
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  const ChessBoard({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
  });

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  /// 선택된 출발 칸 (없으면 null).
  int? _selected;

  /// 선택된 말의 합법 도착 칸들.
  List<ChessMove> _selectedMoves = const [];

  GameSession get session => widget.session;
  Room get room => widget.room;

  // ── 상태 디코딩 ──────────────────────────────────────────

  String get _board {
    final b = room.state['board'];
    if (b is String && b.length == 64) return b;
    return ChessPosition.startBoard;
  }

  String get _castling {
    final c = room.state['castling'];
    return (c is String && c.isNotEmpty) ? c : '-';
  }

  int get _enPassant {
    final e = room.state['enPassant'];
    return e is int ? e : (e is num ? e.toInt() : -1);
  }

  /// room.turn(또는 핫시트 차례)로부터 백 차례 여부 도출.
  bool get _whiteToMove {
    final actor = session.actingPlayerId(room);
    // seat 0 = 백. 현재 차례 플레이어의 seat로 판단.
    final turnId = room.turn ?? actor;
    final seat = session.seatIndex(room, turnId);
    return seat == 0;
  }

  ChessPosition get _position => ChessPosition(
    board: _board,
    whiteToMove: _whiteToMove,
    castling: _castling,
    enPassant: _enPassant,
  );

  int? get _lastFrom {
    final lm = room.state['lastMove'];
    if (lm is Map) {
      final f = lm['from'];
      if (f is int) return f;
      if (f is num) return f.toInt();
    }
    return null;
  }

  int? get _lastTo {
    final lm = room.state['lastMove'];
    if (lm is Map) {
      final t = lm['to'];
      if (t is int) return t;
      if (t is num) return t.toInt();
    }
    return null;
  }

  // ── 진영/방향 ────────────────────────────────────────────

  /// 화면에서 내가 조작하는 쪽(actor)의 seat. 0=백, 1=흑.
  int get _mySeat {
    final actor = session.actingPlayerId(room);
    final seat = session.seatIndex(room, actor);
    return seat < 0 ? 0 : seat;
  }

  /// 보드 flip 여부: seat 1(흑)이면 흑이 아래로 보이게 뒤집는다.
  bool get _flipped => _mySeat == 1;

  /// 화면 셀 인덱스(0=좌상단)를 보드 인덱스로 변환.
  int _displayToBoard(int displayIndex) =>
      _flipped ? 63 - displayIndex : displayIndex;

  // ── 입력 ─────────────────────────────────────────────────

  void _onTapCell(int displayIndex) {
    if (!session.isMyTurn(room)) return;
    if (room.status == RoomStatus.finished) return;

    final pos = _position;

    // 핫시트가 아닐 때: 내 색만 조작 가능.
    if (!session.hotseat) {
      final iAmWhite = _mySeat == 0;
      if (pos.whiteToMove != iAmWhite) return;
    }

    final boardIndex = _displayToBoard(displayIndex);
    final piece = pos.pieceAt(boardIndex);

    // 이미 선택된 상태에서 도착 칸을 탭한 경우 → 이동.
    if (_selected != null) {
      final move = _findMove(boardIndex);
      if (move != null) {
        _applyMove(pos, move);
        return;
      }
      // 같은 색 다른 말을 탭하면 재선택, 아니면 선택 해제.
      if (piece != '.' && pos.isOwnPiece(piece)) {
        _select(pos, boardIndex);
      } else {
        setState(() {
          _selected = null;
          _selectedMoves = const [];
        });
      }
      return;
    }

    // 새 선택.
    if (piece != '.' && pos.isOwnPiece(piece)) {
      _select(pos, boardIndex);
    }
  }

  void _select(ChessPosition pos, int boardIndex) {
    setState(() {
      _selected = boardIndex;
      _selectedMoves = pos.legalMovesFrom(boardIndex);
    });
  }

  ChessMove? _findMove(int toBoardIndex) {
    for (final m in _selectedMoves) {
      if (m.to == toBoardIndex) return m;
    }
    return null;
  }

  void _applyMove(ChessPosition pos, ChessMove move) {
    final next = pos.apply(move);
    final outcome = next.outcome();

    final newState = <String, dynamic>{
      'board': next.board,
      'castling': next.castling,
      'enPassant': next.enPassant,
      'lastMove': {'from': move.from, 'to': move.to},
    };

    setState(() {
      _selected = null;
      _selectedMoves = const [];
    });

    if (outcome == ChessOutcome.checkmate) {
      // 방금 둔 진영(pos.whiteToMove)이 승자. 백=seat0, 흑=seat1.
      final winnerSeat = pos.whiteToMove ? 0 : 1;
      final winnerId = room.playerIds.length > winnerSeat
          ? room.playerIds[winnerSeat]
          : room.playerIds.first;
      session.submit(newState, status: RoomStatus.finished, winner: winnerId);
    } else if (outcome == ChessOutcome.stalemate) {
      session.submit(newState, status: RoomStatus.finished, winner: 'draw');
    } else {
      // 다음 차례 플레이어.
      final nextSeat = next.whiteToMove ? 0 : 1;
      final nextId = room.playerIds.length > nextSeat
          ? room.playerIds[nextSeat]
          : room.playerIds.first;
      session.submit(newState, nextTurn: nextId);
    }
  }

  void _rematch() {
    session.rematch(
      widget.createInitialState(room.playerIds),
      widget.firstTurn(room.playerIds),
    );
    setState(() {
      _selected = null;
      _selectedMoves = const [];
    });
  }

  // ── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    final inCheck = pos.inCheck();
    final checkedKing = inCheck ? pos.kingIndex() : -1;

    return Column(
      children: [
        _statusBar(pos, inCheck),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  _boardGrid(pos, checkedKing),
                  if (room.status == RoomStatus.finished) _resultOverlay(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _captured(pos),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _statusBar(ChessPosition pos, bool inCheck) {
    final whiteTurn = pos.whiteToMove;
    final turnColor = whiteTurn ? Colors.white : Colors.black87;
    final label = whiteTurn ? '백(White) 차례' : '흑(Black) 차례';

    String sub;
    if (room.status == RoomStatus.finished) {
      sub = '게임 종료';
    } else if (!session.isMyTurn(room)) {
      sub = '상대 차례를 기다리는 중...';
    } else if (session.hotseat) {
      sub = inCheck ? '체크! 같은 기기에서 진행' : '같은 기기에서 진행';
    } else {
      final iAmWhite = _mySeat == 0;
      sub = (pos.whiteToMove == iAmWhite)
          ? (inCheck ? '체크! 당신 차례' : '당신 차례')
          : '상대 차례';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: turnColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: Icon(
              Icons.castle_rounded,
              size: 16,
              color: whiteTurn ? Colors.black54 : Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    color: inCheck ? G42Colors.bad : Colors.white54,
                    fontSize: 12,
                    fontWeight: inCheck ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (inCheck && room.status != RoomStatus.finished)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: G42Colors.bad.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'CHECK',
                style: TextStyle(
                  color: G42Colors.bad,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _boardGrid(ChessPosition pos, int checkedKing) {
    final highlightTargets = <int>{for (final m in _selectedMoves) m.to};

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: 64,
          itemBuilder: (context, displayIndex) {
            final boardIndex = _displayToBoard(displayIndex);
            final piece = pos.pieceAt(boardIndex);
            final file = ChessPosition.fileOf(boardIndex);
            final rank = ChessPosition.rankOf(boardIndex);
            final isLight = (file + rank) % 2 == 0;

            final isSelected = _selected == boardIndex;
            final isTarget = highlightTargets.contains(boardIndex);
            final isLast = boardIndex == _lastFrom || boardIndex == _lastTo;
            final isCheckedKing = boardIndex == checkedKing;

            Color base = isLight
                ? const Color(0xFFE9E2D0)
                : const Color(0xFF6B5B73);
            if (isLast) {
              base = Color.alphaBlend(
                G42Colors.warn.withValues(alpha: 0.30),
                base,
              );
            }
            if (isSelected) {
              base = Color.alphaBlend(
                G42Colors.accent.withValues(alpha: 0.55),
                base,
              );
            }
            if (isCheckedKing) {
              base = Color.alphaBlend(
                G42Colors.bad.withValues(alpha: 0.55),
                base,
              );
            }

            final cellSize = constraints.maxWidth / 8;

            return GestureDetector(
              onTap: () => _onTapCell(displayIndex),
              child: Container(
                color: base,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (piece != '.')
                      Text(
                        _glyph(piece),
                        style: TextStyle(
                          fontSize: cellSize * 0.72,
                          height: 1.0,
                          color: _isWhitePiece(piece)
                              ? Colors.white
                              : const Color(0xFF15151F),
                          shadows: const [
                            Shadow(
                              blurRadius: 2,
                              color: Colors.black38,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    if (isTarget)
                      Container(
                        width: piece == '.' ? cellSize * 0.30 : cellSize * 0.9,
                        height: piece == '.' ? cellSize * 0.30 : cellSize * 0.9,
                        decoration: BoxDecoration(
                          color: piece == '.'
                              ? G42Colors.good.withValues(alpha: 0.65)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: piece != '.'
                              ? Border.all(
                                  color: G42Colors.good.withValues(alpha: 0.9),
                                  width: 3,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _captured(ChessPosition pos) {
    // 사라진 말 계산: 시작 배치 대비 현재 보드.
    final start = ChessPosition.startBoard;
    final startCount = <String, int>{};
    final nowCount = <String, int>{};
    for (var i = 0; i < 64; i++) {
      final s = start[i];
      if (s != '.') startCount[s] = (startCount[s] ?? 0) + 1;
      final n = pos.board[i];
      if (n != '.') nowCount[n] = (nowCount[n] ?? 0) + 1;
    }
    // 잡힌 백 말(흑이 잡음), 잡힌 흑 말(백이 잡음).
    final capturedWhite = <String>[];
    final capturedBlack = <String>[];
    startCount.forEach((piece, cnt) {
      final missing = cnt - (nowCount[piece] ?? 0);
      for (var k = 0; k < missing; k++) {
        if (_isWhitePiece(piece)) {
          capturedWhite.add(piece);
        } else {
          capturedBlack.add(piece);
        }
      }
    });

    Widget row(String label, List<String> pieces, bool white) {
      return Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 1,
              children: pieces
                  .map(
                    (p) => Text(
                      _glyph(p),
                      style: TextStyle(
                        fontSize: 18,
                        color: white ? Colors.white70 : const Color(0xFF15151F),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          row('흑이 잡음', capturedWhite, true),
          const SizedBox(height: 4),
          row('백이 잡음', capturedBlack, false),
        ],
      ),
    );
  }

  Widget _resultOverlay() {
    final winner = room.winner;
    String title;
    String subtitle;
    Color color;
    if (winner == 'draw') {
      title = '무승부';
      subtitle = '스테일메이트';
      color = G42Colors.warn;
    } else {
      final winnerSeat = winner != null ? session.seatIndex(room, winner) : -1;
      final whiteWon = winnerSeat == 0;
      title = '체크메이트';
      final winnerName = winner != null
          ? (room.playerById(winner)?.name ?? (whiteWon ? '백' : '흑'))
          : '';
      subtitle = '$winnerName (${whiteWon ? '백' : '흑'}) 승리';
      color = G42Colors.good;
    }

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                winner == 'draw'
                    ? Icons.handshake_rounded
                    : Icons.emoji_events_rounded,
                size: 64,
                color: color,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _rematch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('재대국'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 헬퍼 ─────────────────────────────────────────────────

  static bool _isWhitePiece(String p) => p != '.' && p == p.toUpperCase();

  static String _glyph(String p) {
    switch (p) {
      case 'P':
      case 'p':
        return '♟'; // ♟ (양쪽 모두 색으로 구분)
      case 'N':
      case 'n':
        return '♞'; // ♞
      case 'B':
      case 'b':
        return '♝'; // ♝
      case 'R':
      case 'r':
        return '♜'; // ♜
      case 'Q':
      case 'q':
        return '♛'; // ♛
      case 'K':
      case 'k':
        return '♚'; // ♚
      default:
        return '';
    }
  }
}
