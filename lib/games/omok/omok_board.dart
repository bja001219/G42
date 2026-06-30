import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'omok_logic.dart';

/// 오목 인게임 보드 위젯.
class OmokBoard extends StatefulWidget {
  final GameSession session;
  final Room room;

  /// 재대국 시 호출(새 초기 상태 생성을 위임).
  final Future<void> Function() onRematch;

  const OmokBoard({
    super.key,
    required this.session,
    required this.room,
    required this.onRematch,
  });

  @override
  State<OmokBoard> createState() => _OmokBoardState();
}

class _OmokBoardState extends State<OmokBoard> {
  bool _submitting = false;

  /// 승부가 결정된 직후 결과 박스를 바로 띄우지 않고, 먼저 승착이 놓인 보드와
  /// 승리선을 잠깐 보여준 뒤 true 가 된다(상대가 "어떻게 졌는지" 볼 수 있도록).
  bool _resultRevealed = false;

  /// 승리를 만든 5목 칸들(강조 표시용). 승리가 아니거나 미계산이면 null.
  List<int>? _winLine;

  Timer? _revealTimer;

  /// 승착을 보여준 뒤 결과 박스가 나타나기까지의 지연.
  static const _winRevealDelay = Duration(milliseconds: 1400);

  GameSession get _session => widget.session;
  Room get _room => widget.room;

  String get _board {
    final b = _room.state['board'];
    return (b is String && b.length == kOmokCells) ? b : emptyOmokBoard();
  }

  int get _lastMove {
    final v = _room.state['lastMove'];
    return v is int ? v : -1;
  }

  @override
  void initState() {
    super.initState();
    // 이미 끝난 방으로 입장(중도 합류) 시에는 연출 없이 즉시 결과 표시.
    if (_room.status == RoomStatus.finished) {
      _resultRevealed = true;
      _winLine = _computeWinLine();
    }
  }

  @override
  void didUpdateWidget(covariant OmokBoard old) {
    super.didUpdateWidget(old);
    final was = old.room.status == RoomStatus.finished;
    final now = _room.status == RoomStatus.finished;
    if (!was && now) {
      // 방금 대국이 끝났다 — 양쪽 클라이언트가 같은 finished 스냅샷을 받으므로
      // 로컬 타이머 지연도 양쪽에서 동일하게 동작한다.
      _winLine = _computeWinLine();
      final isWinFinish = _room.winner != null &&
          _room.winner != 'draw' &&
          (_winLine?.isNotEmpty ?? false);
      if (isWinFinish) {
        _resultRevealed = false; // 먼저 승착이 놓인 보드를 보여준다.
        _revealTimer?.cancel();
        _revealTimer = Timer(_winRevealDelay, () {
          if (mounted) setState(() => _resultRevealed = true);
        });
      } else {
        _resultRevealed = true; // 무승부 등은 즉시.
      }
    } else if (was && !now) {
      // 재대국으로 리셋.
      _revealTimer?.cancel();
      _resultRevealed = false;
      _winLine = null;
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  /// 마지막 착수를 기준으로 승리선을 계산한다(없으면 null).
  List<int>? _computeWinLine() {
    final lm = _lastMove;
    if (lm < 0 || lm >= kOmokCells) return null;
    final board = _board;
    final stone = board[lm];
    if (stone == '.') return null;
    final line = winningLine(board, lm, stone);
    return line.isEmpty ? null : line;
  }

  Future<void> _onTapCell(int index) async {
    if (_submitting) return;
    if (_room.status == RoomStatus.finished) return;
    if (!_session.isMyTurn(_room)) return;

    final board = _board;
    if (!isEmptyCell(board, index)) return;

    final me = _session.actingPlayerId(_room);
    final seat = _session.seatIndex(_room, me);
    if (seat < 0) return;
    final stone = stoneForSeat(seat);

    final newBoard = placeStone(board, index, stone);
    final state = <String, dynamic>{'board': newBoard, 'lastMove': index};

    setState(() => _submitting = true);
    try {
      if (isWin(newBoard, index, stone)) {
        await _session.submit(state, status: RoomStatus.finished, winner: me);
      } else if (isBoardFull(newBoard)) {
        await _session.submit(
          state,
          status: RoomStatus.finished,
          winner: 'draw',
        );
      } else {
        final opponent = _session.opponentOf(_room, me);
        await _session.submit(state, nextTurn: opponent?.id);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusBar(session: _session, room: _room),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapDown: (details) {
                        final size = constraints.biggest.shortestSide;
                        final cell = size / kOmokSize;
                        final col = (details.localPosition.dx / cell)
                            .floor()
                            .clamp(0, kOmokSize - 1);
                        final row = (details.localPosition.dy / cell)
                            .floor()
                            .clamp(0, kOmokSize - 1);
                        _onTapCell(omokIndex(row, col));
                      },
                      child: CustomPaint(
                        size: Size.square(constraints.biggest.shortestSide),
                        painter: _OmokPainter(
                          board: _board,
                          lastMove: _lastMove,
                          winLine: _winLine,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (_room.status == RoomStatus.finished && _resultRevealed)
          _ResultOverlay(
            session: _session,
            room: _room,
            onRematch: widget.onRematch,
          ),
      ],
    );
  }
}

/// 차례 / 안내 표시줄.
class _StatusBar extends StatelessWidget {
  final GameSession session;
  final Room room;

  const _StatusBar({required this.session, required this.room});

  @override
  Widget build(BuildContext context) {
    final turnId = room.turn;
    final isBlackTurn = turnId != null && session.seatIndex(room, turnId) == 0;
    final turnPlayer = turnId == null ? null : room.playerById(turnId);
    final myTurn = session.isMyTurn(room) && room.status != RoomStatus.finished;

    final stoneColor = isBlackTurn ? Colors.black : Colors.white;
    final stoneBorder = isBlackTurn ? Colors.white24 : Colors.black26;
    final label = isBlackTurn ? '흑' : '백';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: myTurn ? G42Colors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: stoneColor,
              shape: BoxShape.circle,
              border: Border.all(color: stoneBorder, width: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              room.status == RoomStatus.finished
                  ? '대국 종료'
                  : '$label 차례'
                        '${turnPlayer != null ? ' · ${turnPlayer.name}' : ''}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          if (myTurn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: G42Colors.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '내 차례',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: G42Colors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 결과(승/무) 오버레이 + 재대국.
class _ResultOverlay extends StatelessWidget {
  final GameSession session;
  final Room room;
  final Future<void> Function() onRematch;

  const _ResultOverlay({
    required this.session,
    required this.room,
    required this.onRematch,
  });

  @override
  Widget build(BuildContext context) {
    final winner = room.winner;
    final isDraw = winner == 'draw';

    String text;
    Color color;
    IconData icon;

    if (isDraw) {
      text = '무승부';
      color = G42Colors.warn;
      icon = Icons.handshake_rounded;
    } else {
      final winSeat = winner == null ? -1 : session.seatIndex(room, winner);
      final stoneLabel = winSeat == 0 ? '흑' : '백';
      final winPlayer = winner == null ? null : room.playerById(winner);
      text = '$stoneLabel 승리${winPlayer != null ? ' · ${winPlayer.name}' : ''}';
      color = G42Colors.good;
      icon = Icons.emoji_events_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: G42Colors.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onRematch,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('재대국'),
          ),
        ],
      ),
    );
  }
}

/// 바둑판(우드톤 격자 + 화점) + 돌 + 마지막 착수 마커.
class _OmokPainter extends CustomPainter {
  final String board;
  final int lastMove;

  /// 승리선 칸들(있으면 금색 링으로 강조). 진행 중이면 null.
  final List<int>? winLine;

  _OmokPainter({required this.board, required this.lastMove, this.winLine});

  static const _wood = Color(0xFFD9A86B);
  static const _woodDark = Color(0xFFB5824A);
  static const _line = Color(0xFF6B4A28);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final cell = side / kOmokSize;
    // 격자선은 각 셀의 중앙을 지난다.
    final origin = cell / 2;

    // 보드 배경(우드톤).
    final bgRect = Rect.fromLTWH(0, 0, side, side);
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_wood, _woodDark],
      ).createShader(bgRect);
    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(8));
    canvas.drawRRect(rrect, bgPaint);

    // 격자선.
    final linePaint = Paint()
      ..color = _line
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < kOmokSize; i++) {
      final p = origin + i * cell;
      canvas.drawLine(
        Offset(origin, p),
        Offset(origin + (kOmokSize - 1) * cell, p),
        linePaint,
      );
      canvas.drawLine(
        Offset(p, origin),
        Offset(p, origin + (kOmokSize - 1) * cell),
        linePaint,
      );
    }

