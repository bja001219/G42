import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'reaction_logic.dart';

/// 반응속도 대결 메인 인게임 위젯.
///
/// 레이턴시 공정성: 각 플레이어는 '자기 화면에 초록이 렌더된 시각 → 자기 탭 시각'의
/// 로컬 반응시간(ms)을 측정한다. 측정값만 state에 기록하고, 라운드 판정은 두 값이
/// 모두 모였을 때 한다.
class ReactionView extends StatefulWidget {
  final GameSession session;
  final Room room;
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;
  final int targetWins;

  const ReactionView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
    required this.targetWins,
  });

  @override
  State<ReactionView> createState() => _ReactionViewState();
}

class _ReactionViewState extends State<ReactionView> {
  final Random _rng = Random();

  /// go 단계에서 화면을 빨강→초록으로 바꾸기 위한 로컬 타이머.
  Timer? _ticker;

  /// 초록이 이 기기 화면에 처음 렌더된 로컬 시각(ms epoch). null이면 아직 빨강.
  int? _localGreenAt;

  /// 이 기기가 'go' 단계를 관측한 로컬 시각(ms epoch). 여기서부터 지연을 센다.
  int? _goObservedAt;

  /// 이번 go 라운드에서 내가 이미 기록(탭/부정출발)했는지(로컬 가드).
  bool _localRecorded = false;

  /// 라운드 판정 중복 제출 방지.
  bool _resolveRequested = false;

  /// 핫시트: 가림막 표시 여부.
  bool _curtain = false;

  /// 현재 추적 중인 라운드(라운드 변경 감지용).
  int _trackedRound = 0;

  /// 현재 추적 중인 단계(단계 변경 감지용).
  String _trackedPhase = '';

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  Map<String, dynamic> get _state => widget.room.state;

  String get _phase => (_state['phase'] as String?) ?? 'arming';

  int get _round => (_state['round'] as int?) ?? 1;

  int get _goDelay => (_state['goDelayMillis'] as int?) ?? 0;

  int get _hotseatActive => (_state['hotseatActive'] as int?) ?? 0;

  String get _me => widget.session.actingPlayerId(widget.room);

  int _winsOf(String pid) {
    final wins = _state['wins'] as Map?;
    return (wins?[pid] as int?) ?? 0;
  }

  int _reactionOf(String pid) {
    final r = _state['reaction'] as Map?;
    return (r?[pid] as int?) ?? ReactionLogic.notRecorded;
  }

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  /// 핫시트에서 지금 측정해야 하는 플레이어 id.
  String _hotseatMeasurer() {
    final ids = widget.room.playerIds;
    if (ids.isEmpty) return _me;
    final i = _hotseatActive.clamp(0, ids.length - 1);
    return ids[i];
  }

  /// 최신 room.state 복제.
  Map<String, dynamic> _freshState() {
    final s = _state;
    return {
      'phase': (s['phase'] as String?) ?? 'arming',
      'round': (s['round'] as int?) ?? 1,
      'wins': Map<String, dynamic>.from(s['wins'] as Map? ?? {}),
      'reaction': Map<String, dynamic>.from(s['reaction'] as Map? ?? {}),
      'goDelayMillis': (s['goDelayMillis'] as int?) ?? 0,
      'hotseatActive': (s['hotseatActive'] as int?) ?? 0,
    };
  }

