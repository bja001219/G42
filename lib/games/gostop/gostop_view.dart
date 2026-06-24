import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'gostop_anim.dart';
import 'gostop_card_widget.dart';
import 'gostop_cards.dart';
import 'gostop_geometry.dart';
import 'gostop_logic.dart';

/// 고스톱(2인 맞고) 메인 인게임 위젯 — 고정 전체화면 세로 테이블.
///
/// ## 아키텍처 (스펙 §C)
/// - **상태 커밋은 즉시**: 탭 → `playHandCard` → `session.submit` 을 곧바로 호출한다.
///   애니메이션 뒤로 submit 을 미루지 않는다(온라인 정합성 + `pumpAndSettle` 호환).
/// - **표시 상태(displayed) ≠ 권위 상태(authoritative)**: 권위 상태가 바뀌면
///   (내 수든 상대 수든) `lastMove`(+diff)로 안무를 만들어 displayed 를 new 로
///   모핑한 뒤 스냅한다. 내 수/상대 수 **동일 경로**.
/// - **연출 중 입력 잠금**(`_animating`). submit 은 이미 끝났으니 추가 탭 방지용.
/// - **핫시트 커튼은 연출 후**. `awaitingGoStop` 이면 커튼 대신 고/스톱 패널.
/// - **컨트롤러 기반**(타이머 금지). 모든 컨트롤러 `dispose`.
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

class _GoStopViewState extends State<GoStopView> with TickerProviderStateMixin {
  // ── 핫시트 / 자동 처리 플래그 (기존 동작 유지) ──
  bool _curtain = false;
  String? _lastActor;
  bool _autoActionInFlight = false;

  // ── 표시 상태(displayed) — 연출 동안 권위 상태와 분리 ──
  /// 현재 화면에 그려지는 상태(연출 중엔 직전 수 기준으로 모핑).
  Map<String, dynamic>? _displayedState;

  /// `_displayedState` 가 반영한 moveSeq.
  int _displayedSeq = -1;

  // ── 안무(코스메틱) ──
  AnimationController? _moveCtrl;
  GoStopMoveAnim? _currentMove;
  bool _animating = false;

  /// 핫시트에서 내 수 연출이 끝난 뒤 커튼을 올려야 하는가(연출 후 커튼).
  bool _pendingCurtain = false;

  // ── 콜아웃 ──
  AnimationController? _calloutCtrl;
  GoStopCallout? _callout;

  // ====================================================================
  // 상태 접근 헬퍼 (권위 상태 = room.state)
  // ====================================================================

  Map<String, dynamic> get _state => widget.room.state;

  /// 화면 렌더 기준 상태(연출 중엔 displayed, 아니면 권위).
  Map<String, dynamic> get _view => _displayedState ?? _state;

  String get _phase => (_state['phase'] as String?) ?? 'playing';

  String get _me => widget.session.actingPlayerId(widget.room);

  String? get _opponentId => widget.session.opponentOf(widget.room, _me)?.id;

  List<int> _handOf(Map<String, dynamic> st, String pid) =>
      _intList((st['hands'] as Map?)?[pid]);

  List<int> _capturedOf(Map<String, dynamic> st, String pid) =>
      _intList((st['captured'] as Map?)?[pid]);

  List<int> _floorOf(Map<String, dynamic> st) => _intList(st['floor']);

  List<int> _stockOf(Map<String, dynamic> st) => _intList(st['stock']);

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

  int get _authSeq => (_state['moveSeq'] as num?)?.toInt() ?? 0;

  List<int> _intList(dynamic raw) {
    if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
    return <int>[];
  }

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  // ====================================================================
  // 생애주기
  // ====================================================================

