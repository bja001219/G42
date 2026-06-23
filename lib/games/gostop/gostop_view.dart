import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'gostop_card_widget.dart';
import 'gostop_cards.dart';
import 'gostop_logic.dart';

/// 고스톱(2인 맞고) 메인 인게임 위젯.
///
/// 동기화 상태는 [Room.state]에서만 읽고, 임시/표시 상태(가림막, 직전 이벤트 토스트
/// 표시 여부)는 로컬 State에 둔다. state는 항상 통째로 [GameSession.submit].
class GoStopView extends StatefulWidget {
  final GameSession session;
  final Room room;

  /// 재대국용 초기 상태 생성기.
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  const GoStopView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
  });

  @override
  State<GoStopView> createState() => _GoStopViewState();
}

class _GoStopViewState extends State<GoStopView> {
  /// 핫시트: 차례 전환 시 손패를 가리는 가림막.
  bool _curtain = false;

  /// 핫시트: 마지막으로 본 차례 주체(전환 감지용).
  String? _lastActor;

  /// 직전에 토스트로 보여준 이벤트(중복 방지).
  String? _shownEvent;

  /// 총통/3뻑/나가리/기록 같은 1회 자동 처리의 중복 submit 방지 플래그.
  bool _autoActionInFlight = false;

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  Map<String, dynamic> get _state => widget.room.state;

  String get _phase => (_state['phase'] as String?) ?? 'playing';

  String get _me => widget.session.actingPlayerId(widget.room);

  String? get _opponentId => widget.session.opponentOf(widget.room, _me)?.id;

  List<int> _handOf(String pid) => _intList((_state['hands'] as Map?)?[pid]);

  List<int> _capturedOf(String pid) =>
      _intList((_state['captured'] as Map?)?[pid]);

  List<int> get _floor => _intList(_state['floor']);

  List<int> get _stock => _intList(_state['stock']);

  int _goOf(String pid) => _intAt('go', pid);
  int _shakenOf(String pid) => _intAt('shaken', pid);
  int _bombOf(String pid) => _intAt('bomb', pid);

