import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'boggle_logic.dart';
import 'boggle_rules.dart';

/// 보글 메인 인게임 위젯.
///
/// 동기화 상태(`grid`/`found`/`scores`/`done`/`phase`/`hsTurn`)는 [room.state]에서만
/// 읽고, 현재 선택 중인 경로/타이머 등 로컬 임시 상태는 State에 둔다.
///
/// - 온라인: 같은 판을 둘이 동시에 풀고 각자 로컬 90초 타이머. 둘 다 끝나면 점수 비교.
///   (레이턴시 공정: 타이머는 각자 로컬에서 잰다.)
/// - 핫시트: 한 명씩 순차로 90초 플레이 + 가림막으로 정보 은닉. 둘 다 끝나면 비교.
class BoggleView extends StatefulWidget {
  final GameSession session;
  final Room room;
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  /// 언어/규칙(영어 또는 한글). 글자판 표기/사전/점수/제한시간이 여기서 갈린다.
  final BoggleRules rules;

  const BoggleView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
    required this.rules,
  });

  @override
  State<BoggleView> createState() => _BoggleViewState();
}

class _BoggleViewState extends State<BoggleView> {
  /// 현재 선택 중인 경로(평탄화 인덱스 목록).
  final List<int> _path = <int>[];

  /// 로컬 카운트다운(초). null이면 아직 시작 안 함/종료됨.
  int? _secondsLeft;
  Timer? _timer;

  /// 이 라운드에서 내(또는 현재 핫시트 차례 플레이어) 타이머가 시작된 적 있는가.
  bool _started = false;

  /// 핫시트: 다음 플레이어로 넘어갈 때 가림막을 보여줄지.
  bool _curtain = false;

  /// 핫시트: 마지막으로 본 차례(전환 감지).
  String? _lastHsTurn;

  /// 내가 'done' 제출을 이미 처리했는지(중복 제출 방지).
  bool _submittedDone = false;

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  String get _grid => (widget.room.state['grid'] as String?) ?? '';

  Map<String, dynamic> get _found =>
      Map<String, dynamic>.from(widget.room.state['found'] as Map? ?? {});

  Map<String, dynamic> get _scores =>
      Map<String, dynamic>.from(widget.room.state['scores'] as Map? ?? {});

  Map<String, dynamic> get _done =>
      Map<String, dynamic>.from(widget.room.state['done'] as Map? ?? {});

  String get _hsTurn => (widget.room.state['hsTurn'] as String?) ?? '';

  List<String> _foundOf(String pid) =>
      List<String>.from((_found[pid] as List?) ?? const []);

  int _scoreOf(String pid) => (_scores[pid] as num?)?.toInt() ?? 0;

  bool _doneOf(String pid) => (_done[pid] as bool?) ?? false;

  /// 현재 이 화면에서 '플레이하는' 플레이어.
  /// - 온라인: 항상 나.
  /// - 핫시트: hsTurn(현재 차례).
  String get _me {
    if (!widget.session.hotseat) return widget.session.myPlayerId;
    if (_hsTurn.isNotEmpty) return _hsTurn;
    return widget.session.actingPlayerId(widget.room);
  }

