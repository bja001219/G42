import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'battleship_board.dart';
import 'battleship_logic.dart';

/// 배틀쉽 메인 인게임 위젯.
///
/// 동기화 상태는 [room.state]에서만 읽고, 배치 중 임시 상태(배치할 함선 인덱스,
/// 회전 방향, 핫시트 가림막)는 로컬 State에 둔다.
class BattleshipView extends StatefulWidget {
  final GameSession session;
  final Room room;

  /// 종료 후 재대국용 초기 상태 생성기.
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  const BattleshipView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
  });

  @override
  State<BattleshipView> createState() => _BattleshipViewState();
}

class _BattleshipViewState extends State<BattleshipView> {
  /// 다음에 배치할 함선 인덱스(0~3). 4 이상이면 배치 완료.
  int _nextShip = 0;

  /// 배치 방향(true=가로).
  bool _horizontal = true;

  /// 마우스 호버 미리보기용 인덱스(배치 단계, 데스크탑/웹).
  int? _hoverIndex;

  /// 핫시트: 정보 은닉 가림막을 띄울지.
  bool _curtain = false;

  /// 핫시트: 마지막으로 본 차례 주체(전환 감지용).
  String? _lastActor;

  /// 핫시트: 배치 단계에서 마지막으로 가림막을 보여준 플레이어.
  String? _curtainShownFor;

  /// 온라인: 호스트가 전투 전환을 이미 요청했는지(동시 준비 경쟁 상태 방지).
  bool _battleStartRequested = false;

  final Random _rng = Random();

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  String get _phase => (widget.room.state['phase'] as String?) ?? 'placing';

  Map<String, dynamic> get _boards =>
      Map<String, dynamic>.from(widget.room.state['boards'] as Map? ?? {});

  Map<String, dynamic> get _shots =>
      Map<String, dynamic>.from(widget.room.state['shots'] as Map? ?? {});

  Map<String, dynamic> get _ready =>
      Map<String, dynamic>.from(widget.room.state['ready'] as Map? ?? {});

  String _boardOf(String pid) =>
      (_boards[pid] as String?) ?? BattleshipLogic.emptyBoard();

  String _shotsOf(String pid) =>
      (_shots[pid] as String?) ?? BattleshipLogic.emptyShots();

  bool _readyOf(String pid) => (_ready[pid] as bool?) ?? false;

  String get _me => widget.session.actingPlayerId(widget.room);

  String? get _opponentId => widget.session.opponentOf(widget.room, _me)?.id;

  // ---- 빌드 -----------------------------------------------------------------

  @override
  void didUpdateWidget(covariant BattleshipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRaiseCurtainOnTurnChange();
    _maybeAutoStartBattleOnline();
  }

  /// 온라인에서 두 명이 거의 동시에 '준비'를 눌러 서로의 ready 업데이트를 받기 전이면,
  /// 어느 쪽도 everyoneReady를 못 보고 placing에 갇힐 수 있다.
  /// 그래서 호스트 클라이언트가 "둘 다 준비 && 아직 placing"을 감지하면 전투로 전환한다.
  void _maybeAutoStartBattleOnline() {
    if (widget.session.hotseat) return;
    if (_phase != 'placing') return;
    final ids = widget.room.playerIds;
    if (ids.isEmpty) return;
    final everyoneReady = ids.every((pid) => _readyOf(pid));
    if (!everyoneReady) return;
    if (widget.session.myPlayerId != ids.first) return; // 호스트만 권한
    if (_battleStartRequested) return;
    _battleStartRequested = true;
    final state = _freshState();
    state['phase'] = 'battle';
    widget.session.submit(state, nextTurn: ids.first);
  }

  @override
  void initState() {
    super.initState();
    _lastActor = _actorForCurtain();
  }

  /// 핫시트 배틀 단계에서 차례가 바뀌면 가림막을 올린다.
  String? _actorForCurtain() {
    if (!widget.session.hotseat) return null;
    return widget.room.turn;
  }