  int _intAt(String key, String pid) {
    final m = _state[key];
    if (m is Map) {
      final v = m[pid];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  String get _awaitingGoStop => (_state['awaitingGoStop'] as String?) ?? '';

  List<int> _intList(dynamic raw) {
    if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
    return <int>[];
  }

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  // ---- 생애주기 -------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _lastActor = widget.session.hotseat ? widget.room.turn : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeHandleChongtong();
      _maybeAutoFinalize();
    });
  }

  @override
  void didUpdateWidget(covariant GoStopView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRaiseCurtainOnTurnChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowEventToast();
      _maybeHandleChongtong();
      _maybeAutoFinalize();
    });
  }

  void _maybeRaiseCurtainOnTurnChange() {
    if (!widget.session.hotseat) return;
    if (widget.room.status == RoomStatus.finished) return;
    final actor = widget.room.turn;
    if (actor != null && _lastActor != null && actor != _lastActor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _curtain = true);
      });
    }
    _lastActor = actor;
  }

  // ---- 자동 처리: 총통 / 나가리 / 3뻑 / 전적기록 ---------------------------

  /// 딜 직후(첫 턴, 진행 중) 내 손패가 같은 달 4장이면 즉시 승.
  /// 양쪽 클라이언트 일관을 위해 그 손패를 가진(=acting) 플레이어가 1회 처리.
  void _maybeHandleChongtong() {
    if (_phase != 'playing') return;
    if (widget.room.status == RoomStatus.finished) return;
    if (_autoActionInFlight) return;
    final me = _me;
    if (!widget.session.isMyTurn(widget.room)) return;
    final month = GoStopLogic.checkChongtong(_handOf(me));
    if (month == null) return;
    _autoActionInFlight = true;
    final state = _freshState();
    state['phase'] = 'finished';
    state['winner'] = me;
    state['lastEvent'] = GoStopLogic.evChongtong;
    // 총통 점수: 기본 큰 점수(사양서 8장 예시 +α). 흔들기/나가리 배수만 반영.
    final score = GoStopLogic.finalizeScore(
      10,
      nagariMult: (state['nagariMult'] as num?)?.toInt() ?? 1,
    );
    state['roundScore'] = score;
    state['winnerId'] = me;
    widget.session.submit(state, status: RoomStatus.finished, winner: me);
  }

  /// 라운드가 끝났으면(또는 나가리/3뻑) 전적을 1회 기록한다.
  void _maybeAutoFinalize() {
    // 종료 상태에서는 전적 기록 경로로 직행한다.
    // (_autoActionInFlight 는 '종료 전이 submit' 중복 방지 용도이지 기록을
    //  막는 가드가 아니다. 종료 state 가 되돌아온 뒤에는 항상 기록을 시도하고,
    //  중복은 _state['recorded'] 플래그 + 기록 주체 식별로만 막는다.)
    if (widget.room.status == RoomStatus.finished) {
      _recordIfNeeded();
      return;
    }

    // 진행 중 종료 전이(총통/3뻑/나가리) 중복 submit 은 이 가드로만 막는다.
    if (_autoActionInFlight) return;

    // 진행 중인데 3뻑이 발생했으면 상대 즉시 승으로 종료한다.
    final winner = GoStopLogic.checkThreePpeokWinner(_state);
    if (winner != null && widget.session.isMyTurn(widget.room)) {
      _autoActionInFlight = true;
      final state = _freshState();
      state['phase'] = 'finished';
      state['winner'] = winner;
      final score = GoStopLogic.finalizeScore(
        GoStopLogic.goStopThreshold,
        nagariMult: (state['nagariMult'] as num?)?.toInt() ?? 1,
      );
      state['roundScore'] = score;
      state['winnerId'] = winner;
      widget.session.submit(state, status: RoomStatus.finished, winner: winner);
      return;
    }

    // 나가리: 더미 + 양쪽 손패 모두 소진. 호스트 클라이언트가 1회 처리.
    if (GoStopLogic.isNagari(_state)) {
      final host = widget.room.playerIds.isNotEmpty
          ? widget.room.playerIds.first
          : null;
      final iAmHost =
          widget.session.hotseat || widget.session.myPlayerId == host;
      if (iAmHost && _state['nagari'] != true) {
        _autoActionInFlight = true;
        final state = _freshState();
        state['phase'] = 'finished';
        state['nagari'] = true;
        // 다음 판 누적 배수: 직전 × 2.
        final prevMult = (state['nagariMult'] as num?)?.toInt() ?? 1;
        state['nagariMult'] = prevMult * 2;
        widget.session.submit(
          state,
          status: RoomStatus.finished,
          winner: 'draw',
        );
      }
      return;
    }
  }

  /// 전적을 정확히 1회만 기록한다(score_store 호출 계약 준수).
  ///
  /// 계약(score_store.dart §22)대로 기록을 await 한 뒤 같은 흐름에서
  /// recorded=true 를 커밋한다. 기록 Future 가 실패하면 recorded 를 세우지
  /// 않아(가드만 서고 기록은 누락되는 상태를 방지) 다음 프레임에서 재시도된다.
  Future<void> _recordIfNeeded() async {
    if (_state['recorded'] == true) return;
    // 진행 중인 기록 트랜잭션이 끝나기 전에 didUpdateWidget 이 다시 호출돼도
    // 중복 기록하지 않도록, 기록 흐름 동안만 in-flight 로 표시한다.
    if (_recordInFlight) return;
    final isNagari = _state['nagari'] == true || widget.room.winner == 'draw';

    if (isNagari) {
      // 나가리: 승자 없음 → 호스트 클라이언트(또는 핫시트 처리 주체)가 1회.
      final ids = widget.room.playerIds;
      if (ids.length < 2) return;
      final host = ids.first;
      final iAmRecorder =
          widget.session.hotseat || widget.session.myPlayerId == host;
      if (!iAmRecorder) return;
      final aId = ids[0];
      final bId = ids[1];
      _recordInFlight = true;
      try {
        await AppServices.of(context).scoreStore.recordNagari(
          idA: aId,
          nameA: _nameOf(aId),
          idB: bId,
          nameB: _nameOf(bId),
        );
        if (!mounted) return;
        await _markRecorded();
      } catch (_) {
        // 기록 실패: recorded 를 세우지 않는다. 다음 프레임에서 재시도.
      } finally {
        _recordInFlight = false;
      }
      return;
    }

    final winnerId = (_state['winnerId'] as String?) ?? widget.room.winner;
    if (winnerId == null || winnerId.isEmpty) return;
    final loserId = widget.room.opponentOf(winnerId)?.id;
    if (loserId == null) return;

    // 처리 주체: 온라인은 승자 클라이언트, 핫시트는 단일 디바이스.
    final iAmRecorder =
        widget.session.hotseat || widget.session.myPlayerId == winnerId;
    if (!iAmRecorder) return;

    final score = (_state['roundScore'] as num?)?.toInt() ?? 0;
    _recordInFlight = true;
    try {
      await AppServices.of(context).scoreStore.recordRound(
        winnerId: winnerId,
        winnerName: _nameOf(winnerId),
        loserId: loserId,
        loserName: _nameOf(loserId),
        score: score,
      );
      if (!mounted) return;
      await _markRecorded();
    } catch (_) {
      // 기록 실패: recorded 를 세우지 않는다. 다음 프레임에서 재시도.
    } finally {
      _recordInFlight = false;
    }
  }

  /// 기록 트랜잭션이 진행 중인지(중복 기록 방지).
  bool _recordInFlight = false;

  Future<void> _markRecorded() {
    final state = _freshState();
    state['recorded'] = true;
    return widget.session.submit(state);
  }

  // ---- 빌드 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    // 핫시트 가림막.
    if (room.status != RoomStatus.finished &&
        _curtain &&
        widget.session.hotseat) {
      return _curtainScreen(context);
    }

    final finished = room.status == RoomStatus.finished;

    // 고/스톱 대기면 다이얼로그를 띄운다.
    if (!finished) _maybeShowGoStop();

    final content = _buildTable(context, finished);

    if (!finished) return content;
    return Stack(children: [content, _resultOverlay(context)]);
  }

  Widget _buildTable(BuildContext context, bool finished) {
    final me = _me;
    final opp = _opponentId;
    final myHand = _handOf(me);
    final oppHand = opp != null ? _handOf(opp) : <int>[];
    final myCap = _capturedOf(me);
    final oppCap = opp != null ? _capturedOf(opp) : <int>[];
    final myScore = GoStopLogic.scoreOf(myCap);
    final oppScore = GoStopLogic.scoreOf(oppCap);
    final myTurn = widget.session.isMyTurn(widget.room) && !finished;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _turnBanner(myTurn, finished),
            const SizedBox(height: 10),
            // 상대 영역.
            _opponentPanel(opp, oppHand.length, oppCap, oppScore),
            const SizedBox(height: 12),
            // 중앙: 바닥 + 더미.
            _floorPanel(),
            const SizedBox(height: 12),
            // 내 먹은패 + 점수.
            _myCapturePanel(myCap, myScore),
            const SizedBox(height: 10),
            // 액션 버튼.
            if (!finished) _actionRow(me, myHand, myTurn),
            const SizedBox(height: 10),
            // 내 손패.
            _myHandPanel(me, myHand, myTurn),
          ],
        ),
      ),
    );
  }

  // ---- 차례 배너 / 이벤트 ---------------------------------------------------

  Widget _turnBanner(bool myTurn, bool finished) {
    if (finished) return const SizedBox.shrink();
    final me = _me;
    final seat = widget.session.seatIndex(widget.room, me);
    final color = seat == 0 ? G42Colors.accent : G42Colors.warn;
    final name = _nameOf(me);
    final myScore = GoStopLogic.scoreOf(_capturedOf(me)).total;

    final label = widget.session.hotseat
        ? '$name 차례'
        : (myTurn ? '내 차례' : '상대 차례 — 대기 중');

    final event = (_state['lastEvent'] as String?) ?? GoStopLogic.evNone;
    final evtText = _eventLabel(event);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (myTurn ? color : G42Colors.surface).withValues(
          alpha: myTurn ? 0.22 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: myTurn ? color : G42Colors.surfaceHi,
          width: myTurn ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            myTurn
                ? Icons.play_circle_fill_rounded
                : Icons.hourglass_empty_rounded,
            color: myTurn ? color : Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: myTurn ? Colors.white : Colors.white60,
                  ),
                ),
                Text(
                  '내 점수 $myScore점${evtText.isNotEmpty ? '   ·   $evtText' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: G42Colors.surfaceHi,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '더미 ${_stock.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _maybeShowEventToast() {
    final event = (_state['lastEvent'] as String?) ?? GoStopLogic.evNone;
    if (event == GoStopLogic.evNone || event == GoStopLogic.evEat) {
      _shownEvent = event;
      return;
    }
    if (event == _shownEvent) return;
    _shownEvent = event;
    final text = _eventLabel(event);
    if (text.isNotEmpty) _toast(text);
  }

  String _eventLabel(String event) {
    switch (event) {
      case GoStopLogic.evPpeok:
        return '뻑!';
      case GoStopLogic.evJappeok:
        return '자뻑! (상대 피 획득)';
      case GoStopLogic.evTtadak:
        return '따닥! (상대 피 획득)';
      case GoStopLogic.evJjok:
        return '쪽! (상대 피 획득)';
      case GoStopLogic.evSseulgi:
        return '쓸기! (상대 피 획득)';
      case GoStopLogic.evBonus:
        return '보너스패!';
      case GoStopLogic.evBomb:
        return '폭탄! (추가 턴)';
      case GoStopLogic.evChongtong:
        return '총통!';
      default:
        return '';
    }
  }

  // ---- 상대 영역 ------------------------------------------------------------

  Widget _opponentPanel(
    String? opp,
    int handCount,
    List<int> oppCap,
    GoStopScore oppScore,
  ) {
    final oppGo = opp != null ? _goOf(opp) : 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  opp != null ? _nameOf(opp) : '상대',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (oppGo > 0) _badge('$oppGo고', G42Colors.warn),
              const SizedBox(width: 6),
              _badge('${oppScore.total}점', G42Colors.bad),
            ],
          ),
          const SizedBox(height: 8),
          // 상대 손패: 뒷면 카드 N장.
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (var i = 0; i < handCount; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: GoStopCardWidget(
                      cardId: 0,
                      faceDown: true,
                      width: 26,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _captureSummary(oppCap, oppScore, compact: true),
        ],
      ),
    );
  }

  // ---- 바닥 + 더미 ----------------------------------------------------------

  Widget _floorPanel() {
    final floor = _floor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14331E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E5631)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grass_rounded,
                size: 16,
                color: Color(0xFF8BC34A),
              ),
              const SizedBox(width: 6),
              Text(
                '바닥 (${floor.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              // 더미: 뒷면 1장 + 남은 장수.
              GoStopCardWidget(cardId: 0, faceDown: true, width: 24),
              const SizedBox(width: 6),
              Text(
                '×${_stock.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (floor.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '바닥이 비어 있습니다',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final id in floor) GoStopCardWidget(cardId: id, width: 40),
              ],
            ),
        ],
      ),
    );
  }

  // ---- 내 먹은패 / 점수 -----------------------------------------------------

  Widget _myCapturePanel(List<int> myCap, GoStopScore score) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G42Colors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              const Text(
                '내 먹은 패',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              _badge('${score.total}점', G42Colors.good),
            ],
          ),
          const SizedBox(height: 8),
          _captureSummary(myCap, score, compact: false),
        ],
      ),
    );
  }

  /// 먹은 패를 분류별(광/띠/열끗/피)로 요약 표시.
  Widget _captureSummary(
    List<int> cap,
    GoStopScore score, {
    required bool compact,
  }) {
    final gwang = cap.where(GoStopCards.isGwang).toList();
    final ribbon = cap.where(GoStopCards.isRibbon).toList();
    final animal = cap.where(GoStopCards.isAnimal).toList();
    final junk = cap.where(GoStopCards.isJunk).toList();
    final cw = compact ? 22.0 : 34.0;

    Widget group(String label, List<int> ids, Color color, String detail) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color),
                ),
                child: Text(
                  '$label ${ids.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ],
          ),
          if (ids.isNotEmpty) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                for (final id in ids) GoStopCardWidget(cardId: id, width: cw),
              ],
            ),
          ],
          const SizedBox(height: 6),
        ],
      );
    }

    final ribbonDetail = [
      if (score.hasHong) '홍단',
      if (score.hasCheong) '청단',
      if (score.hasCho) '초단',
    ].join('·');

    if (compact) {
      // 상대용: 분류별 장수만.
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _badge('광 ${gwang.length}', const Color(0xFFB8860B)),
          _badge('띠 ${ribbon.length}', G42Colors.bad),
          _badge('열끗 ${animal.length}', G42Colors.good),
          _badge('피 ${GoStopLogic.junkCount(cap)}', const Color(0xFF90A4AE)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group(
          '광',
          gwang,
          const Color(0xFFD4AF37),
          score.gwangScore > 0 ? '${score.gwangScore}점' : '',
        ),
        group(
          '띠',
          ribbon,
          G42Colors.bad,
          [
            if (ribbonDetail.isNotEmpty) ribbonDetail,
            if (score.ribbonScore > 0) '${score.ribbonScore}점',
          ].join(' '),
        ),
        group(
          '열끗',
          animal,
          G42Colors.good,
          [
            if (score.hasGodori) '고도리',
            if (score.animalScore > 0) '${score.animalScore}점',
          ].join(' '),
        ),
        group(
          '피',
          junk,
          const Color(0xFF90A4AE),
          '${GoStopLogic.junkCount(cap)}장'
              '${score.junkScore > 0 ? ' · ${score.junkScore}점' : ''}',
        ),
      ],
    );
  }

  // ---- 내 손패 --------------------------------------------------------------

  Widget _myHandPanel(String me, List<int> myHand, bool myTurn) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: myTurn ? G42Colors.warn : G42Colors.surfaceHi,
          width: myTurn ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.back_hand_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                '내 손패 (${myHand.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (myTurn)
                const Text(
                  '카드를 탭하세요',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: [
              for (final id in myHand)
                GoStopCardWidget(
                  cardId: id,
                  width: 48,
                  onTap: myTurn ? () => _onPlayHandCard(me, id) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 액션 버튼 ------------------------------------------------------------

  Widget _actionRow(String me, List<int> myHand, bool myTurn) {
    if (!myTurn) return const SizedBox.shrink();

    // 폭탄 가능: 손패 같은 달 3장 + 바닥 같은 달 1장.
    final floor = _floor;
    final bombMonths = <int>{};
    for (var m = 1; m <= 12; m++) {
      final inHand = myHand.where((c) => GoStopCards.monthOf(c) == m).length;
      final inFloor = floor.where((c) => GoStopCards.monthOf(c) == m).length;
      if (inHand >= 3 && inFloor >= 1) bombMonths.add(m);
    }

    if (bombMonths.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in bombMonths)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: G42Colors.bad,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => _onBomb(me, m),
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: Text('폭탄 $m월'),
          ),
      ],
    );
  }

  // ---- 입력 핸들러 ----------------------------------------------------------

  Future<void> _onPlayHandCard(String me, int cardId) async {
    if (!widget.session.isMyTurn(widget.room)) return;
    if (_phase != 'playing') return;

    final hand = _handOf(me);
    final month = GoStopCards.monthOf(cardId);

    // 흔들기: 같은 달 3장 보유 + 아직 흔들기 미선언 → 확인.
    var state = _freshState();
    if (month != 0 && GoStopLogic.canShake(hand, month) && _shakenOf(me) == 0) {
      final shake = await _confirmShake(month);
      if (!mounted) return;
      if (shake == true) {
        state = GoStopLogic.declareShake(state, me, month);
      }
    }

    if (!widget.session.isMyTurn(widget.room)) return;

    final result = GoStopLogic.playHandCard(state, me, cardId);
    final opp = _opponentId;

    // 추가 턴(폭탄)·고스톱 대기면 차례 유지, 아니면 상대.
    final keepTurn = result.extraTurn || result.canGoStop;
    final nextTurn = keepTurn ? me : (opp ?? me);

    widget.session.submit(result.state, nextTurn: nextTurn);
  }

  Future<void> _onBomb(String me, int month) async {
    if (!widget.session.isMyTurn(widget.room)) return;
    if (_phase != 'playing') return;
    final state = _freshState();
    final result = GoStopLogic.playBomb(state, me, month);
    // 폭탄은 항상 추가 진행(같은 플레이어).
    widget.session.submit(result.state, nextTurn: me);
  }

  // ---- 고/스톱 다이얼로그 --------------------------------------------------

  /// awaitingGoStop 상태이고 내 차례면 고/스톱 다이얼로그를 띄운다.
  void _maybeShowGoStop() {
    if (_phase != 'awaitingGoStop') return;
    final me = _me;
    if (_awaitingGoStop != me) return;
    if (!widget.session.isMyTurn(widget.room)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showGoStopDialog(me);
    });
  }

  Future<void> _showGoStopDialog(String me) async {
    if (_goStopDialogOpen) return;
    _goStopDialogOpen = true;
    final myCap = _capturedOf(me);
    final base = GoStopLogic.scoreOf(myCap).total;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('고 / 스톱'),
        content: Text('현재 $base점입니다.\n계속 진행(고)하거나 멈추고 승리(스톱)를 선택하세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('go'),
            child: const Text('고 (계속)'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('stop'),
            child: const Text('스톱 (승리)'),
          ),
        ],
      ),
    );
    _goStopDialogOpen = false;
    if (!mounted) return;
    if (choice == 'go') {
      _onGo(me);
    } else if (choice == 'stop') {
      _onStop(me);
    }
  }

  bool _goStopDialogOpen = false;

  void _onGo(String me) {
    if (!widget.session.isMyTurn(widget.room)) return;
    final state = GoStopLogic.declareGo(_freshState(), me);
    // 고(Go)는 '멈추지 않고 계속 진행'. 고를 부른 쪽은 이미 이번 턴 카드를 냈으므로
    // 턴은 상대에게 넘어간다(GOSTOP_RULES 5장). me 로 유지하면 온라인 교착/핫시트
    // 연속 플레이 + 고박 역전 불가가 된다.
    final opp = _opponentId;
    widget.session.submit(state, nextTurn: opp ?? me);
  }

  void _onStop(String me) {
    if (!widget.session.isMyTurn(widget.room)) return;
    final myCap = _capturedOf(me);
    final opp = _opponentId;
    final oppCap = opp != null ? _capturedOf(opp) : <int>[];
    final base = GoStopLogic.scoreOf(myCap).total;

    final finalScore = GoStopLogic.finalizeScore(
      base,
      goCount: _goOf(me),
      shakenCount: _shakenOf(me),
      bombCount: _bombOf(me),
      nagariMult: (_state['nagariMult'] as num?)?.toInt() ?? 1,
      pibak: GoStopLogic.isPibak(myCap, oppCap),
      gwangbak: GoStopLogic.isGwangbak(myCap, oppCap),
      gobak: opp != null && _goOf(opp) > 0,
    );

    final state = GoStopLogic.declareStop(_freshState(), me);
    state['roundScore'] = finalScore;
    state['winnerId'] = me;
    widget.session.submit(state, status: RoomStatus.finished, winner: me);
  }

  // ---- 가림막 / 결과 오버레이 ----------------------------------------------

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
            const Text(
              '기기를 넘겨받은 뒤 시작하세요. 손패가 가려져 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() => _curtain = false),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('화면 확인 (기기를 넘겨받았어요)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultOverlay(BuildContext context) {
    final me = _me;
    final isNagari = _state['nagari'] == true || widget.room.winner == 'draw';
    final winnerId = (_state['winnerId'] as String?) ?? widget.room.winner;
    final iWon = winnerId == me;
    final roundScore = (_state['roundScore'] as num?)?.toInt() ?? 0;

    final String title;
    final Color color;
    final IconData icon;
    if (isNagari) {
      title = '나가리 (무승부)';
      color = G42Colors.warn;
      icon = Icons.handshake_rounded;
    } else if (widget.session.hotseat) {
      title = '${_nameOf(winnerId ?? '')} 승리!';
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
        color: Colors.black.withValues(alpha: 0.74),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: G42Colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: color),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  if (!isNagari) ...[
                    const SizedBox(height: 10),
                    Text(
                      '획득 점수 $roundScore점',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (winnerId != null) _scoreBreakdown(winnerId),
                  ],
                  if (isNagari) ...[
                    const SizedBox(height: 10),
                    Text(
                      '다음 판 점수 ×${(_state['nagariMult'] as num?)?.toInt() ?? 2}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 20),
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
      ),
    );
  }

  /// 승자 점수 분해(광/띠/열끗/피/고/박/흔들기).
  Widget _scoreBreakdown(String winnerId) {
    final cap = _capturedOf(winnerId);
    final score = GoStopLogic.scoreOf(cap);
    final opp = widget.room.opponentOf(winnerId)?.id;
    final oppCap = opp != null ? _capturedOf(opp) : <int>[];
    final go = _goOf(winnerId);
    final shaken = _shakenOf(winnerId);
    final bomb = _bombOf(winnerId);
    final pibak = GoStopLogic.isPibak(cap, oppCap);
    final gwangbak = GoStopLogic.isGwangbak(cap, oppCap);
    final gobak = opp != null && _goOf(opp) > 0;

    final rows = <String>[
      if (score.gwangScore > 0) '광 ${score.gwangScore}점',
      if (score.ribbonScore > 0) '띠 ${score.ribbonScore}점',
      if (score.animalScore > 0) '열끗 ${score.animalScore}점',
      if (score.junkScore > 0) '피 ${score.junkScore}점',
      if (go > 0) '$go고',
      if (shaken > 0) '흔들기 ×${1 << shaken}',
      if (bomb > 0) '폭탄 ×${1 << bomb}',
      if (pibak) '피박 ×2',
      if (gwangbak) '광박 ×2',
      if (gobak) '고박 ×2',
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: G42Colors.surfaceHi,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            '점수 분해',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [for (final r in rows) _badge(r, G42Colors.accent)],
          ),
        ],
      ),
    );
  }

  void _onRematch() {
    final isNagari = _state['nagari'] == true || widget.room.winner == 'draw';
    final ids = widget.room.playerIds;

    final fresh = widget.createInitialState(ids);

    final String first;
    if (isNagari) {
      // 나가리: 선 유지 + 누적 배수 반영.
      first = widget.room.turn ?? widget.firstTurn(ids);
      final carried = (_state['nagariMult'] as num?)?.toInt() ?? 2;
      fresh['nagariMult'] = carried;
    } else {
      // 이긴 사람이 다음 선.
      final winnerId = (_state['winnerId'] as String?) ?? widget.room.winner;
      first = (winnerId != null && winnerId.isNotEmpty)
          ? winnerId
          : widget.firstTurn(ids);
    }

    setState(() {
      _curtain = false;
      _lastActor = null;
      _shownEvent = null;
      _autoActionInFlight = false;
      _recordInFlight = false;
      _goStopDialogOpen = false;
    });

    widget.session.rematch(fresh, first);
  }

  // ---- 공통 위젯 / 헬퍼 -----------------------------------------------------

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Future<bool?> _confirmShake(int month) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('흔들기'),
        content: Text(
          '$month월 같은 달 3장을 보유 중입니다.\n흔들기를 선언하면 이 판 최종 점수가 ×2 됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('그냥 내기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('흔들기 선언'),
          ),
        ],
      ),
    );
  }

  /// 최신 room.state를 복제(통째 submit 베이스).
  Map<String, dynamic> _freshState() {
    final s = _state;
    return <String, dynamic>{
      'phase': s['phase'] ?? 'playing',
      'floor': _intList(s['floor']),
      'stock': _intList(s['stock']),
      'hands': _cloneIntListMap(s['hands']),
      'captured': _cloneIntListMap(s['captured']),
      'scores': _cloneIntMap(s['scores']),
      'go': _cloneIntMap(s['go']),
      'shaken': _cloneIntMap(s['shaken']),
      'bomb': _cloneIntMap(s['bomb']),
      'ppeokCount': _cloneIntMap(s['ppeokCount']),
      'nagariMult': (s['nagariMult'] as num?)?.toInt() ?? 1,
      'firstTurn': s['firstTurn'] ?? false,
      'awaitingGoStop': s['awaitingGoStop'] ?? '',
      'lastEvent': s['lastEvent'] ?? GoStopLogic.evNone,
      if (s.containsKey('winner')) 'winner': s['winner'],
      if (s.containsKey('winnerId')) 'winnerId': s['winnerId'],
      if (s.containsKey('roundScore')) 'roundScore': s['roundScore'],
      if (s.containsKey('nagari')) 'nagari': s['nagari'],
      if (s.containsKey('recorded')) 'recorded': s['recorded'],
    };
  }

  Map<String, List<int>> _cloneIntListMap(dynamic raw) {
    final out = <String, List<int>>{};
    if (raw is Map) {
      raw.forEach((k, v) => out['$k'] = _intList(v));
    }
    return out;
  }

  Map<String, int> _cloneIntMap(dynamic raw) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) out['$k'] = v.toInt();
      });
    }
    return out;
  }

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