  String? get _opponentId => widget.session.opponentOf(widget.room, _me)?.id;

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  // ---- 라이프사이클 ---------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _lastHsTurn = _hsTurn;
    _maybeBeginRound();
  }

  @override
  void didUpdateWidget(covariant BoggleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHandleHotseatTurnChange();
    _maybeBeginRound();
  }

  /// 핫시트에서 차례(hsTurn)가 바뀌면 가림막을 올리고 로컬 상태를 리셋한다.
  void _maybeHandleHotseatTurnChange() {
    if (!widget.session.hotseat) return;
    final cur = _hsTurn;
    if (cur != _lastHsTurn) {
      _lastHsTurn = cur;
      _stopTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _curtain = !_doneOf(cur); // 아직 안 끝낸 사람에게만 가림막
          _path.clear();
          _started = false;
          _submittedDone = false;
          _secondsLeft = null;
        });
      });
    }
  }

  /// 라운드 시작 조건이 되면 로컬 타이머를 켠다.
  void _maybeBeginRound() {
    if (widget.room.status == RoomStatus.finished) return;
    if (_started) return;
    if (_curtain) return;

    final me = _me;
    if (_doneOf(me)) return; // 이미 끝낸 사람은 시작 안 함

    // 핫시트: 내 차례일 때만 시작.
    if (widget.session.hotseat && _hsTurn.isNotEmpty && _hsTurn != me) return;

    _started = true;
    _secondsLeft = widget.rules.durationSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = (_secondsLeft ?? 0) - 1;
      if (left <= 0) {
        _stopTimer();
        setState(() => _secondsLeft = 0);
        _onTimeUp();
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  // ---- 라운드 종료 처리 -----------------------------------------------------

  /// 시간이 다 됐거나 사용자가 '끝내기'를 눌렀을 때.
  void _onTimeUp() {
    if (_submittedDone) return;
    _submittedDone = true;
    _stopTimer();

    final me = _me;
    final state = _freshState();
    final done = Map<String, dynamic>.from(state['done'] as Map);
    done[me] = true;
    state['done'] = done;

    final ids = widget.room.playerIds;
    final everyoneDone =
        ids.isNotEmpty && ids.every((p) => _resolvedDone(done, p));

    if (everyoneDone) {
      _finishGame(state);
      return;
    }

    if (widget.session.hotseat) {
      // 다음(아직 안 끝낸) 플레이어에게 차례를 넘긴다.
      final next = ids.firstWhere(
        (p) => !_resolvedDone(done, p),
        orElse: () => me,
      );
      state['hsTurn'] = next;
      widget.session.submit(state, nextTurn: next);
    } else {
      // 온라인: 내 done만 반영하고 상대 타이머 종료를 기다린다.
      widget.session.submit(state);
    }
  }

  bool _resolvedDone(Map<String, dynamic> done, String pid) =>
      (done[pid] as bool?) ?? false;

  void _finishGame(Map<String, dynamic> state) {
    final ids = widget.room.playerIds;
    final scores = Map<String, dynamic>.from(state['scores'] as Map);
    String winner = 'draw';
    if (ids.length == 2) {
      final a = (scores[ids[0]] as num?)?.toInt() ?? 0;
      final b = (scores[ids[1]] as num?)?.toInt() ?? 0;
      if (a > b) {
        winner = ids[0];
      } else if (b > a) {
        winner = ids[1];
      } else {
        winner = 'draw';
      }
    }
    state['phase'] = 'finished';
    widget.session.submit(state, status: RoomStatus.finished, winner: winner);
  }

  // ---- 단어 선택 / 제출 -----------------------------------------------------

  void _onCellTap(int index) {
    if (_isRoundOver) return;
    setState(() {
      if (_path.isNotEmpty && _path.last == index) {
        // 마지막 칸 다시 탭 → 한 칸 취소.
        _path.removeLast();
        return;
      }
      if (_path.contains(index)) {
        // 이미 쓴 칸(마지막 제외) 탭 → 그 칸까지로 잘라낸다.
        final at = _path.indexOf(index);
        _path.removeRange(at + 1, _path.length);
        return;
      }
      if (_path.isEmpty || widget.rules.adjacent(_path.last, index)) {
        _path.add(index);
      } else {
        // 인접하지 않은 칸 → 새 경로 시작.
        _path
          ..clear()
          ..add(index);
      }
    });
  }

  void _clearPath() => setState(() => _path.clear());

  void _submitWord() {
    if (_isRoundOver) return;
    final me = _me;
    final word = widget.rules.wordFromPath(_grid, _path);

    if (!widget.rules.isValidPath(_path)) {
      _toast('잘못된 경로입니다');
      return;
    }

    final found = _foundOf(me).toSet();
    final result = widget.rules.check(_grid, word, found);

    if (result != WordCheck.valid) {
      _toast(result.message);
      if (result == WordCheck.duplicate) _clearPath();
      return;
    }

    // 내 키(found/scores)만 바꿔 최신 state로 통째로 submit.
    final state = _freshState();
    final allFound = Map<String, dynamic>.from(state['found'] as Map);
    final myList = List<String>.from((allFound[me] as List?) ?? const []);
    myList.add(word);
    allFound[me] = myList;
    state['found'] = allFound;

    final allScores = Map<String, dynamic>.from(state['scores'] as Map);
    allScores[me] =
        ((allScores[me] as num?)?.toInt() ?? 0) + widget.rules.scoreFor(word);
    state['scores'] = allScores;

    widget.session.submit(state);
    setState(() => _path.clear());
    _toast(
      '+${widget.rules.scoreFor(word)}  ${widget.rules.displayWord(word)}',
    );
  }

  bool get _isRoundOver {
    if (widget.room.status == RoomStatus.finished) return true;
    if ((_secondsLeft ?? 1) <= 0) return true;
    if (_doneOf(_me)) return true;
    return false;
  }

  // ---- 빌드 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    if (room.status == RoomStatus.finished) {
      return Stack(
        children: [_buildPlayArea(context), _resultOverlay(context)],
      );
    }

    // 핫시트 가림막.
    if (_curtain && widget.session.hotseat) {
      return _curtainScreen(context);
    }

    final me = _me;

    // 온라인: 내 라운드는 끝났지만 상대가 아직이면 대기 화면.
    if (!widget.session.hotseat && _doneOf(me) && !_doneOf(_opponentId ?? '')) {
      return _waitingForOpponent(context);
    }

    return _buildPlayArea(context);
  }

  Widget _buildPlayArea(BuildContext context) {
    final me = _me;
    final myFound = _foundOf(me);
    final finished = widget.room.status == RoomStatus.finished;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const SizedBox(height: 12),
          _currentWordBar(),
          const SizedBox(height: 12),
          _grid.length == widget.rules.cellCount
              ? _board()
              : const SizedBox.shrink(),
          const SizedBox(height: 12),
          if (!finished) _actionButtons(),
          const SizedBox(height: 16),
          _scoreBoard(),
          const SizedBox(height: 16),
          _foundList(myFound),
        ],
      ),
    );
  }

  // ---- 헤더 / 타이머 --------------------------------------------------------

  Widget _header(BuildContext context) {
    final me = _me;
    final seat = widget.session.seatIndex(widget.room, me);
    final color = seat == 0 ? G42Colors.accent : G42Colors.warn;
    final left = _secondsLeft ?? widget.rules.durationSeconds;
    final lowTime = left <= 10;
    final timerColor = lowTime ? G42Colors.bad : color;

    final label = widget.session.hotseat ? '${_nameOf(me)} 차례' : '단어를 찾으세요';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Icon(Icons.timer_rounded, size: 20, color: timerColor),
          const SizedBox(width: 6),
          Text(
            '$left초',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: timerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentWordBar() {
    final word = _path.isEmpty
        ? '글자를 탭해 단어를 만드세요'
        : widget.rules.displayWord(widget.rules.wordFromPath(_grid, _path));
    final score = _path.isEmpty
        ? 0
        : widget.rules.scoreFor(widget.rules.wordFromPath(_grid, _path));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              word,
              style: TextStyle(
                fontSize: 22,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
                color: _path.isEmpty ? Colors.white38 : Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_path.isNotEmpty)
            Text(
              '+$score',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: G42Colors.good,
              ),
            ),
        ],
      ),
    );
  }

  // ---- 보드 -----------------------------------------------------------------

  /// 칸 사이 간격: 판이 클수록 좁게(칸을 최대한 크게).
  double get _cellSpacing => switch (widget.rules.size) {
    4 => 8,
    5 => 6,
    6 => 5,
    <= 8 => 4,
    _ => 3, // 10x10+
  };

  /// 글자 기준 폰트 크기: 판이 클수록 작게. (FittedBox가 추가로 줄여 맞춘다.)
  double get _cellFontSize => switch (widget.rules.size) {
    4 => 26,
    5 => 22,
    6 => 18,
    <= 8 => 15,
    _ => 13, // 10x10+
  };

  /// 경로 순서 배지 폰트.
  double get _orderFontSize => switch (widget.rules.size) {
    >= 8 => 8,
    6 || 7 => 9,
    _ => 11,
  };

  /// 칸 모서리 둥글기.
  double get _cellRadius => switch (widget.rules.size) {
    >= 8 => 6,
    6 || 7 => 9,
    _ => 12,
  };

  /// 칸 글자 안쪽 여백: 큰 판은 더 좁게.
  double get _cellPadding => widget.rules.size >= 8 ? 2 : 4;

  Widget _board() {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.rules.size,
          mainAxisSpacing: _cellSpacing,
          crossAxisSpacing: _cellSpacing,
        ),
        itemCount: widget.rules.cellCount,
        itemBuilder: (context, index) => _cell(index),
      ),
    );
  }

  Widget _cell(int index) {
    final inPath = _path.contains(index);
    final isLast = _path.isNotEmpty && _path.last == index;
    final order = inPath ? _path.indexOf(index) + 1 : 0;
    final over = _isRoundOver;

    final Color bg;
    final Color border;
    if (isLast) {
      bg = G42Colors.accent;
      border = Colors.white;
    } else if (inPath) {
      bg = G42Colors.accent.withValues(alpha: 0.55);
      border = G42Colors.accent;
    } else {
      bg = G42Colors.surfaceHi;
      border = G42Colors.surface;
    }

    return GestureDetector(
      onTap: over ? null : () => _onCellTap(index),
      child: Container(
        decoration: BoxDecoration(
          color: over ? G42Colors.surface : bg,
          borderRadius: BorderRadius.circular(_cellRadius),
          border: Border.all(color: border, width: isLast ? 2.5 : 1.5),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.all(_cellPadding),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.rules.displayAt(_grid, index),
                    style: TextStyle(
                      fontSize: _cellFontSize,
                      fontWeight: FontWeight.w900,
                      color: over ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            if (inPath)
              Positioned(
                top: 4,
                left: 6,
                child: Text(
                  '$order',
                  style: TextStyle(
                    fontSize: _orderFontSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 액션 버튼 ------------------------------------------------------------

  Widget _actionButtons() {
    final over = _isRoundOver;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (over || _path.isEmpty) ? null : _clearPath,
                icon: const Icon(Icons.backspace_rounded),
                label: const Text('지우기'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (over || _path.isEmpty) ? null : _submitWord,
                icon: const Icon(Icons.send_rounded),
                label: const Text('제출'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: over ? null : _onTimeUp,
          style: OutlinedButton.styleFrom(
            foregroundColor: G42Colors.bad,
            side: const BorderSide(color: G42Colors.bad),
          ),
          icon: const Icon(Icons.flag_rounded),
          label: const Text('끝내기'),
        ),
      ],
    );
  }

  // ---- 점수판 / 찾은 단어 ---------------------------------------------------

  Widget _scoreBoard() {
    final ids = widget.room.playerIds;
    return Row(
      children: [
        for (var i = 0; i < ids.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _scoreChip(ids[i], i)),
        ],
      ],
    );
  }

  Widget _scoreChip(String pid, int seat) {
    final color = seat == 0 ? G42Colors.accent : G42Colors.warn;
    final isMe = pid == _me;
    final done = _doneOf(pid);
    final hideScore =
        widget.session.hotseat &&
        widget.room.status != RoomStatus.finished &&
        !done; // 핫시트: 아직 진행 중인 플레이어 점수는 가린다(상대 화면에 노출 방지)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? color.withValues(alpha: 0.18) : G42Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? color : G42Colors.surfaceHi,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _nameOf(pid),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (done)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: G42Colors.good,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hideScore ? '••' : '${_scoreOf(pid)}점',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: hideScore ? Colors.white24 : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _foundList(List<String> words) {
    if (words.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('아직 찾은 단어가 없습니다', style: TextStyle(color: Colors.white38)),
      );
    }
    final sorted = List<String>.from(words)
      ..sort((a, b) => b.length.compareTo(a.length));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '찾은 단어 ${words.length}개',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in sorted)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: G42Colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: G42Colors.surfaceHi),
                ),
                child: Text(
                  '${widget.rules.displayWord(w)}  +${widget.rules.scoreFor(w)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---- 대기 / 가림막 / 결과 -------------------------------------------------

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
          Text('시간 종료!', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '내 점수 ${_scoreOf(_me)}점\n상대가 끝내기를 기다리는 중...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _curtainScreen(BuildContext context) {
    final me = _me;
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
            Text(
              '${_nameOf(me)} 차례',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '기기를 넘겨받았다면 시작하세요.\n${widget.rules.durationSeconds}초 동안 단어를 찾습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() => _curtain = false),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('시작'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultOverlay(BuildContext context) {
    final winner = widget.room.winner;
    final me = widget.session.myPlayerId;
    final isDraw = winner == 'draw';
    final iWon = winner == me;
    final ids = widget.room.playerIds;

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
      icon = Icons.emoji_events_rounded;
    } else if (iWon) {
      title = '승리!';
      color = G42Colors.good;
      icon = Icons.emoji_events_rounded;
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
                const SizedBox(height: 16),
                for (var i = 0; i < ids.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${_nameOf(ids[i])} : ${_scoreOf(ids[i])}점',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: i == 0 ? G42Colors.accent : G42Colors.warn,
                      ),
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
    _stopTimer();
    setState(() {
      _path.clear();
      _secondsLeft = null;
      _started = false;
      _curtain = false;
      _submittedDone = false;
      _lastHsTurn = null;
    });
    widget.session.rematch(
      widget.createInitialState(widget.room.playerIds),
      widget.firstTurn(widget.room.playerIds),
    );
  }

  // ---- 잡다 -----------------------------------------------------------------

  /// 최신 room.state 복제(내 키만 바꿔 통째로 submit하기 위한 베이스).
  Map<String, dynamic> _freshState() {
    final s = widget.room.state;
    return {
      'grid': (s['grid'] as String?) ?? '',
      'phase': (s['phase'] as String?) ?? 'playing',
      'found': Map<String, dynamic>.from(s['found'] as Map? ?? {}),
      'scores': Map<String, dynamic>.from(s['scores'] as Map? ?? {}),
      'done': Map<String, dynamic>.from(s['done'] as Map? ?? {}),
      'hsTurn': (s['hsTurn'] as String?) ?? '',
    };
  }

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