  void _maybeRaiseCurtainOnTurnChange() {
    if (!widget.session.hotseat) return;
    if (_phase != 'battle') return;
    final actor = widget.room.turn;
    if (actor != null && _lastActor != null && actor != _lastActor) {
      // 차례가 넘어갔다 → 가림막.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _curtain = true);
      });
    }
    _lastActor = actor;
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    // 종료 상태.
    if (room.status == RoomStatus.finished) {
      return _buildBattle(context, finished: true);
    }

    switch (_phase) {
      case 'placing':
        return _buildPlacing(context);
      case 'battle':
      default:
        return _buildBattle(context, finished: false);
    }
  }

  // ---- 배치 단계 ------------------------------------------------------------

  Widget _buildPlacing(BuildContext context) {
    final me = _me;
    final myBoard = _boardOf(me);
    final iAmReady = _readyOf(me);

    // 핫시트: 다른 플레이어가 방금 배치를 마쳤고 내가 아직이면 가림막.
    if (widget.session.hotseat &&
        !iAmReady &&
        _curtainShownFor != me &&
        _anyOtherReady(me)) {
      return _curtainScreen(
        context,
        title: '${_nameOf(me)} 차례',
        subtitle: '함대를 배치하세요. 상대에게 보이지 않게!',
        onReveal: () => setState(() {
          _curtainShownFor = me;
          // 다음 플레이어를 위해 배치 로컬 상태 초기화.
          _nextShip = 0;
          _horizontal = true;
          _hoverIndex = null;
        }),
      );
    }

    if (iAmReady) {
      return _waitingForOpponent(context);
    }

    final placingDone = _nextShip >= BattleshipLogic.shipSizes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 컴팩트 상태 헤더.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _compactPlacingHeader(placingDone),
        ),
        // 함선 팔레트 (가로 스크롤, 높이 고정).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: _shipPalette(),
        ),
        // 보드: 남은 공간을 꽉 채움.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: MouseRegion(
                  onExit: (_) => setState(() => _hoverIndex = null),
                  child: BattleshipGrid(
                    cellAt: (i) => _placingCellAt(myBoard, i),
                    onTap: placingDone ? null : (i) => _onPlaceTap(myBoard, i),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 방향/랜덤/지우기 버튼 행.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _horizontal = !_horizontal),
                  icon: Icon(
                    _horizontal
                        ? Icons.swap_horiz_rounded
                        : Icons.swap_vert_rounded,
                    size: 16,
                  ),
                  label: Text(_horizontal ? '가로' : '세로'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _onRandomize,
                  icon: const Icon(Icons.casino_rounded, size: 16),
                  label: const Text('랜덤'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _onClearPlacement,
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('지우기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 준비 완료 버튼.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: FilledButton.icon(
            onPressed: placingDone ? _onReady : null,
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('준비 완료'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactPlacingHeader(bool placingDone) {
    final color = G42Colors.accent;
    final sub = placingDone
        ? '배치 완료! 준비를 누르세요.'
        : '${BattleshipLogic.shipSizes[_nextShip]}칸 함선을 놓을 위치를 탭하세요.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.anchor_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sub,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _anyOtherReady(String me) {
    for (final pid in widget.room.playerIds) {
      if (pid != me && _readyOf(pid)) return true;
    }
    return false;
  }

  Widget _shipPalette() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var s = 0; s < BattleshipLogic.shipSizes.length; s++) _shipChip(s),
      ],
    );
  }

  Widget _shipChip(int s) {
    final len = BattleshipLogic.shipSizes[s];
    final placed = s < _nextShip;
    final active = s == _nextShip;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? G42Colors.accent.withValues(alpha: 0.25)
            : G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? G42Colors.accent
              : (placed ? G42Colors.good : G42Colors.surfaceHi),
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            placed ? Icons.check_rounded : Icons.directions_boat_rounded,
            size: 16,
            color: placed ? G42Colors.good : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(
            '$len칸',
            style: TextStyle(
              color: placed ? G42Colors.good : Colors.white,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  CellKind _placingCellAt(String board, int index) {
    // 미리보기.
    final hover = _hoverIndex;
    if (hover != null && _nextShip < BattleshipLogic.shipSizes.length) {
      final len = BattleshipLogic.shipSizes[_nextShip];
      final cells = BattleshipLogic.shipCells(
        BattleshipLogic.rowOf(hover),
        BattleshipLogic.colOf(hover),
        len,
        _horizontal,
      );
      if (cells != null && cells.contains(index)) {
        final ok = BattleshipLogic.isFree(board, cells);
        return ok ? CellKind.previewValid : CellKind.previewInvalid;
      }
    }
    return board[index] != '.' ? CellKind.ship : CellKind.water;
  }

  void _onPlaceTap(String board, int index) {
    setState(() => _hoverIndex = index);
    final len = BattleshipLogic.shipSizes[_nextShip];
    final cells = BattleshipLogic.shipCells(
      BattleshipLogic.rowOf(index),
      BattleshipLogic.colOf(index),
      len,
      _horizontal,
    );
    if (cells == null) {
      _toast('범위를 벗어났습니다');
      return;
    }
    if (!BattleshipLogic.isFree(board, cells)) {
      _toast('다른 함선과 겹칩니다');
      return;
    }
    final newBoard = BattleshipLogic.place(board, cells, _nextShip);
    _submitBoard(newBoard);
    setState(() {
      _nextShip++;
      _hoverIndex = null;
    });
  }

  void _onRandomize() {
    final board = BattleshipLogic.randomBoard(_rng);
    _submitBoard(board);
    setState(() {
      _nextShip = BattleshipLogic.shipSizes.length;
      _hoverIndex = null;
    });
  }

  void _onClearPlacement() {
    _submitBoard(BattleshipLogic.emptyBoard());
    setState(() {
      _nextShip = 0;
      _hoverIndex = null;
    });
  }

  /// 내 보드만 바꿔 최신 state로 통째로 submit (동시 쓰기 충돌 최소화).
  void _submitBoard(String board) {
    final state = _freshState();
    final boards = Map<String, dynamic>.from(state['boards'] as Map);
    boards[_me] = board;
    state['boards'] = boards;
    widget.session.submit(state);
  }

  void _onReady() {
    final me = _me;
    final board = _boardOf(me);
    if (!BattleshipLogic.isComplete(board)) {
      _toast('함대 배치가 완료되지 않았습니다');
      return;
    }

    final state = _freshState();
    final ready = Map<String, dynamic>.from(state['ready'] as Map);
    ready[me] = true;
    state['ready'] = ready;

    // 두 명 모두 준비되면 전투 단계로 전환.
    final everyoneReady =
        widget.room.playerIds.isNotEmpty &&
        widget.room.playerIds.every((pid) => (ready[pid] as bool?) ?? false);

    if (everyoneReady) {
      state['phase'] = 'battle';
      final host = widget.room.playerIds.first;
      widget.session.submit(state, nextTurn: host);
      if (widget.session.hotseat) {
        setState(() {
          _curtain = true;
          _lastActor = host;
        });
      }
    } else {
      if (widget.session.hotseat) {
        // 핫시트: 아직 준비 안 된 다음 플레이어로 차례를 넘겨
        // actingPlayerId가 그 사람을 가리키게 한다(그래야 그 사람이 배치 가능).
        final next = widget.room.playerIds.firstWhere(
          (pid) => !((ready[pid] as bool?) ?? false),
          orElse: () => widget.room.playerIds.first,
        );
        widget.session.submit(state, nextTurn: next);
        // 다음 플레이어용 가림막이 다시 뜨도록 표시 기록 초기화.
        setState(() => _curtainShownFor = null);
      } else {
        widget.session.submit(state);
      }
    }
  }

  Widget _waitingForOpponent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            size: 56,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text('준비 완료!', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            '상대의 배치를 기다리는 중...',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  // ---- 전투 단계 ------------------------------------------------------------

  Widget _buildBattle(BuildContext context, {required bool finished}) {
    final me = _me;
    final opp = _opponentId;
    final myBoard = _boardOf(me);
    final myShots = _shotsOf(me); // 상대 보드에 쏜 것
    final oppShots = opp != null ? _shotsOf(opp) : BattleshipLogic.emptyShots();
    final oppBoard = opp != null ? _boardOf(opp) : BattleshipLogic.emptyBoard();

    // 핫시트 가림막.
    if (!finished && _curtain && widget.session.hotseat) {
      return _curtainScreen(
        context,
        title: '${_nameOf(me)} 차례',
        subtitle: '화면을 받은 뒤 시작하세요.',
        onReveal: () => setState(() => _curtain = false),
      );
    }

    final myTurn = widget.session.isMyTurn(widget.room) && !finished;
    final myRemaining = opp != null
        ? BattleshipLogic.remainingShips(myShots, oppBoard)
        : 0;
    final oppRemaining = BattleshipLogic.remainingShips(oppShots, myBoard);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 차례 배너: 컴팩트 고정 높이.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _turnBanner(myTurn, finished),
        ),
        // 상대 해역 레이블.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: _sectionLabel(
            '상대 해역  (남은 함선 $myRemaining/${BattleshipLogic.shipSizes.length})',
            G42Colors.bad,
          ),
        ),
        // 상대 해역 보드: 절반 높이 flex.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: BattleshipGrid(
                  cellAt: (i) => _enemyCellAt(myShots, i),
                  sunkCells: _sunkCellsOnEnemy(myShots, oppBoard),
                  onTap: (myTurn && opp != null)
                      ? (i) => _onFire(i, oppBoard, myShots)
                      : null,
                ),
              ),
            ),
          ),
        ),
        // 내 함대 레이블.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: _sectionLabel(
            '내 함대  (남은 함선 $oppRemaining/${BattleshipLogic.shipSizes.length})',
            G42Colors.good,
          ),
        ),
        // 내 함대 보드: 절반 높이 flex.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: BattleshipGrid(
                  cellAt: (i) => _myFleetCellAt(myBoard, oppShots, i),
                  sunkCells: _sunkCellsOnMine(oppShots, myBoard),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (!finished) return content;

    return Stack(children: [content, _resultOverlay(context)]);
  }

  CellKind _enemyCellAt(String myShots, int index) {
    switch (myShots[index]) {
      case 'X':
        return CellKind.hit;
      case 'O':
        return CellKind.miss;
      default:
        return CellKind.water;
    }
  }

  CellKind _myFleetCellAt(String myBoard, String oppShots, int index) {
    final shot = oppShots[index];
    final isShip = myBoard[index] != '.';
    if (shot == 'X') return CellKind.hit;
    if (shot == 'O') return CellKind.miss;
    return isShip ? CellKind.ship : CellKind.water;
  }

  Set<int> _sunkCellsOnEnemy(String myShots, String oppBoard) {
    final result = <int>{};
    for (var s = 0; s < BattleshipLogic.shipSizes.length; s++) {
      if (BattleshipLogic.isShipSunk(myShots, oppBoard, s)) {
        final mark = s.toString();
        for (var i = 0; i < oppBoard.length; i++) {
          if (oppBoard[i] == mark) result.add(i);
        }
      }
    }
    return result;
  }

  Set<int> _sunkCellsOnMine(String oppShots, String myBoard) {
    final result = <int>{};
    for (var s = 0; s < BattleshipLogic.shipSizes.length; s++) {
      if (BattleshipLogic.isShipSunk(oppShots, myBoard, s)) {
        final mark = s.toString();
        for (var i = 0; i < myBoard.length; i++) {
          if (myBoard[i] == mark) result.add(i);
        }
      }
    }
    return result;
  }

  void _onFire(int index, String oppBoard, String myShots) {
    if (!widget.session.isMyTurn(widget.room)) return;
    if (myShots[index] != '.') {
      _toast('이미 사격한 칸입니다');
      return;
    }

    final me = _me;
    final opp = _opponentId;
    if (opp == null) return;

    final newShots = BattleshipLogic.fire(myShots, oppBoard, index);

    final state = _freshState();
    final shots = Map<String, dynamic>.from(state['shots'] as Map);
    shots[me] = newShots;
    state['shots'] = shots;

    final hit = oppBoard[index] != '.';
    final won = BattleshipLogic.allSunk(newShots, oppBoard);
    final sunkShip = BattleshipLogic.sunkShipAt(newShots, oppBoard, index);

    if (won) {
      state['phase'] = 'finished';
      widget.session.submit(state, status: RoomStatus.finished, winner: me);
    } else {
      // 클래식 규칙: 명중이어도 턴은 상대에게.
      widget.session.submit(state, nextTurn: opp);
    }

    if (sunkShip != null && !won) {
      _toast('${BattleshipLogic.shipSizes[sunkShip]}칸 함선 격침!');
    } else if (hit && !won) {
      _toast('명중!');
    }
  }

  // ---- 헤더 / 배너 ----------------------------------------------------------

  Widget _turnBanner(bool myTurn, bool finished) {
    if (finished) {
      return const SizedBox.shrink();
    }
    final me = _me;
    final seat = widget.session.seatIndex(widget.room, me);
    final color = seat == 0 ? G42Colors.accent : G42Colors.warn;
    final name = _nameOf(me);

    final label = widget.session.hotseat
        ? '$name 차례 — 사격하세요'
        : (myTurn ? '내 차례 — 사격하세요' : '상대 차례 — 대기 중');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (myTurn ? color : G42Colors.surface).withValues(
          alpha: myTurn ? 0.22 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: myTurn ? color : G42Colors.surfaceHi,
          width: myTurn ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            myTurn ? Icons.gps_fixed_rounded : Icons.hourglass_empty_rounded,
            color: myTurn ? color : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: myTurn ? Colors.white : Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // ---- 가림막 / 오버레이 ----------------------------------------------------

  Widget _curtainScreen(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onReveal,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_off_rounded,
              size: 72,
              color: Colors.white54,
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('화면 확인 (기기를 넘겨받았어요)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultOverlay(BuildContext context) {
    final winner = widget.room.winner;
    final me = _me;
    final iWon = winner == me;
    final isDraw = winner == 'draw';

    final String title;
    final Color color;
    final IconData icon;
    if (isDraw) {
      title = '무승부';
      color = G42Colors.warn;
      icon = Icons.handshake_rounded;
    } else if (widget.session.hotseat) {
      title = '${_nameOf(winner ?? '')} 승리!';
      color = G42Colors.good;
      icon = Icons.military_tech_rounded;
    } else if (iWon) {
      title = '승리!';
      color = G42Colors.good;
      icon = Icons.military_tech_rounded;
    } else {
      title = '패배';
      color = G42Colors.bad;
      icon = Icons.sentiment_dissatisfied_rounded;
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: G42Colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: color),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _onRematch,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('재대국'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onRematch() {
    setState(() {
      _nextShip = 0;
      _horizontal = true;
      _hoverIndex = null;
      _curtain = false;
      _curtainShownFor = null;
      _lastActor = null;
      _battleStartRequested = false;
    });
    widget.session.rematch(
      widget.createInitialState(widget.room.playerIds),
      widget.firstTurn(widget.room.playerIds),
    );
  }

  // ---- 잡다한 헬퍼 ----------------------------------------------------------

  /// 최신 room.state 복제(내 키만 바꿔 통째로 submit하기 위한 베이스).
  Map<String, dynamic> _freshState() {
    final s = widget.room.state;
    return {
      'phase': (s['phase'] as String?) ?? 'placing',
      'boards': Map<String, dynamic>.from(s['boards'] as Map? ?? {}),
      'shots': Map<String, dynamic>.from(s['shots'] as Map? ?? {}),
      'ready': Map<String, dynamic>.from(s['ready'] as Map? ?? {}),
    };
  }

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