    // 화점(3, 7, 11).
    const starPoints = [3, 7, 11];
    final starPaint = Paint()
      ..color = _line
      ..style = PaintingStyle.fill;
    for (final r in starPoints) {
      for (final c in starPoints) {
        canvas.drawCircle(
          Offset(origin + c * cell, origin + r * cell),
          cell * 0.08,
          starPaint,
        );
      }
    }

    // 돌.
    final stoneR = cell * 0.42;
    for (var idx = 0; idx < kOmokCells; idx++) {
      final ch = board[idx];
      if (ch == '.') continue;
      final r = omokRow(idx);
      final c = omokCol(idx);
      final center = Offset(origin + c * cell, origin + r * cell);
      final isBlack = ch == 'B';

      // 그림자.
      canvas.drawCircle(
        center.translate(0, stoneR * 0.12),
        stoneR,
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );

      final stonePaint = Paint()
        ..shader = RadialGradient(
          colors: isBlack
              ? const [Color(0xFF555555), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFCFCFCF)],
          center: const Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: center, radius: stoneR));
      canvas.drawCircle(center, stoneR, stonePaint);

      // 마지막 착수 강조 마커.
      if (idx == lastMove) {
        final markPaint = Paint()
          ..color = isBlack ? Colors.white : Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(center, stoneR * 0.4, markPaint);
      }
    }

    // 승리선 강조: 5목을 이룬 칸들에 금색 링을 덧그린다.
    final wl = winLine;
    if (wl != null && wl.isNotEmpty) {
      final ringPaint = Paint()
        ..color = G42Colors.warn
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      for (final idx in wl) {
        if (idx < 0 || idx >= kOmokCells) continue;
        final center = Offset(
          origin + omokCol(idx) * cell,
          origin + omokRow(idx) * cell,
        );
        canvas.drawCircle(center, stoneR + 2.5, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OmokPainter old) =>
      old.board != board ||
      old.lastMove != lastMove ||
      !_sameLine(old.winLine, winLine);

  static bool _sameLine(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
