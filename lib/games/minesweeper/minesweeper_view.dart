import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'minesweeper_logic.dart';

/// 지뢰찾기 인게임 위젯(협동 · 같은 보드 공유).
///
/// 두 플레이어가 [Room.state]에 담긴 하나의 지뢰밭을 실시간으로 함께 푼다. 칸 탭은
/// 열기(또는 깃발 모드면 깃발 토글), 꾹 누르면 깃발 토글. 결과(클리어/지뢰)는 경쟁
/// 게임과 달리 status를 finished로 바꾸지 않고 이 위젯이 자체 오버레이로 보여준다
/// — 협동이라 승패·전적 기록 흐름을 타지 않는다.
class MinesweeperView extends StatefulWidget {
  final GameSession session;
  final Room room;

  const MinesweeperView({super.key, required this.session, required this.room});

  @override
  State<MinesweeperView> createState() => _MinesweeperViewState();
}

class _MinesweeperViewState extends State<MinesweeperView> {
  /// 깃발 모드(로컬 토글 — 동기화하지 않는다. 꽂힌 깃발 자체는 보드 상태로 공유).
  bool _flagMode = false;

  final Random _rng = Random();

  GameSession get session => widget.session;
  Map<String, dynamic> get _state => widget.room.state;

  void _onCellTap(int i) {
    final state = _state;
    if (MinesweeperState.phaseOf(state) != 'playing') return;
    final next = _flagMode
        ? MinesweeperState.applyFlag(state, i)
        : MinesweeperState.applyReveal(state, i, _rng);
    if (!identical(next, state)) {
      session.submit(next);
    }
  }

  void _onCellLongPress(int i) {
    final state = _state;
    if (MinesweeperState.phaseOf(state) != 'playing') return;
    final next = MinesweeperState.applyFlag(state, i);
    if (!identical(next, state)) {
      session.submit(next);
    }
  }

  void _restart() {
    final state = _state;
    final rows = MinesweeperState.rowsOf(state);
    final cols = MinesweeperState.colsOf(state);
    final mines = MinesweeperState.mineCountOf(state);
    final config = (state['config'] as Map?) != null
        ? Map<String, dynamic>.from(state['config'] as Map)
        : null;
    session.submit(
      MinesweeperState.fresh(
        rows: rows,
        cols: cols,
        mines: mines,
        config: config,
      ),
    );
  }