  // ---- 생명주기 -------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _trackedRound = _round;
    _trackedPhase = _phase;
    _syncToPhase();
  }

  @override
  void didUpdateWidget(covariant ReactionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final phaseChanged = _phase != _trackedPhase;
    final roundChanged = _round != _trackedRound;
    if (phaseChanged || roundChanged) {
      _trackedPhase = _phase;
      _trackedRound = _round;
      _syncToPhase();
    } else {
      // 같은 go 단계 안에서 상대 기록이 들어왔을 수 있다 → 판정 체크.
      _maybeResolveRound();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 단계/라운드가 바뀔 때 로컬 측정 상태를 초기화하고 필요한 타이머를 건다.
  void _syncToPhase() {
    _ticker?.cancel();
    _localGreenAt = null;
    _localRecorded = false;
    _resolveRequested = false;
    _goObservedAt = null;

    if (widget.room.status == RoomStatus.finished) return;

    if (_phase == 'go') {
      // 핫시트: 측정자가 아니면 가림막.
      if (widget.session.hotseat) {
        final measurer = _hotseatMeasurer();
        if (_reactionOf(measurer) != ReactionLogic.notRecorded) {
          // 이미 기록된 측정자면(이상 상태) 판정 체크.
          _maybeResolveRound();
          return;
        }
      }
      // 이 기기가 'go'를 관측한 로컬 시각을 기준점으로 잡는다.
      _goObservedAt = DateTime.now().millisecondsSinceEpoch;
      _startGoTicker();
    } else if (_phase == 'roundResult') {
      _maybeResolveRound();
    }
  }

  /// go 단계: 각 기기가 'go'를 관측한 로컬 시각으로부터 goDelayMillis 만큼 지나면
  /// 초록으로 전환한다. 절대 시각을 공유하지 않으므로 두 폰의 시계 차와 무관하게 공정하다.
  void _startGoTicker() {
    _ticker?.cancel();
    final delay = _goDelay;
    final observed = _goObservedAt ??= DateTime.now().millisecondsSinceEpoch;
    bool ready() =>
        delay > 0 && DateTime.now().millisecondsSinceEpoch - observed >= delay;
    if (ready()) {
      _flipGreen();
      return;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (ready()) {
        t.cancel();
        _flipGreen();
      }
    });
  }

  void _flipGreen() {
    if (!mounted) return;
    setState(() {
      _localGreenAt = DateTime.now().millisecondsSinceEpoch;
    });
  }

  // ---- 라운드 진행 ----------------------------------------------------------

  /// arming 단계에서 라운드 시작. 온라인은 호스트만, 핫시트는 누구나(측정자 화면).
  void _onArm() {
    final delay = 1500 + _rng.nextInt(2500); // 1.5 ~ 4.0초
    final state = _freshState();
    state['phase'] = 'go';
    // 절대 시각이 아니라 '각자 go 관측 후 대기할 지연(ms)'만 공유한다(시계 차 무관).
    state['goDelayMillis'] = delay;
    widget.session.submit(state);
  }

  /// 화면 탭. go 단계에서만 의미. 초록 전이면 부정출발.
  void _onTapPanel() {
    if (_phase != 'go') return;
    if (_localRecorded) return;

    // 핫시트: 지금 측정자가 맞는지 확인(가림막이 풀린 상태여야 함).
    if (widget.session.hotseat && _curtain) return;

    final recorder = widget.session.hotseat ? _hotseatMeasurer() : _me;

    int ms;
    if (_localGreenAt == null) {
      // 부정출발.
      ms = ReactionLogic.falseStart;
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      ms = now - _localGreenAt!;
      if (ms < 0) ms = 0;
    }

    _localRecorded = true;
    _ticker?.cancel();

    if (widget.session.hotseat) {
      // 핫시트는 한 기기에서 순차 측정 → 경쟁이 없으므로 전체 state 제출.
      final state = _freshState();
      (state['reaction'] as Map<String, dynamic>)[recorder] = ms;
      _handleHotseatRecord(state, recorder);
    } else {
      // 온라인: 내 좌석 칸만 점(dotted) 패치로 기록한다.
      // (기존엔 전체 state를 통째로 submit 했는데, 두 명이 거의 동시에 탭하면
      //  각자 상대 기록이 0인 stale state를 써 보내 서로를 덮어써서(clobber)
      //  reaction 한쪽이 영영 0으로 남아 라운드 판정이 무한 대기에 빠졌다.)
      //  dotted 키는 Firestore의 중첩 필드 업데이트/로컬 applyPatch 모두 해당
      //  칸만 머지하므로 양쪽 반응시간이 보존되어 호스트가 정상 판정한다.
      widget.session.patch({'state.reaction.$recorder': ms});
      // 제출 후 didUpdateWidget에서 양쪽 기록 확인 → 호스트가 판정.
      setState(() {});
    }
  }

  /// 핫시트: 측정자 기록 후 다음 측정자로 넘기거나, 둘 다 끝났으면 판정.
  void _handleHotseatRecord(Map<String, dynamic> state, String recorder) {
    final ids = widget.room.playerIds;
    final reaction = state['reaction'] as Map<String, dynamic>;
    final allRecorded = ids.every(
      (pid) => ((reaction[pid] as int?) ?? 0) != ReactionLogic.notRecorded,
    );

    if (allRecorded) {
      _applyRoundResult(state);
    } else {
      // 다음 측정자로.
      final nextIdx = (_hotseatActive + 1).clamp(0, ids.length - 1);
      state['hotseatActive'] = nextIdx;
      // 다음 측정자는 새 무작위 지연으로 다시 go.
      final delay = 1500 + _rng.nextInt(2500);
      state['goDelayMillis'] = delay;
      widget.session.submit(state);
      setState(() => _curtain = true);
    }
  }

  /// 온라인: 두 명 모두 기록되면 라운드 판정(중복 방지: 호스트가 주도).
  void _maybeResolveRound() {
    if (widget.session.hotseat) return;
    if (_phase != 'go') return;
    if (_resolveRequested) return;
    if (widget.room.status == RoomStatus.finished) return;

    final ids = widget.room.playerIds;
    if (ids.length < 2) return;
    final all = ids.every(
      (pid) => _reactionOf(pid) != ReactionLogic.notRecorded,
    );
    if (!all) return;

    // 호스트만 판정 제출(경쟁 방지).
    if (widget.session.myPlayerId != ids.first) return;

    _resolveRequested = true;
    final state = _freshState();
    _applyRoundResult(state);
  }

  /// 두 측정값으로 라운드 승자를 정해 wins 갱신 후 roundResult 단계로.
  /// 매치 선취 시 finished.
  void _applyRoundResult(Map<String, dynamic> state) {
    final ids = widget.room.playerIds;
    final a = ids[0];
    final b = ids.length > 1 ? ids[1] : ids[0];
    final reaction = state['reaction'] as Map<String, dynamic>;
    final msA = (reaction[a] as int?) ?? ReactionLogic.notRecorded;
    final msB = (reaction[b] as int?) ?? ReactionLogic.notRecorded;

    final result = ReactionLogic.roundWinner(msA, msB);
    final wins = state['wins'] as Map<String, dynamic>;
    if (result == 0) {
      wins[a] = ((wins[a] as int?) ?? 0) + 1;
    } else if (result == 1) {
      wins[b] = ((wins[b] as int?) ?? 0) + 1;
    }
    // result == -1 (무승부)면 둘 다 점수 없음.

    state['phase'] = 'roundResult';

    final winsA = (wins[a] as int?) ?? 0;
    final winsB = (wins[b] as int?) ?? 0;
    if (winsA >= widget.targetWins || winsB >= widget.targetWins) {
      final matchWinner = winsA >= widget.targetWins ? a : b;
      widget.session.submit(
        state,
        status: RoomStatus.finished,
        winner: matchWinner,
      );
    } else {
      widget.session.submit(state);
    }
  }

  /// 다음 라운드 준비(arming으로). 측정값 리셋. 호스트/핫시트가 주도.
  void _onNextRound() {
    final ids = widget.room.playerIds;
    final state = _freshState();
    final reaction = state['reaction'] as Map<String, dynamic>;
    for (final pid in ids) {
      reaction[pid] = ReactionLogic.notRecorded;
    }
    state['phase'] = 'arming';
    state['goDelayMillis'] = 0;
    state['hotseatActive'] = 0;
    state['round'] = ((state['round'] as int?) ?? 1) + 1;
    widget.session.submit(state);
  }

  void _onRematch() {
    setState(() {
      _curtain = false;
      _localGreenAt = null;
      _localRecorded = false;
      _resolveRequested = false;
    });
    widget.session.rematch(
      widget.createInitialState(widget.room.playerIds),
      widget.firstTurn(widget.room.playerIds),
    );
  }

  // ---- 빌드 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final finished = widget.room.status == RoomStatus.finished;

    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _scoreBar(),
            const SizedBox(height: 12),
            Expanded(child: _mainPanel(finished)),
          ],
        ),
      ),
    );

    if (!finished) return content;
    return Stack(children: [content, _resultOverlay(context)]);
  }

  Widget _mainPanel(bool finished) {
    if (finished) return _reactionPanel(green: false, label: '게임 종료');

    // 핫시트 가림막.
    if (widget.session.hotseat && _curtain && _phase == 'go') {
      return _curtainPanel();
    }

    switch (_phase) {
      case 'arming':
        return _armingPanel();
      case 'go':
        return _goPanel();
      case 'roundResult':
        return _roundResultPanel();
      default:
        return _armingPanel();
    }
  }

  // ---- 단계별 패널 ----------------------------------------------------------

  Widget _armingPanel() {
    final ids = widget.room.playerIds;
    final iAmHost =
        widget.session.hotseat ||
        (ids.isNotEmpty && widget.session.myPlayerId == ids.first);

    final sub = widget.session.hotseat
        ? '먼저 ${_nameOf(_hotseatMeasurer())}님이 측정합니다.'
        : '초록 불이 켜지면 즉시 탭하세요. 너무 빨리 누르면 부정출발 패배!';

    return Column(
      children: [
        Expanded(
          child: _panelBox(
            color: G42Colors.surfaceHi,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bolt_rounded, size: 72, color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  '$_round 라운드 준비',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (iAmHost)
          FilledButton.icon(
            onPressed: _onArm,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('시작'),
          )
        else
          const Text(
            '호스트가 라운드를 시작하길 기다리는 중...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
      ],
    );
  }

  Widget _goPanel() {
    final isGreen = _localGreenAt != null;
    final recorder = widget.session.hotseat ? _hotseatMeasurer() : _me;
    final myMs = _reactionOf(recorder);
    final iRecorded = myMs != ReactionLogic.notRecorded || _localRecorded;

    if (iRecorded && !widget.session.hotseat) {
      // 온라인: 내 기록 끝, 상대 대기.
      return _waitingPanel(myMs);
    }

    final label = isGreen ? '지금! 탭하세요' : '대기...';
    return GestureDetector(
      onTap: _onTapPanel,
      child: _reactionPanel(green: isGreen, label: label),
    );
  }

  Widget _reactionPanel({required bool green, required String label}) {
    final color = green ? G42Colors.good : G42Colors.bad;
    return _panelBox(
      color: color.withValues(alpha: 0.9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            green ? Icons.touch_app_rounded : Icons.hourglass_top_rounded,
            size: 84,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            green ? '' : '초록이 될 때까지 기다리세요',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _waitingPanel(int myMs) {
    final text = myMs == ReactionLogic.falseStart ? '부정출발!' : '${myMs}ms';
    final color = myMs == ReactionLogic.falseStart
        ? G42Colors.bad
        : G42Colors.accent;
    return _panelBox(
      color: G42Colors.surfaceHi,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '내 기록',
            style: const TextStyle(color: Colors.white60, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '상대의 반응을 기다리는 중...',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _curtainPanel() {
    return _panelBox(
      color: G42Colors.surfaceHi,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.visibility_off_rounded,
            size: 72,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            '${_nameOf(_hotseatMeasurer())} 차례',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            '기기를 넘겨받았다면 시작하세요.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() => _curtain = false);
              // 가림막을 내린 뒤 측정 타이머 시작.
              _syncToPhase();
            },
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('측정 시작'),
          ),
        ],
      ),
    );
  }

  Widget _roundResultPanel() {
    final ids = widget.room.playerIds;
    final a = ids.isNotEmpty ? ids[0] : '';
    final b = ids.length > 1 ? ids[1] : '';
    final msA = _reactionOf(a);
    final msB = _reactionOf(b);
    final result = ReactionLogic.roundWinner(msA, msB);

    final iAmHost =
        widget.session.hotseat ||
        (ids.isNotEmpty && widget.session.myPlayerId == ids.first);

    return Column(
      children: [
        Expanded(
          child: _panelBox(
            color: G42Colors.surface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  result == -1 ? '무승부' : '${_nameOf(result == 0 ? a : b)} 승!',
                  style: TextStyle(
                    color: result == -1 ? G42Colors.warn : G42Colors.good,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                _msRow(a, msA),
                const SizedBox(height: 8),
                _msRow(b, msB),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (iAmHost)
          FilledButton.icon(
            onPressed: _onNextRound,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('다음 라운드'),
          )
        else
          const Text(
            '다음 라운드를 기다리는 중...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
      ],
    );
  }

  Widget _msRow(String pid, int ms) {
    final foul = ms == ReactionLogic.falseStart;
    final text = foul ? '부정출발' : '${ms}ms';
    final color = foul ? G42Colors.bad : Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${_nameOf(pid)}: ',
          style: const TextStyle(color: Colors.white60),
        ),
        Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  // ---- 공통 위젯 ------------------------------------------------------------

  Widget _scoreBar() {
    final ids = widget.room.playerIds;
    final a = ids.isNotEmpty ? ids[0] : '';
    final b = ids.length > 1 ? ids[1] : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Row(
        children: [
          _scorePill(a, G42Colors.accent),
          Column(
            children: [
              Text(
                '$_round R',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${widget.targetWins}선승',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          _scorePill(b, G42Colors.warn),
        ],
      ),
    );
  }

  Widget _scorePill(String pid, Color color) {
    if (pid.isEmpty) return const Expanded(child: SizedBox.shrink());
    return Expanded(
      child: Column(
        children: [
          Text(
            _nameOf(pid),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '${_winsOf(pid)}',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelBox({required Color color, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _resultOverlay(BuildContext context) {
    final winner = widget.room.winner;
    final me = widget.session.hotseat ? null : _me;
    final iWon = me != null && winner == me;

    final String title;
    final Color color;
    final IconData icon;
    if (widget.session.hotseat) {
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

    final ids = widget.room.playerIds;
    final scoreLine = ids.length > 1
        ? '${_nameOf(ids[0])} ${_winsOf(ids[0])} : ${_winsOf(ids[1])} ${_nameOf(ids[1])}'
        : '';

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
                if (scoreLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    scoreLine,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
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
}