  @override
  void initState() {
    super.initState();
    _lastActor = widget.session.hotseat ? widget.room.turn : null;
    _displayedState = _deepCloneState(_state);
    _displayedSeq = _authSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeHandleChongtong();
      _maybeAutoFinalize();
    });
  }

  @override
  void didUpdateWidget(covariant GoStopView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 권위 상태가 바뀌었으면(새 수) 안무를 시작하거나, 변화가 없으면 동기화.
    // 직전 위젯의 권위 상태(= 이 수가 적용되기 전 보드)를 안무 베이스로 넘긴다
    // (H2: 연출 중 다음 수가 도착해도 항상 올바른 pre-move 보드에서 출발).
    _syncDisplayedToAuthoritative(oldWidget.room.state);
    _maybeRaiseCurtainOnTurnChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeHandleChongtong();
      _maybeAutoFinalize();
    });
  }

  @override
  void dispose() {
    _moveCtrl?.dispose();
    _calloutCtrl?.dispose();
    super.dispose();
  }

  // ====================================================================
  // 표시 상태 ↔ 권위 상태 동기화 + 안무 트리거 (§C 원칙 2)
  // ====================================================================

  /// 권위 상태(room.state)와 표시 상태를 비교해, 새 카드 수가 있으면 안무를 재생,
  /// 아니면(비-카드수: go/stop/shake/finished 등) 즉시 동기화한다.
  ///
  /// [prevAuthState] 는 이 수가 적용되기 직전의 권위 보드(= didUpdateWidget 의
  /// oldWidget.room.state). 안무의 pre-move 베이스로 쓴다(H2). null 이면(초기화 등)
  /// `_displayedState` 를 베이스로 한다.
  void _syncDisplayedToAuthoritative([Map<String, dynamic>? prevAuthState]) {
    final authSeq = _authSeq;

    // 종료 상태면 즉시 스냅(결과 오버레이로 전환).
    if (widget.room.status == RoomStatus.finished) {
      // M1: 상대가 '스톱'으로 끝냈으면 스톱! 콜아웃(내 스톱은 _onStop 에서 이미 처리).
      _maybeCalloutOpponentStop(prevAuthState);
      _snapToAuthoritative();
      return;
    }

    // 이미 같은 seq 를 표시 중이면 비-카드수 변화만 반영(go/shake 등) → 스냅.
    if (authSeq == _displayedSeq) {
      // 손패/바닥/먹은패는 동일하지만 go/awaitingGoStop/shaken 등이 바뀔 수 있으므로
      // 연출 중이 아니면 displayed 를 권위로 맞추고, 상대의 비-카드수 선언
      // (고/스톱/흔들기)이면 콜아웃을 띄운다(M1). 연출 중이면 같은 seq 의
      // 중복/에코(C1) 이므로 안무를 재시작하지 않고 무시한다.
      if (!_animating) {
        _maybeCalloutNonCardChange(prevAuthState);
        _snapToAuthoritative();
      }
      return;
    }

    // 새 카드 수 발생. lastMove 로 안무 명세를 만든다.
    final move = GoStopMoveAnim.fromLastMove(_state['lastMove']);
    if (move == null) {
      // 메타 없음(예: 직접 상태 주입) → 안무 없이 스냅.
      _snapToAuthoritative();
      return;
    }

    _startMoveAnim(move, authSeq, prevAuthState);
  }

  /// displayed 를 권위 상태로 즉시 맞춘다(연출 없이).
  void _snapToAuthoritative() {
    _displayedState = _deepCloneState(_state);
    _displayedSeq = _authSeq;
  }

  /// M1: 비-카드수 변화(고/흔들기)를 직전 권위 상태와 비교해, **상대**의 선언이면
  /// 콜아웃을 띄운다. 내 선언은 [_onGo]/[_onPlayHandCard](흔들기)에서 이미 띄우므로
  /// 상대(카운트가 증가한 주체가 내가 아님)일 때만 띄워 이중 발사를 막는다.
  void _maybeCalloutNonCardChange(Map<String, dynamic>? prevAuthState) {
    if (prevAuthState == null) return;
    // 핫시트는 한 기기에서 직접 선언하므로 _onGo/흔들기에서 이미 콜아웃을 띄운다.
    // 여기서 또 띄우면 이중 발사가 되므로 온라인(비-핫시트)만 처리한다.
    if (widget.session.hotseat) return;
    final opp = _opponentId;
    if (opp == null) return;

    int prevInt(String key, String pid) {
      final m = prevAuthState[key];
      if (m is Map && m[pid] is num) return (m[pid] as num).toInt();
      return 0;
    }

    // 고: 상대 go 카운트 증가.
    if (_goOf(opp) > prevInt('go', opp)) {
      _showCallout(GoStopCallout.go);
      GoStopHaptics.heavy();
      return;
    }
    // 흔들기: 상대 shaken 카운트 증가.
    if (_shakenOf(opp) > prevInt('shaken', opp)) {
      _showCallout(GoStopCallout.shake);
      GoStopHaptics.heavy();
    }
  }

  /// M1: 상대가 '스톱'으로 판을 끝냈으면 스톱! 콜아웃. 직전 phase 가
  /// 'awaitingGoStop' 인 경우만(고/스톱 결정 지점) → 총통/3뻑/나가리와 구분.
  void _maybeCalloutOpponentStop(Map<String, dynamic>? prevAuthState) {
    if (prevAuthState == null) return;
    if (widget.session.hotseat) return; // 핫시트는 결과 오버레이로 직행.
    if (prevAuthState['phase'] != 'awaitingGoStop') return;
    if (_state['nagari'] == true || widget.room.winner == 'draw') return;
    final winnerId = (_state['winnerId'] as String?) ?? widget.room.winner;
    if (winnerId == null || winnerId.isEmpty) return;
    // 내가 이긴(=내가 스톱한) 경우는 _onStop 에서 별도 처리하지 않으므로 콜아웃
    // 자체를 띄우지 않는다(결과 오버레이로 즉시 전환). 상대 스톱만 안내.
    if (winnerId == _me) return;
    _showCallout(GoStopCallout.stop);
    GoStopHaptics.heavy();
  }

  /// 한 수 안무를 시작한다(내 수/상대 수 동일 경로).
  ///
  /// [prevAuthState] 가 있으면 그 보드(= 이 수 직전 권위 보드)를 베이스로 삼는다.
  /// 연출 중 다음 수가 도착해도(H2) 반-모핑된 `_displayedState` 가 아니라 항상
  /// 올바른 pre-move 보드에서 출발하도록 보장한다.
  void _startMoveAnim(
    GoStopMoveAnim move,
    int authSeq, [
    Map<String, dynamic>? prevAuthState,
  ]) {
    _moveCtrl?.dispose();
    _currentMove = move;
    _animating = true;
    // C1: 같은 seq 의 중복/에코 rebuild 가 안무를 재시작하지 않도록 즉시 전진.
    _displayedSeq = authSeq;

    // displayed 는 "직전 수" 보드에서 출발하되, 낸 손패는 즉시 손에서 뺀다
    // (손패에서 빠져나와 바닥으로 비행하는 모션을 위해). pre-move 보드는
    // 직전 권위 상태(prevAuthState)를 우선 사용한다(H2/H3: 바닥의 먹힌 카드가
    // 실제로 존재해 캡처 스윕이 빈 공간이 아니라 진짜 무더기에서 출발).
    final base = prevAuthState != null
        ? _deepCloneState(prevAuthState)
        : (_displayedState ?? _deepCloneState(_state));
    _removePlayedFromHand(base, move);
    _displayedState = base;

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: GoStopAnimTimings.totalMoveMs),
    );
    _moveCtrl = ctrl;

    // 단계 진입 시 햅틱(연출 분기). status/listener 기반(타이머 금지).
    var firedHandSnap = false;
    var firedFlip = false;
    ctrl.addListener(() {
      final t = ctrl.value;
      if (!firedHandSnap && t >= GoStopAnimTimings.handSlideEnd) {
        firedHandSnap = true;
        if (move.handMatched) {
          GoStopHaptics.matchSnap();
        } else if (move.handToFloor) {
          GoStopHaptics.drop();
        }
      }
      if (!firedFlip &&
          move.flippedCard >= 0 &&
          t >= GoStopAnimTimings.suspenseEnd) {
        firedFlip = true;
        if (move.flipMatched) {
          GoStopHaptics.matchSnap();
        } else if (move.flipToFloor) {
          GoStopHaptics.drop();
        }
      }
    });

    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onMoveAnimDone();
      }
    });

    // 이벤트 콜아웃(병렬 오버레이).
    _maybeStartCallout(move.event);

    ctrl.forward();
    setState(() {});
  }

  void _onMoveAnimDone() {
    if (!mounted) return;
    setState(() {
      _animating = false;
      _currentMove = null;
      _snapToAuthoritative();
      // 내 수 연출이 끝났으면(핫시트) 이제 커튼을 올린다(§C 원칙 4).
      if (_pendingCurtain && _awaitingGoStop.isEmpty) {
        _pendingCurtain = false;
        if (widget.session.hotseat &&
            widget.room.status != RoomStatus.finished) {
          _curtain = true;
        }
      } else {
        _pendingCurtain = false;
      }
    });
    // H1: 연출 도중 미뤘던 종료 전이(총통/3뻑/나가리)를 연출 완료 후 처리한다.
    // 라운드를 끝내는 수였다면 여기서 finished state 가 submit 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeHandleChongtong();
      _maybeAutoFinalize();
    });
  }

  /// displayed 손패에서 낸 카드(폭탄이면 3장)를 제거한다.
  void _removePlayedFromHand(Map<String, dynamic> st, GoStopMoveAnim move) {
    final hands = st['hands'];
    if (hands is! Map) return;
    final hand = _intList(hands[move.actor]);
    if (move.bombCards.isNotEmpty) {
      for (final c in move.bombCards) {
        hand.remove(c);
      }
    } else {
      hand.remove(move.playedCard);
    }
    hands[move.actor] = hand;
  }

  void _maybeStartCallout(String event) {
    final callout = GoStopCallout.forEvent(event);
    if (callout == null) return;
    GoStopHaptics.forEvent(event);
    _showCallout(callout);
  }

  void _showCallout(GoStopCallout callout) {
    _calloutCtrl?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds:
            GoStopAnimTimings.calloutInMs +
            GoStopAnimTimings.calloutHoldMs +
            GoStopAnimTimings.calloutOutMs,
      ),
    );
    _calloutCtrl = ctrl;
    _callout = callout;
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _callout = null);
      }
    });
    ctrl.forward();
  }

  // ====================================================================
  // 핫시트 커튼 (연출 후) — 기존 동작 유지
  // ====================================================================

  void _maybeRaiseCurtainOnTurnChange() {
    if (!widget.session.hotseat) return;
    if (widget.room.status == RoomStatus.finished) return;
    final actor = widget.room.turn;
    if (actor != null && _lastActor != null && actor != _lastActor) {
      // 연출 중이면 연출 후 올린다(§C 원칙 4). 아니면 다음 프레임에 올린다.
      if (_animating) {
        _pendingCurtain = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _awaitingGoStop.isEmpty) {
            setState(() => _curtain = true);
          }
        });
      }
    }
    _lastActor = actor;
  }

  // ====================================================================
  // 자동 처리: 총통 / 나가리 / 3뻑 / 전적기록 (기존 로직 유지)
  // ====================================================================

  void _maybeHandleChongtong() {
    if (_phase != 'playing') return;
    if (widget.room.status == RoomStatus.finished) return;
    if (_autoActionInFlight) return;
    // H1: 연출 중에는 종료 전이를 미룬다(연출 완료 후 _onMoveAnimDone 에서 재시도).
    if (_animating) return;
    final me = _me;
    if (!widget.session.isMyTurn(widget.room)) return;
    final month = GoStopLogic.checkChongtong(_handOf(_state, me));
    if (month == null) return;
    _autoActionInFlight = true;
    GoStopHaptics.heavy();
    final state = _freshState();
    state['phase'] = 'finished';
    state['winner'] = me;
    state['lastEvent'] = GoStopLogic.evChongtong;
    final score = GoStopLogic.finalizeScore(
      10,
      nagariMult: (state['nagariMult'] as num?)?.toInt() ?? 1,
    );
    state['roundScore'] = score;
    state['winnerId'] = me;
    widget.session.submit(state, status: RoomStatus.finished, winner: me);
  }

  void _maybeAutoFinalize() {
    // 라운드 종료(승부/나가리/총통/3뻑) 전적 기록은 GameHostScreen 이 게임 무관하게
    // 중앙에서 1회 수행한다. 여기서는 결과 state(winnerId/roundScore/nagari)만 세팅하고
    // 기록은 하지 않는다(중복 방지).
    if (widget.room.status == RoomStatus.finished) return;
    if (_autoActionInFlight) return;
    // H1: 진행 중 종료 전이(총통/3뻑/나가리)는 연출이 끝난 뒤 처리한다.
    // 연출 도중 finished state 를 submit 하면 진행 중인 한 수 연출이 끊긴다.
    // 연출 완료 시 _onMoveAnimDone 에서 다시 호출되어 라운드를 마무리한다.
    if (_animating) return;

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

  // ====================================================================
  // 빌드
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    final finished = widget.room.status == RoomStatus.finished;

    // 핫시트 커튼(연출 후에만 올라옴).
    if (!finished && _curtain && widget.session.hotseat) {
      return _woodFrame(_curtainScreen(context));
    }

    // 고/스톱은 하단 패널(_goStopPanel)에서 직접 처리한다(다이얼로그 폐기).

    return _woodFrame(
      LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geo = GoStopGeometry(size);
          final table = _buildTable(context, geo, finished);
          if (!finished) return table;
          return Stack(children: [table, _resultOverlay(context)]);
        },
      ),
    );
  }

  /// 진녹색 펠트 배경 + 좌우 우드 프레임(§E). 흰 배경 금지.
  Widget _woodFrame(Widget child) {
    return ColoredBox(
      color: const Color(0xFF1B0E03), // 우드 프레임 바깥(짙은 갈색).
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            // 진녹색 펠트.
            gradient: const RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [Color(0xFF1E6B3A), Color(0xFF0E3D20)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3D1C00), width: 8),
            boxShadow: const [
              BoxShadow(color: Color(0x88000000), blurRadius: 8),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: child,
          ),
        ),
      ),
    );
  }

  // ====================================================================
  // 테이블 (단일 풀스크린 Stack + Positioned, §C 원칙 6)
  // ====================================================================

  Widget _buildTable(BuildContext context, GoStopGeometry geo, bool finished) {
    final me = _me;
    final opp = _opponentId;
    final view = _view;

    final myTurn = widget.session.isMyTurn(widget.room) && !finished;
    final myCapAuth = _capturedOf(_state, me);
    final oppCapAuth = opp != null ? _capturedOf(_state, opp) : <int>[];
    final myScore = GoStopLogic.scoreOf(myCapAuth);
    final oppScore = opp != null ? GoStopLogic.scoreOf(oppCapAuth) : null;

    final children = <Widget>[];

    // ── 존 구분 배경(미묘한 라인) ──
    children.add(_zoneDivider(geo));

    // ── 상대 프로필 / 점수 / 고 ──
    children.add(_profileBar(geo.opponentZone, opp, oppScore, true));

    // ── 내 프로필 / 점수 / 고 ──
    children.add(_profileBar(geo.myZone, me, myScore, false));

    // ── 상대 손패(뒷면 부채) ──
    final oppHand = opp != null ? _handOf(view, opp) : <int>[];
    children.addAll(_opponentHandCards(geo, oppHand.length));

    // ── 먹은 패(분류별 줄) — 권위 상태 기준(연출 끝 후 스냅) ──
    children.addAll(_capturedCards(geo, _capturedOf(view, me), true));
    if (opp != null) {
      children.addAll(_capturedCards(geo, _capturedOf(view, opp), false));
    }

    // ── 중앙: 더미 + 바닥 군집 ──
    children.addAll(_floorAndDeck(geo, view, me));

    // ── 내 손패(앞면 부채, ✧ 마커) ──
    children.addAll(_myHandCards(geo, view, me, myTurn));

    // ── 비행 카드(안무) ──
    if (_animating && _currentMove != null && _moveCtrl != null) {
      children.addAll(_flyingCards(geo, _currentMove!, _moveCtrl!));
    }

    // ── 하단 액션 밴드: 폭탄 버튼 / 고·스톱 패널 ──
    if (!finished) {
      final panel = _bottomBand(geo, me, view, myTurn);
      if (panel != null) children.add(panel);
    }

    // ── 콜아웃(가운데 큰 배너) ──
    if (_callout != null && _calloutCtrl != null) {
      children.add(_calloutPositioned(geo));
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _zoneDivider(GoStopGeometry geo) {
    return Positioned.fill(
      child: IgnorePointer(child: CustomPaint(painter: _FeltPainter(geo))),
    );
  }

  // ── 프로필 바(아바타/이름/점수/고) ──

  Widget _profileBar(
    Rect zone,
    String? pid,
    GoStopScore? score,
    bool isOpponent,
  ) {
    final go = pid != null ? _goOf(pid) : 0;
    final name = pid != null ? _nameOf(pid) : (isOpponent ? '상대' : '나');
    final total = score?.total ?? 0;
    final accent = isOpponent ? G42Colors.bad : G42Colors.good;

    // 상대는 존 최상단, 나는 존 최하단(아바타 좌측).
    final top = isOpponent ? zone.top + 2 : zone.bottom - 30;
    return Positioned(
      left: zone.left + 2,
      right: zone.left + 2,
      top: top,
      height: 28,
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: accent.withValues(alpha: 0.3),
            child: Icon(
              isOpponent ? Icons.person_outline_rounded : Icons.person_rounded,
              size: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (go > 0) _badge('$go고', G42Colors.warn),
          const SizedBox(width: 4),
          _scorePill(total, accent),
        ],
      ),
    );
  }

  Widget _scorePill(int total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xCC10241A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$total점',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  // ── 상대 손패(뒷면) ──

  List<Widget> _opponentHandCards(GoStopGeometry geo, int count) {
    if (count <= 0) return const [];
    final band = geo.opponentHandBand;
    final cw = geo.cardWidth * 0.7;
    final ch = cw / GoStopCardWidget.aspect;
    final cy = band.center.dy;
    final step = math.min(cw * 0.55, (band.width - cw) / math.max(1, count));
    final totalW = step * (count - 1) + cw;
    final startX = band.center.dx - totalW / 2;
    final out = <Widget>[];
    for (var i = 0; i < count; i++) {
      out.add(
        Positioned(
          left: startX + i * step,
          top: cy - ch / 2,
          child: GoStopCardWidget(cardId: 0, faceDown: true, width: cw),
        ),
      );
    }
    return out;
  }

  // ── 먹은 패(분류별 겹친 줄, §I) ──

  List<Widget> _capturedCards(GoStopGeometry geo, List<int> cap, bool mine) {
    if (cap.isEmpty) return const [];
    final cw = geo.cardWidth * (mine ? 0.62 : 0.5);
    final ch = cw / GoStopCardWidget.aspect;
    final out = <Widget>[];

    final groups = <GoStopGroup, List<int>>{
      GoStopGroup.gwang: cap.where(GoStopCards.isGwang).toList(),
      GoStopGroup.animal: cap.where(GoStopCards.isAnimal).toList(),
      GoStopGroup.ribbon: cap.where(GoStopCards.isRibbon).toList(),
      GoStopGroup.junk: cap.where(GoStopCards.isJunk).toList(),
    };

    groups.forEach((group, ids) {
      for (var i = 0; i < ids.length; i++) {
        final slot = geo.capturedSlot(group, i, mine);
        out.add(
          Positioned(
            left: slot.dx - cw / 2,
            top: slot.dy - ch / 2,
            child: GoStopCardWidget(cardId: ids[i], width: cw),
          ),
        );
      }
    });
    return out;
  }

  // ── 중앙: 더미 + 바닥 군집(같은 달 겹침, §F) ──

  List<Widget> _floorAndDeck(
    GoStopGeometry geo,
    Map<String, dynamic> view,
    String me,
  ) {
    final out = <Widget>[];
    final floor = _floorOf(view);
    final stock = _stockOf(view);
    final cw = geo.cardWidth;
    final ch = cw / GoStopCardWidget.aspect;

    // 손패에 짝(같은 달 바닥패)이 있는 달 집합 — ✧ 마커/하이라이트용.
    final myHand = _handOf(view, me);
    final matchMonths = <int>{};
    for (final c in myHand) {
      final m = GoStopCards.monthOf(c);
      if (m == 0) continue;
      if (floor.any((f) => GoStopCards.monthOf(f) == m)) matchMonths.add(m);
    }

    // 더미(정중앙) 뒷면 스택 + ×N 배지.
    final deck = geo.deckCenter;
    // 두께감을 주는 그림자 스택(최대 3겹).
    final depth = math.min(3, (stock.length / 6).ceil());
    for (var d = depth; d >= 1; d--) {
      out.add(
        Positioned(
          left: deck.dx - cw / 2 + d * 1.5,
          top: deck.dy - ch / 2 + d * 1.5,
          child: GoStopCardWidget(cardId: 0, faceDown: true, width: cw),
        ),
      );
    }
    out.add(
      Positioned(
        left: deck.dx - cw / 2,
        top: deck.dy - ch / 2,
        child: GoStopCardWidget(cardId: 0, faceDown: true, width: cw),
      ),
    );
    // ×N 잔량 배지(더미 위).
    out.add(
      Positioned(
        left: deck.dx - cw / 2,
        top: deck.dy + ch / 2 - 16,
        width: cw,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xDD000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD4AF37), width: 1),
            ),
            child: Text(
              '×${stock.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFFE082),
              ),
            ),
          ),
        ),
      ),
    );

    // 바닥패: 월별 앵커 + 같은 달 겹침. 연출로 캡처/낙하 중인 카드는 제외한다.
    final hidden = _hiddenFloorDuringAnim();
    final present = _presentMonths(floor);
    final perMonthIndex = <int, int>{};
    for (final id in floor) {
      if (hidden.contains(id)) continue;
      final month = GoStopCards.monthOf(id);
      final idx = perMonthIndex[month] ?? 0;
      perMonthIndex[month] = idx + 1;
      final anchor = geo.floorAnchor(month, present);
      final off = geo.stackOffset(idx);
      final glow = matchMonths.contains(month);
      out.add(
        Positioned(
          left: anchor.dx + off.dx - cw / 2,
          top: anchor.dy + off.dy - ch / 2,
          child: GoStopCardWidget(cardId: id, width: cw, glow: glow),
        ),
      );
    }

    return out;
  }

  /// 바닥에 존재하는 월 목록(정렬·중복 제거) — 앵커 결정용.
  List<int> _presentMonths(List<int> floor) {
    final s = <int>{};
    for (final id in floor) {
      final m = GoStopCards.monthOf(id);
      if (m != 0) s.add(m);
    }
    final list = s.toList()..sort();
    return list;
  }

  /// 연출 중 바닥에서 잠시 숨길 카드(비행 카드와 중복 렌더 방지).
  Set<int> _hiddenFloorDuringAnim() {
    final move = _currentMove;
    if (!_animating || move == null) return const {};
    // 손패 단계/뒤집기 단계가 먹은 카드(캡처 비행 중)는 바닥에서 숨긴다.
    return {...move.handCaptured, ...move.flipCaptured};
  }

  // ── 내 손패(앞면 부채, ✧ 마커) ──

  List<Widget> _myHandCards(
    GoStopGeometry geo,
    Map<String, dynamic> view,
    String me,
    bool myTurn,
  ) {
    final hand = _handOf(view, me);
    if (hand.isEmpty) return const [];
    final floor = _floorOf(view);
    final cw = geo.cardWidth;
    final ch = cw / GoStopCardWidget.aspect;
    final n = hand.length;

    // 결정적 정렬(월 → id)로 부채를 안정화.
    final sorted = List<int>.from(hand)
      ..sort((a, b) {
        final ma = GoStopCards.monthOf(a);
        final mb = GoStopCards.monthOf(b);
        return ma != mb ? ma.compareTo(mb) : a.compareTo(b);
      });

    final out = <Widget>[];
    for (var i = 0; i < n; i++) {
      final id = sorted[i];
      final slot = geo.handSlot(i, n);
      final month = GoStopCards.monthOf(id);
      final hasMatch =
          month != 0 && floor.any((f) => GoStopCards.monthOf(f) == month);

      // 카드(회전된 부채). GestureDetector 는 GoStopCardWidget 내부에서 감싼다.
      out.add(
        Positioned(
          left: slot.pos.dx - cw / 2,
          top: slot.pos.dy - ch / 2,
          child: Transform.rotate(
            angle: slot.angle,
            child: GoStopCardWidget(
              key: ValueKey('hand-$id'),
              cardId: id,
              width: cw,
              glow: hasMatch && myTurn,
              onTap: myTurn ? () => _onPlayHandCard(me, id) : null,
            ),
          ),
        ),
      );

      // ✧ 마커(짝 있는 손패) — 카드 상단에 작게.
      if (hasMatch) {
        out.add(
          Positioned(
            left: slot.pos.dx - 7,
            top: slot.pos.dy - ch / 2 - 14,
            child: IgnorePointer(
              child: Text(
                '✧',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFFE082),
                  shadows: [
                    Shadow(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.9),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  // ── 비행 카드(안무): 손패→바닥, 캡처→먹은패, 더미 플립, 붙음/낙하 ──

  List<Widget> _flyingCards(
    GoStopGeometry geo,
    GoStopMoveAnim move,
    AnimationController ctrl,
  ) {
    final cw = geo.cardWidth;
    final ch = cw / GoStopCardWidget.aspect;
    final view = _view;
    final floor = _floorOf(view);
    final present = _presentMonths([
      ...floor,
      ...move.handCaptured,
      ...move.flipCaptured,
    ]);

    Offset monthAnchor(int month) => geo.floorAnchor(month, present);

    // 손패 출발 위치: actor 가 나면 내 손패 밴드 중앙, 상대면 상대 손패 밴드.
    final fromMe = move.actor == _me;
    final handStart = fromMe
        ? Offset(geo.myZone.center.dx, geo.handSlot(0, 1).pos.dy)
        : geo.opponentHandBand.center;

    final playedMonth = GoStopCards.monthOf(move.playedCard);
    final capturedBand = geo.capturedSlot(GoStopGroup.junk, 0, fromMe);

    return [
      AnimatedBuilder(
        key: const ValueKey('gostop-flying'),
        animation: ctrl,
        builder: (context, _) {
          final t = ctrl.value;
          final widgets = <Widget>[];

          // ── 1) 손패 카드 슬라이드(→ 바닥 해당 달) ──
          final handTarget = monthAnchor(playedMonth);
          if (t <= GoStopAnimTimings.handCaptureEnd) {
            final st = (t / GoStopAnimTimings.handSlideEnd).clamp(0.0, 1.0);
            final curved = Curves.fastOutSlowIn.transform(st);
            final pos = Offset.lerp(handStart, handTarget, curved)!;
            // 매치면 elasticOut 스냅 느낌(살짝 오버슈트), 낙하면 easeOut.
            widgets.add(
              _flyCard(move.playedCard, pos, cw, ch, glow: move.handMatched),
            );
          }

          // ── 2) 손패 캡처 스윕(먹은 패로) ──
          if (move.handMatched &&
              t > GoStopAnimTimings.floorHighlightEnd &&
              t <= GoStopAnimTimings.handCaptureEnd) {
            final st =
                ((t - GoStopAnimTimings.floorHighlightEnd) /
                        (GoStopAnimTimings.handCaptureEnd -
                            GoStopAnimTimings.floorHighlightEnd))
                    .clamp(0.0, 1.0);
            final curved = Curves.easeInOut.transform(st);
            for (final id in move.handCaptured) {
              final pos = Offset.lerp(handTarget, capturedBand, curved)!;
              widgets.add(_flyCard(id, pos, cw * 0.7, ch * 0.7, glow: true));
            }
          }

          // ── 3) 더미 플립(3D) + 서스펜스 홀드 ──
          // M4: 렌더 구간을 [handCaptureEnd, suspenseEnd] 로 잡아 회전
          // [handCaptureEnd→deckFlipEnd] 이 실제로 보이게 한다(이후 st=1 로
          // 클램프되어 앞면 정지 = 서스펜스 홀드).
          if (move.flippedCard >= 0 &&
              t > GoStopAnimTimings.handCaptureEnd &&
              t <= GoStopAnimTimings.suspenseEnd) {
            final st =
                ((t - GoStopAnimTimings.handCaptureEnd) /
                        (GoStopAnimTimings.deckFlipEnd -
                            GoStopAnimTimings.handCaptureEnd))
                    .clamp(0.0, 1.0);
            final angle = (1 - st) * math.pi; // π→0 (뒷면→앞면)
            final deck = geo.deckCenter;
            final scale = 1.0 + 0.35 * Curves.easeOut.transform(st);
            widgets.add(
              Positioned(
                left: deck.dx - cw / 2,
                top: deck.dy - ch / 2,
                child: Transform.scale(
                  scale: scale,
                  child: GoStopCardWidget(
                    cardId: move.flippedCard,
                    width: cw,
                    flipAngle: angle,
                  ),
                ),
              ),
            );
          }

          // ── 4) 붙음(매치) vs 낙하(안 붙음) ──
          if (move.flippedCard >= 0 && t > GoStopAnimTimings.suspenseEnd) {
            final deck = geo.deckCenter;
            final flipMonth = GoStopCards.monthOf(move.flippedCard);
            if (move.flipMatched) {
              // 붙음: 대상 무더기로 비행 → elasticOut 스냅 + 글로우.
              if (t <= GoStopAnimTimings.flipSnapEnd) {
                final st =
                    ((t - GoStopAnimTimings.suspenseEnd) /
                            (GoStopAnimTimings.flipSnapEnd -
                                GoStopAnimTimings.suspenseEnd))
                        .clamp(0.0, 1.0);
                final curved = Curves.elasticOut.transform(st);
                final pos = Offset.lerp(deck, monthAnchor(flipMonth), curved)!;
                widgets.add(
                  _flyCard(move.flippedCard, pos, cw, ch, glow: true),
                );
              } else {
                // 캡처 스윕(먹은 패로).
                final st =
                    ((t - GoStopAnimTimings.flipSnapEnd) /
                            (1 - GoStopAnimTimings.flipSnapEnd))
                        .clamp(0.0, 1.0);
                final curved = Curves.easeInOut.transform(st);
                final from = monthAnchor(flipMonth);
                for (final id in move.flipCaptured) {
                  final pos = Offset.lerp(from, capturedBand, curved)!;
                  widgets.add(
                    _flyCard(id, pos, cw * 0.7, ch * 0.7, glow: true),
                  );
                }
              }
            } else if (move.flipToFloor) {
              // 낙하: 빈 바닥 슬롯으로 easeOut 드롭(글로우 없음).
              final st =
                  ((t - GoStopAnimTimings.suspenseEnd) /
                          (1 - GoStopAnimTimings.suspenseEnd))
                      .clamp(0.0, 1.0);
              final curved = Curves.easeOut.transform(st);
              final pos = Offset.lerp(deck, monthAnchor(flipMonth), curved)!;
              widgets.add(_flyCard(move.flippedCard, pos, cw, ch));
            }
          }

          return Stack(clipBehavior: Clip.none, children: widgets);
        },
      ),
    ];
  }

  Widget _flyCard(
    int id,
    Offset center,
    double w,
    double h, {
    bool glow = false,
  }) {
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      child: IgnorePointer(
        child: GoStopCardWidget(cardId: id, width: w, glow: glow),
      ),
    );
  }

  // ── 콜아웃 위치 ──

  Widget _calloutPositioned(GoStopGeometry geo) {
    // L2: 빌드 중 강제 언랩 금지. 로컬로 캡처하고, 빌더 콜백이 나중 프레임에
    // 발사될 때 콜아웃/컨트롤러가 비워졌을 수 있으므로 null-guard 한다.
    final ctrl = _calloutCtrl;
    final callout = _callout;
    if (ctrl == null || callout == null) return const SizedBox.shrink();
    final field = geo.fieldZone;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final current = _callout;
        if (current == null) return const SizedBox.shrink();
        return Positioned(
          left: field.left,
          right: 0,
          top: field.center.dy - 40,
          width: field.width,
          child: Center(
            child: GoStopCalloutBanner(
              callout: current,
              progress: ctrl.value,
              width: field.width,
            ),
          ),
        );
      },
    );
  }

  // ── 하단 밴드: 폭탄 버튼 / 고·스톱 패널 ──

  Widget? _bottomBand(
    GoStopGeometry geo,
    String me,
    Map<String, dynamic> view,
    bool myTurn,
  ) {
    final band = geo.bottomBand;

    // 고/스톱 대기(내 차례)면 큰 패널을 우선 표시.
    if (_phase == 'awaitingGoStop' &&
        _awaitingGoStop == me &&
        widget.session.isMyTurn(widget.room) &&
        !_animating) {
      return Positioned(
        left: band.left,
        right: band.left,
        top: band.top,
        height: band.height,
        child: _goStopPanel(me),
      );
    }

    if (!myTurn || _animating) return null;

    // 폭탄 가능: 손패 같은 달 3장 + 바닥 같은 달 1장.
    final hand = _handOf(view, me);
    final floor = _floorOf(view);
    final bombMonths = <int>{};
    for (var m = 1; m <= 12; m++) {
      final inHand = hand.where((c) => GoStopCards.monthOf(c) == m).length;
      final inFloor = floor.where((c) => GoStopCards.monthOf(c) == m).length;
      if (inHand >= 3 && inFloor >= 1) bombMonths.add(m);
    }
    if (bombMonths.isEmpty) return null;

    return Positioned(
      left: band.left,
      right: band.left,
      top: band.top,
      height: band.height,
      child: Center(
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (final m in bombMonths)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: G42Colors.bad,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                onPressed: () => _onBomb(me, m),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: Text('폭탄 $m월'),
              ),
          ],
        ),
      ),
    );
  }

  /// 고/스톱 큰 버튼 패널(테이블 톤, §H). AlertDialog 대체.
  Widget _goStopPanel(String me) {
    final myCap = _capturedOf(_state, me);
    final base = GoStopLogic.scoreOf(myCap).total;
    final go = _goOf(me);
    // 고 시 예상 가산(다음 고까지 갔을 때의 보너스 가늠).
    final projected = GoStopLogic.finalizeScore(
      base,
      goCount: go + 1,
      shakenCount: _shakenOf(me),
      bombCount: _bombOf(me),
      nagariMult: (_state['nagariMult'] as num?)?.toInt() ?? 1,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEE10241A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 $base점',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '고 진행 시 예상 $projected점',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB0BEC5),
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: G42Colors.good,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => _onGo(me),
            child: const Text(
              '고',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: G42Colors.bad,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => _onStop(me),
            child: const Text(
              '스톱',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // 입력 핸들러 (상태 커밋 즉시, §C 원칙 1)
  // ====================================================================

  Future<void> _onPlayHandCard(String me, int cardId) async {
    if (_animating) return;
    if (!widget.session.isMyTurn(widget.room)) return;
    if (_phase != 'playing') return;

    final hand = _handOf(_state, me);
    final month = GoStopCards.monthOf(cardId);

    var state = _freshState();
    if (month != 0 && GoStopLogic.canShake(hand, month) && _shakenOf(me) == 0) {
      final shake = await _confirmShake(month);
      if (!mounted) return;
      if (shake == true) {
        state = GoStopLogic.declareShake(state, me, month);
        GoStopHaptics.heavy();
        _showCallout(GoStopCallout.shake);
      }
    }

    if (!widget.session.isMyTurn(widget.room)) return;

    GoStopHaptics.play();
    final result = GoStopLogic.playHandCard(state, me, cardId);
    final opp = _opponentId;

    final keepTurn = result.extraTurn || result.canGoStop;
    final nextTurn = keepTurn ? me : (opp ?? me);

    widget.session.submit(result.state, nextTurn: nextTurn);
  }

  Future<void> _onBomb(String me, int month) async {
    if (_animating) return;
    if (!widget.session.isMyTurn(widget.room)) return;
    if (_phase != 'playing') return;
    GoStopHaptics.matchSnap();
    final state = _freshState();
    final result = GoStopLogic.playBomb(state, me, month);
    widget.session.submit(result.state, nextTurn: me);
  }

  // ====================================================================
  // 고 / 스톱
  // ====================================================================

  void _onGo(String me) {
    if (!widget.session.isMyTurn(widget.room)) return;
    GoStopHaptics.heavy();
    _showCallout(GoStopCallout.go);
    final state = GoStopLogic.declareGo(_freshState(), me);
    final opp = _opponentId;
    widget.session.submit(state, nextTurn: opp ?? me);
  }

  void _onStop(String me) {
    if (!widget.session.isMyTurn(widget.room)) return;
    GoStopHaptics.heavy();
    final myCap = _capturedOf(_state, me);
    final opp = _opponentId;
    final oppCap = opp != null ? _capturedOf(_state, opp) : <int>[];
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

  // ====================================================================
  // 가림막 / 결과 오버레이
  // ====================================================================

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
              color: Colors.white70,
            ),
            const SizedBox(height: 20),
            Text(
              '${_nameOf(me)} 차례',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '기기를 넘겨받은 뒤 시작하세요. 손패가 가려져 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
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

  /// 승자 점수 분해(광/띠/열끗/피/고/박/흔들기/폭탄/피박/광박/고박).
  Widget _scoreBreakdown(String winnerId) {
    final cap = _capturedOf(_state, winnerId);
    final score = GoStopLogic.scoreOf(cap);
    final opp = widget.room.opponentOf(winnerId)?.id;
    final oppCap = opp != null ? _capturedOf(_state, opp) : <int>[];
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
      first = widget.room.turn ?? widget.firstTurn(ids);
      final carried = (_state['nagariMult'] as num?)?.toInt() ?? 2;
      fresh['nagariMult'] = carried;
    } else {
      final winnerId = (_state['winnerId'] as String?) ?? widget.room.winner;
      first = (winnerId != null && winnerId.isNotEmpty)
          ? winnerId
          : widget.firstTurn(ids);
    }

    // M3: 컨트롤러를 먼저 dispose+null 처리해 진행 중 안무의 상태 리스너가
    // 리셋 이후 _onMoveAnimDone 을 호출하지 못하게 한다(dispose 는 completed 를
    // 발사하지 않음). 그 다음 setState 로 모든 in-flight 플래그를 끄고 displayed
    // 를 fresh(moveSeq 0, lastMove 없음)로 시드한다. _displayedSeq 를 0 으로
    // 맞추므로, 리매치 state(authSeq 0)가 도착해도 같은 seq 로 스냅되어 직전 판의
    // 묵은 lastMove 가 헛 재생되지 않는다.
    _moveCtrl?.dispose();
    _moveCtrl = null;
    _calloutCtrl?.dispose();
    _calloutCtrl = null;

    setState(() {
      _curtain = false;
      _lastActor = null;
      _autoActionInFlight = false;
      _animating = false;
      _currentMove = null;
      _callout = null;
      _pendingCurtain = false;
      _displayedState = _deepCloneState(fresh);
      _displayedSeq = (fresh['moveSeq'] as num?)?.toInt() ?? 0;
    });

    widget.session.rematch(fresh, first);
  }

  // ====================================================================
  // 공통 위젯 / 헬퍼
  // ====================================================================

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

  /// 최신 room.state(권위)를 복제(통째 submit 베이스). lastMove 는 비-카드수
  /// 경로(go/stop/shake/auto)에 넘기지 않는다(기존 계약 유지).
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
      'moveSeq': (s['moveSeq'] as num?)?.toInt() ?? 0,
      if (s.containsKey('winner')) 'winner': s['winner'],
      if (s.containsKey('winnerId')) 'winnerId': s['winnerId'],
      if (s.containsKey('roundScore')) 'roundScore': s['roundScore'],
      if (s.containsKey('nagari')) 'nagari': s['nagari'],
      if (s.containsKey('recorded')) 'recorded': s['recorded'],
    };
  }

  /// displayed 용 깊은 복제(연출 중 권위와 독립적으로 손패/바닥을 변형하기 위해).
  ///
  /// L3: **렌더 전용**. 안다고 알려진 키만 복제하므로 그 외 키(scores/go·shaken·
  /// bomb 외 메타/winner/winnerId/roundScore/nagari/recorded/lastMove/firstTurn/
  /// ppeokCount/nagariMult 등)는 **누락된다**. 이 결과는 오직 [_displayedState]
  /// (화면 표시)에만 쓰며 **절대 [GameSession.submit] 페이로드로 쓰지 않는다**
  /// (제출은 모든 계약 키를 보존하는 [_freshState] 를 쓴다). 키를 누락한 채
  /// 제출하면 권위 상태가 손상되므로, 제출 경로에 섞지 말 것.
  Map<String, dynamic> _deepCloneState(Map<String, dynamic> s) {
    return <String, dynamic>{
      'phase': s['phase'] ?? 'playing',
      'floor': _intList(s['floor']),
      'stock': _intList(s['stock']),
      'hands': _cloneIntListMap(s['hands']),
      'captured': _cloneIntListMap(s['captured']),
      'go': _cloneIntMap(s['go']),
      'shaken': _cloneIntMap(s['shaken']),
      'bomb': _cloneIntMap(s['bomb']),
      'awaitingGoStop': s['awaitingGoStop'] ?? '',
      'lastEvent': s['lastEvent'] ?? GoStopLogic.evNone,
      'moveSeq': (s['moveSeq'] as num?)?.toInt() ?? 0,
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
}

/// 펠트 위에 존 구분선/중앙 강조를 옅게 그리는 페인터(장식용, hit-test 없음).
class _FeltPainter extends CustomPainter {
  final GoStopGeometry geo;
  const _FeltPainter(this.geo);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    // 상대/필드, 필드/내 경계.
    final field = geo.fieldZone;
    canvas.drawLine(
      Offset(field.left, field.top),
      Offset(field.right, field.top),
      line,
    );
    canvas.drawLine(
      Offset(field.left, field.bottom),
      Offset(field.right, field.bottom),
      line,
    );
    // 중앙 더미 강조 링.
    final ring = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(geo.deckCenter, geo.cardWidth * 0.75, ring);
  }

  @override
  bool shouldRepaint(covariant _FeltPainter oldDelegate) =>
      oldDelegate.geo.size != geo.size;
}