  void _backToPicker() {
    session.patch(<String, dynamic>{
      'status': RoomStatus.waiting.name,
      'gameId': '',
      'turn': null,
      'winner': null,
      'state': <String, dynamic>{},
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final rows = MinesweeperState.rowsOf(state);
    final cols = MinesweeperState.colsOf(state);
    if (rows <= 0 || cols <= 0) {
      return const Center(child: CircularProgressIndicator());
    }

    final revealed = MinesweeperState.revealedOf(state);
    final flags = MinesweeperState.flagsOf(state);
    final mineSet = MinesweeperState.minesOf(state).toSet();
    final phase = MinesweeperState.phaseOf(state);
    final hit = MinesweeperState.hitOf(state);
    final mineCount = MinesweeperState.mineCountOf(state);
    final flagCount = flags.where((v) => v == 1).length;
    final logic = MinesweeperLogic(rows: rows, cols: cols);

    return Stack(
      children: [
        Column(
          children: [
            _statusBar(remaining: mineCount - flagCount),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cell = _cellSize(constraints, rows, cols);
                    return Center(
                      child: SizedBox(
                        width: cell * cols,
                        height: cell * rows,
                        child: _board(
                          rows: rows,
                          cols: cols,
                          cell: cell,
                          revealed: revealed,
                          flags: flags,
                          mineSet: mineSet,
                          phase: phase,
                          hit: hit,
                          logic: logic,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _flagToggleBar(),
          ],
        ),
        if (phase != 'playing')
          _resultOverlay(won: phase == 'won', mineCount: mineCount),
      ],
    );
  }

  double _cellSize(BoxConstraints c, int rows, int cols) {
    final w = c.maxWidth / cols;
    final h = c.maxHeight / rows;
    final s = w < h ? w : h;
    return s.clamp(14.0, 48.0);
  }

  // ---- 상단 상태바: 남은 지뢰 수 + 협동 안내 ----------------------------------
  Widget _statusBar({required int remaining}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _chip(
            icon: '🚩',
            label: '$remaining',
            color: G42Colors.bad,
          ),
          const Spacer(),
          const Text(
            '둘이 함께!',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 보드 ------------------------------------------------------------------
  Widget _board({
    required int rows,
    required int cols,
    required double cell,
    required List<int> revealed,
    required List<int> flags,
    required Set<int> mineSet,
    required String phase,
    required int hit,
    required MinesweeperLogic logic,
  }) {
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < cols; c++)
                _cell(
                  i: logic.index(r, c),
                  size: cell,
                  revealed: revealed,
                  flags: flags,
                  mineSet: mineSet,
                  phase: phase,
                  hit: hit,
                  logic: logic,
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell({
    required int i,
    required double size,
    required List<int> revealed,
    required List<int> flags,
    required Set<int> mineSet,
    required String phase,
    required int hit,
    required MinesweeperLogic logic,
  }) {
    final isRevealed = revealed[i] == 1;
    final isFlag = flags[i] == 1;
    final isMine = mineSet.contains(i);
    final lost = phase == 'lost';

    Color bg;
    Widget? child;
    final textSize = size * 0.5;

    if (lost && isMine) {
      // 패배 시 모든 지뢰 공개. 밟은 칸은 더 진한 빨강.
      bg = i == hit
          ? G42Colors.bad
          : G42Colors.bad.withValues(alpha: 0.45);
      child = Text('💣', style: TextStyle(fontSize: textSize));
    } else if (lost && isFlag && !isMine) {
      // 빗나간 깃발 표시.
      bg = G42Colors.surfaceHi;
      child = Text('❌', style: TextStyle(fontSize: textSize * 0.9));
    } else if (isRevealed) {
      bg = G42Colors.bg;
      final n = logic.adjacentMines(i, mineSet);
      if (n > 0) {
        child = Text(
          '$n',
          style: TextStyle(
            fontSize: textSize,
            fontWeight: FontWeight.w900,
            color: _numberColor(n),
            height: 1.0,
          ),
        );
      }
    } else {
      // 가려진 칸.
      bg = G42Colors.surfaceHi;
      if (isFlag) child = Text('🚩', style: TextStyle(fontSize: textSize));
    }

    return GestureDetector(
      onTap: () => _onCellTap(i),
      onLongPress: () => _onCellLongPress(i),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 0.5),
          borderRadius: BorderRadius.circular(size * 0.12),
        ),
        child: child,
      ),
    );
  }

  /// 클래식 지뢰찾기 숫자 색(다크 배경에서 잘 보이도록 조정).
  Color _numberColor(int n) {
    const colors = <Color>[
      Color(0xFF64B5F6), // 1 파랑
      Color(0xFF66BB6A), // 2 초록
      Color(0xFFFF8A80), // 3 빨강
      Color(0xFFB388FF), // 4 보라
      Color(0xFFFFB74D), // 5 주황
      Color(0xFF4DD0E1), // 6 청록
      Color(0xFFE0E0E0), // 7 흰
      Color(0xFF9E9E9E), // 8 회색
    ];
    return colors[(n - 1).clamp(0, colors.length - 1)];
  }

  // ---- 하단 깃발 모드 토글 ----------------------------------------------------
  Widget _flagToggleBar() {
    final on = _flagMode;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => setState(() => _flagMode = !_flagMode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on
                        ? G42Colors.accent
                        : G42Colors.surfaceHi,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: on ? G42Colors.accent : Colors.white12,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🚩', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        on ? '깃발 모드 · 켜짐' : '깃발 모드 · 꺼짐',
                        style: TextStyle(
                          color: on ? Colors.white : Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              on ? '칸을 누르면 깃발을 꽂거나 뺍니다.' : '칸을 누르면 엽니다. (꾹 누르면 깃발)',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 결과 오버레이(협동: status는 playing 유지, 자체 표시) ------------------
  Widget _resultOverlay({required bool won, required int mineCount}) {
    final color = won ? G42Colors.good : G42Colors.bad;
    final icon = won ? '🎉' : '💥';
    final headline = won ? '클리어!' : '지뢰를 밟았어요';
    final subtitle = won ? '둘이서 지뢰 $mineCount개를 모두 피했어요.' : '아쉽지만 한 판 더 도전해요.';

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 60)),
                const SizedBox(height: 12),
                Text(
                  headline,
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('다시하기'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _backToPicker,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('게임 선택으로'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
