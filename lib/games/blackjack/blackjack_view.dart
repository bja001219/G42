import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'blackjack_logic.dart';

/// 블랙잭 메인 인게임 위젯 (정식 룰 + 칩 베팅, 딜러 교대 방식).
///
/// 동기화 상태는 [room.state]에서만 읽고, 베팅 슬라이더·가림막 같은 임시 상태만
/// 로컬 State에 둔다. state는 항상 최신 room.state를 복제해 통째로 submit 한다.
class BlackjackView extends StatefulWidget {
  final GameSession session;
  final Room room;
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  const BlackjackView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
  });

  @override
  State<BlackjackView> createState() => _BlackjackViewState();
}

class _BlackjackViewState extends State<BlackjackView> {
  /// 핫시트: 정보 은닉 가림막(베팅 플레이어가 바뀔 때 기기 전달용).
  bool _curtain = false;

  /// 핫시트: 차례 전환 감지용.
  String? _lastActor;

  /// 진행 중 베팅 금액(로컬 임시 상태).
  int _betAmount = 10;

  @override
  void initState() {
    super.initState();
    _lastActor = widget.room.turn;
  }

  @override
  void didUpdateWidget(covariant BlackjackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRaiseCurtainOnTurnChange();
  }

  /// 핫시트에서 새 라운드(베팅 단계)로 넘어가며 베팅 플레이어가 바뀌면 가림막을 올린다.
  void _maybeRaiseCurtainOnTurnChange() {
    if (!widget.session.hotseat) return;
    final actor = widget.room.turn;
    final changed = actor != null && _lastActor != null && actor != _lastActor;
    if (changed && _phase == 'bet') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _curtain = true);
      });
    }
    _lastActor = actor;
  }

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  Map<String, dynamic> get _state => widget.room.state;
  String get _phase => (_state['phase'] as String?) ?? 'bet';
  int get _roundNo => (_state['roundNo'] as int?) ?? 1;
  bool get _split => (_state['split'] as bool?) ?? false;
  int get _activeHand => (_state['activeHand'] as int?) ?? 0;
  int get _bet0 => (_state['bet0'] as int?) ?? 0;
  int get _bet1 => (_state['bet1'] as int?) ?? 0;
  int get _lastDelta => (_state['lastDelta'] as int?) ?? 0;

  String get _me => widget.session.actingPlayerId(widget.room);

  String get _dealerId {
    final d = _state['dealer'] as String?;
    if (d != null && d.isNotEmpty) return d;
    final ids = widget.room.playerIds;
    return ids.length > 1 ? ids[1] : (ids.isNotEmpty ? ids.first : '');
  }

  String get _bettorId {
    for (final p in widget.room.playerIds) {
      if (p != _dealerId) return p;
    }
    final ids = widget.room.playerIds;
    return ids.isNotEmpty ? ids.first : '';
  }

  List<int> _handOf(String pid) {
    final hands = _state['hands'] as Map?;
    final raw = hands?[pid] as List?;
    return raw == null ? <int>[] : raw.map((e) => e as int).toList();
  }

  List<int> get _splitHand {
    final raw = _state['splitHand'] as List?;
    return raw == null ? <int>[] : raw.map((e) => e as int).toList();
  }

  int _chipsOf(String pid) {
    final chips = _state['chips'] as Map?;
    return (chips?[pid] as int?) ?? 0;
  }

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  /// 이번 라운드 한 사람이 잃거나 딜러가 (1배) 지급할 수 있는 한도.
  /// 더블다운/스플릿(내추럴 보너스 없음)의 커버 판정에 쓴다.
  int get _coverage {
    final b = _chipsOf(_bettorId);
    final d = _chipsOf(_dealerId);
    return b < d ? b : d;
  }

  /// 최초 베팅 상한. 내추럴 블랙잭 3:2(=floor(bet*3/2))까지 딜러가 반드시
  /// 지급할 수 있도록 (bet*3)~/2 <= dealerChips 를 만족하는 최대 bet 으로 제한한다.
  /// → bet <= floor((2*dealerChips+1)/3), 그리고 내 칩 한도.
  int get _maxBet {
    final b = _chipsOf(_bettorId);
    final d = _chipsOf(_dealerId);
    if (b <= 0 || d <= 0) return 0;
    final coverNatural = (2 * d + 1) ~/ 3; // d>=1 이면 항상 >=1.
    return b < coverNatural ? b : coverNatural;
  }

  /// 현재 라운드에 이미 걸린 총 칩(스플릿/더블 포함).
  int get _currentWager => _bet0 + (_split ? _bet1 : 0);

  /// 최신 room.state 복제(통째로 submit 하기 위한 베이스).
  Map<String, dynamic> _freshState() {
    final s = _state;
    final deck = (s['deck'] as List?)?.map((e) => e as int).toList() ?? <int>[];
    final hands = <String, dynamic>{};
    final srcHands = s['hands'] as Map? ?? {};
    for (final entry in srcHands.entries) {
      hands[entry.key as String] = (entry.value as List)
          .map((e) => e as int)
          .toList();
    }
    final chips = <String, dynamic>{};
    final srcChips = s['chips'] as Map? ?? {};
    for (final entry in srcChips.entries) {
      chips[entry.key as String] = entry.value as int;
    }
    return {
      'deck': deck,
      'ptr': (s['ptr'] as int?) ?? deck.length,
      'chips': chips,
      'hands': hands,
      'splitHand':
          (s['splitHand'] as List?)?.map((e) => e as int).toList() ?? <int>[],
      'dealer': (s['dealer'] as String?) ?? _dealerId,
      'phase': (s['phase'] as String?) ?? 'bet',
      'bet0': (s['bet0'] as int?) ?? 0,
      'bet1': (s['bet1'] as int?) ?? 0,
      'split': (s['split'] as bool?) ?? false,
      'activeHand': (s['activeHand'] as int?) ?? 0,
      'roundNo': (s['roundNo'] as int?) ?? 1,
      'lastDelta': (s['lastDelta'] as int?) ?? 0,
    };
  }

  // ---- 빌드 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final finished = room.status == RoomStatus.finished;

    final showCurtain =
        !finished &&
        widget.session.hotseat &&
        _curtain &&
        (_phase == 'bet' || _phase == 'player');
    if (showCurtain) return _curtainScreen(context);

    // Determine which bottom control panel to show.
    Widget? controls;
    if (!finished) {
      if (_phase == 'bet' && _canAct()) {
        controls = _betPanel();
      } else if (_phase == 'player' && _canAct()) {
        controls = _actionButtons();
      } else if (_phase == 'reveal') {
        controls = _revealArea();
      }
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Fixed top: score + turn banner ──
        _scoreBar(),
        const SizedBox(height: 4),
        _turnBanner(finished),
        const SizedBox(height: 4),
        // ── Flexible middle: card table ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _handsArea(finished, constraints);
            },
          ),
        ),
        // ── Fixed bottom: controls ──
        if (controls != null) ...[const SizedBox(height: 4), controls],
      ],
    );

    if (!finished) return content;
    return Stack(children: [content, _resultOverlay(context)]);
  }

  // ---- 액션 게이팅 ----------------------------------------------------------

  bool _canAct() {
    if (widget.room.status == RoomStatus.finished) return false;
    if (_phase != 'bet' && _phase != 'player') return false;
    if (!widget.session.isMyTurn(widget.room)) return false;
    return _me == _bettorId;
  }

  /// 현재 활성 손패(스플릿 시 activeHand 기준).
  List<int> get _activeHandCards =>
      _activeHand == 1 ? _splitHand : _handOf(_bettorId);

  // ---- 베팅 / 딜 ------------------------------------------------------------

  void _onDeal() {
    if (!_canAct() || _phase != 'bet') return;
    final maxBet = _maxBet;
    if (maxBet <= 0) return;
    final bet = _betAmount.clamp(1, maxBet);

    var state = _freshState();
    var deck = (state['deck'] as List).cast<int>();
    var ptr = state['ptr'] as int;

    // 카드가 부족하면 새 덱으로 교체(라운드 시작 시점).
    if (ptr > deck.length - 25) {
      deck = BlackjackLogic.shuffledDeck();
      ptr = 0;
      state['deck'] = deck;
    }

    final bettor = _bettorId;
    final dealer = _dealerId;
    final bettorHand = <int>[];
    final dealerHand = <int>[];
    // 플레이어, 딜러, 플레이어, 딜러 순으로 2장씩.
    bettorHand.add(deck[ptr++]);
    dealerHand.add(deck[ptr++]);
    bettorHand.add(deck[ptr++]);
    dealerHand.add(deck[ptr++]);

    final hands = state['hands'] as Map<String, dynamic>;
    hands[bettor] = bettorHand;
    hands[dealer] = dealerHand;
    state['ptr'] = ptr;
    state['bet0'] = bet;
    state['bet1'] = 0;
    state['split'] = false;
    state['splitHand'] = <int>[];
    state['activeHand'] = 0;

    // 즉시 내추럴 판정(둘 중 하나라도 내추럴이면 플레이어 단계 없이 정산).
    final pN = BlackjackLogic.isNaturalBlackjack(bettorHand);
    final dN = BlackjackLogic.isNaturalBlackjack(dealerHand);
    if (pN || dN) {
      _settleAndFinishRound(state, dealerDraws: false);
      return;
    }
    state['phase'] = 'player';
    widget.session.submit(state, nextTurn: bettor);
  }

  // ---- 플레이어 액션 --------------------------------------------------------

  void _onHit() {
    if (!_canAct() || _phase != 'player') return;
    final state = _freshState();
    final deck = (state['deck'] as List).cast<int>();
    var ptr = state['ptr'] as int;
    if (ptr >= deck.length) {
      _toast('덱이 소진되었습니다');
      return;
    }
    final hand = _writableActiveHand(state);
    hand.add(deck[ptr++]);
    state['ptr'] = ptr;
    _storeActiveHand(state, hand);

    if (BlackjackLogic.isBust(hand)) {
      _advanceActiveHand(state);
    } else {
      widget.session.submit(state, nextTurn: _bettorId);
    }
  }

  void _onStand() {
    if (!_canAct() || _phase != 'player') return;
    final state = _freshState();
    _advanceActiveHand(state);
  }

  void _onDouble() {
    if (!_canAct() || _phase != 'player') return;
    final hand = _activeHandCards;
    if (!BlackjackLogic.canDouble(hand)) return;
    final activeBet = _activeHand == 1 ? _bet1 : _bet0;
    if (_currentWager + activeBet > _coverage) return; // 칩 커버 불가.

    final state = _freshState();
    final deck = (state['deck'] as List).cast<int>();
    var ptr = state['ptr'] as int;
    if (ptr >= deck.length) {
      _toast('덱이 소진되었습니다');
      return;
    }
    // 베팅 2배.
    if (_activeHand == 1) {
      state['bet1'] = (state['bet1'] as int) * 2;
    } else {
      state['bet0'] = (state['bet0'] as int) * 2;
    }
    // 정확히 한 장 받고 손패 종료.
    final h = _writableActiveHand(state);
    h.add(deck[ptr++]);
    state['ptr'] = ptr;
    _storeActiveHand(state, h);
    _advanceActiveHand(state);
  }

  void _onSplit() {
    if (!_canAct() || _phase != 'player') return;
    if (_split || _activeHand != 0) return;
    final hand = _handOf(_bettorId);
    if (!BlackjackLogic.canSplit(hand)) return;
    if (_bet0 * 2 > _coverage) return; // 두 번째 손패 베팅 커버 불가.

    final state = _freshState();
    final deck = (state['deck'] as List).cast<int>();
    var ptr = state['ptr'] as int;
    if (ptr > deck.length - 2) {
      _toast('덱이 소진되었습니다');
      return;
    }
    final bettor = _bettorId;
    final isAces = BlackjackLogic.isAcePair(hand);

    final hand0 = <int>[hand[0], deck[ptr++]];
    final hand1 = <int>[hand[1], deck[ptr++]];
    (state['hands'] as Map<String, dynamic>)[bettor] = hand0;
    state['splitHand'] = hand1;
    state['split'] = true;
    state['bet1'] = state['bet0'];
    state['ptr'] = ptr;
    state['activeHand'] = 0;

    if (isAces) {
      // 에이스 스플릿: 각 손패 한 장씩만 받고 즉시 정산.
      _settleAndFinishRound(state, dealerDraws: true);
      return;
    }
    widget.session.submit(state, nextTurn: bettor);
  }

  /// 활성 손패를 종료하고 다음(스플릿 두 번째) 또는 딜러 정산으로 넘어간다.
  void _advanceActiveHand(Map<String, dynamic> state) {
    final split = state['split'] as bool;
    final active = state['activeHand'] as int;
    if (split && active == 0) {
      state['activeHand'] = 1;
      widget.session.submit(state, nextTurn: _bettorId);
    } else {
      _settleAndFinishRound(state, dealerDraws: true);
    }
  }

  // ---- 딜러 진행 + 정산 -----------------------------------------------------

  void _settleAndFinishRound(
    Map<String, dynamic> state, {
    required bool dealerDraws,
  }) {
    final bettor = _bettorId;
    final dealer = _dealerId;
    final hands = state['hands'] as Map<String, dynamic>;
    final hand0 = (hands[bettor] as List).cast<int>();
    final split = state['split'] as bool;
    final splitHand = (state['splitHand'] as List).cast<int>();
    var dealerHand = (hands[dealer] as List).cast<int>();

    // 살아있는 플레이어 손패가 하나라도 있으면 딜러가 진행한다.
    final anyAlive =
        !BlackjackLogic.isBust(hand0) ||
        (split && !BlackjackLogic.isBust(splitHand));
    if (dealerDraws && anyAlive) {
      final deck = (state['deck'] as List).cast<int>();
      final ptr = state['ptr'] as int;
      final res = BlackjackLogic.playDealer(deck, ptr, dealerHand);
      dealerHand = res.hand;
      hands[dealer] = dealerHand;
      state['ptr'] = res.ptr;
    }

    final delta = BlackjackLogic.settleRound(
      hand0: hand0,
      splitHand: split ? splitHand : null,
      dealerHand: dealerHand,
      bet0: state['bet0'] as int,
      bet1: state['bet1'] as int,
      split: split,
    );

    // 제로섬 + 음수 방지 클램프 적용.
    final chips = state['chips'] as Map<String, dynamic>;
    final applied = _applyDelta(chips, bettor, dealer, delta);
    state['lastDelta'] = applied;
    state['phase'] = 'reveal';

    final bettorChips = chips[bettor] as int;
    final dealerChips = chips[dealer] as int;
    if (bettorChips <= 0 || dealerChips <= 0) {
      final matchWinner = bettorChips > 0 ? bettor : dealer;
      widget.session.submit(
        state,
        status: RoomStatus.finished,
        winner: matchWinner,
      );
    } else {
      // reveal 단계: 호스트가 '다음 라운드'를 주도한다.
      widget.session.submit(state, nextTurn: widget.room.playerIds.first);
    }
  }

  /// 칩 증감을 제로섬으로 적용하되 음수가 되지 않도록 클램프. 실제 적용된 증감 반환.
  int _applyDelta(
    Map<String, dynamic> chips,
    String bettor,
    String dealer,
    int delta,
  ) {
    final b = chips[bettor] as int;
    final d = chips[dealer] as int;
    final t = BlackjackLogic.clampTransfer(
      delta: delta,
      playerChips: b,
      dealerChips: d,
    );
    chips[bettor] = b + t;
    chips[dealer] = d - t;
    return t;
  }

  // ---- 손패 쓰기 헬퍼 -------------------------------------------------------

  List<int> _writableActiveHand(Map<String, dynamic> state) {
    final active = state['activeHand'] as int;
    if (active == 1) return List<int>.from(state['splitHand'] as List);
    return List<int>.from(
      (state['hands'] as Map<String, dynamic>)[_bettorId] as List,
    );
  }

  void _storeActiveHand(Map<String, dynamic> state, List<int> hand) {
    final active = state['activeHand'] as int;
    if (active == 1) {
      state['splitHand'] = hand;
    } else {
      (state['hands'] as Map<String, dynamic>)[_bettorId] = hand;
    }
  }

  // ---- 다음 라운드 / 재대국 -------------------------------------------------

  void _onNextRound() {
    final ids = widget.room.playerIds;
    final state = _freshState();

    // 딜러 교대: 이번 라운드의 베팅 플레이어가 다음 라운드 딜러.
    final newDealer = _bettorId;
    final newBettor = _dealerId;

    var deck = (state['deck'] as List).cast<int>();
    var ptr = state['ptr'] as int;
    if (ptr > deck.length - 25) {
      deck = BlackjackLogic.shuffledDeck();
      ptr = 0;
      state['deck'] = deck;
    }
    state['ptr'] = ptr;

    final hands = state['hands'] as Map<String, dynamic>;
    for (final pid in ids) {
      hands[pid] = <int>[];
    }
    state['splitHand'] = <int>[];
    state['dealer'] = newDealer;
    state['phase'] = 'bet';
    state['bet0'] = 0;
    state['bet1'] = 0;
    state['split'] = false;
    state['activeHand'] = 0;
    state['roundNo'] = ((state['roundNo'] as int?) ?? 1) + 1;
    state['lastDelta'] = 0;

    widget.session.submit(state, nextTurn: newBettor);
    if (widget.session.hotseat) {
      setState(() {
        _curtain = true;
        _lastActor = newBettor;
      });
    }
  }

  void _onRematch() {
    setState(() {
      _curtain = false;
      _lastActor = null;
      _betAmount = 10;
    });
    widget.session.rematch(
      widget.createInitialState(widget.room.playerIds),
      widget.firstTurn(widget.room.playerIds),
    );
  }

  // ---- 위젯 조각: 스코어/칩 바 ----------------------------------------------

  Widget _scoreBar() {
    final ids = widget.room.playerIds;
    final a = ids.isNotEmpty ? ids[0] : '';
    final b = ids.length > 1 ? ids[1] : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Row(
        children: [
          _chipPill(a, G42Colors.accent),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_roundNo라운드',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Text(
                '칩 0이면 종료',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _chipPill(b, G42Colors.warn),
        ],
      ),
    );
  }

  Widget _chipPill(String pid, Color color) {
    if (pid.isEmpty) return const Expanded(child: SizedBox.shrink());
    final isDealer = pid == _dealerId;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _nameOf(pid),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.album_rounded, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                '${_chipsOf(pid)}',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (isDealer ? G42Colors.warn : G42Colors.good).withValues(
                alpha: 0.18,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isDealer ? '딜러' : '플레이어',
              style: TextStyle(
                color: isDealer ? G42Colors.warn : G42Colors.good,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 위젯 조각: 안내 배너 -------------------------------------------------

  Widget _turnBanner(bool finished) {
    if (finished) return const SizedBox.shrink();

    if (_phase == 'reveal') {
      final delta = _lastDelta;
      final String label;
      final Color color;
      final IconData icon;
      if (delta == 0) {
        label = '이번 라운드 무승부 (push) — 베팅 환수';
        color = G42Colors.warn;
        icon = Icons.handshake_rounded;
      } else {
        final winner = delta > 0 ? _bettorId : _dealerId;
        label = '${_nameOf(winner)} 라운드 승! (칩 ${delta.abs()} 이동)';
        color = G42Colors.good;
        icon = Icons.emoji_events_rounded;
      }
      return _bannerBox(label, color, icon, true);
    }

    final myTurn = widget.session.isMyTurn(widget.room) && _me == _bettorId;
    final String label;
    if (_phase == 'bet') {
      label = widget.session.hotseat
          ? '${_nameOf(_bettorId)} 베팅'
          : (myTurn ? '베팅하세요' : '${_nameOf(_bettorId)} 베팅 중 — 대기');
    } else {
      label = widget.session.hotseat
          ? '${_nameOf(_bettorId)} 차례'
          : (myTurn ? '내 차례 — Hit/Stand/Double/Split' : '상대 차례 — 대기 중');
    }
    final color =
        (_bettorId ==
            (widget.room.playerIds.isNotEmpty
                ? widget.room.playerIds.first
                : ''))
        ? G42Colors.accent
        : G42Colors.warn;
    return _bannerBox(
      label,
      myTurn ? color : G42Colors.surfaceHi,
      myTurn ? Icons.touch_app_rounded : Icons.hourglass_empty_rounded,
      myTurn,
    );
  }

  Widget _bannerBox(String label, Color color, IconData icon, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.20) : G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? color : G42Colors.surfaceHi,
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: active ? color : Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 위젯 조각: 손패 영역 -------------------------------------------------

  /// The card table area. Receives bounded [constraints] from LayoutBuilder
  /// so card sizes can adapt. Never scrolls — fits within the Expanded region.
  Widget _handsArea(bool finished, BoxConstraints constraints) {
    final reveal = _phase == 'reveal' || finished;
    final dealer = _dealerId;
    final bettor = _bettorId;

    // 딜러의 홀 카드: reveal 전이며 보는 사람이 딜러 본인이 아니면 가린다.
    final hideDealerHole = !reveal && _me != dealer;
    final dealerHand = _handOf(dealer);

    // Distribute available height across panels.
    // With split: 3 panels; without: 2 panels.
    final hasSplit = _split;
    final panelCount = hasSplit ? 3 : 2;
    // Each panel gets an equal share of the available height.
    final spacing = 6.0;
    final totalSpacing = spacing * (panelCount - 1);
    final panelHeight = ((constraints.maxHeight - totalSpacing) / panelCount)
        .clamp(60.0, double.infinity);

    // Card size: fit ~5 cards side-by-side in width with some overlap margin,
    // and height = width * 1.4, clamped so it fits in the panel.
    final availableWidth = constraints.maxWidth;
    // Each panel has 12px padding on each side, so inner width is narrower.
    final innerWidth = availableWidth - 24;
    // Card width: aim to show 5 cards without overlap on inner width.
    // Use 1/6 of inner width so there's always space even with many cards.
    final cardW = (innerWidth / 6).clamp(28.0, 46.0);
    final cardH = (cardW * 1.4).clamp(38.0, 64.0);

    return Column(
      children: [
        // 딜러 영역.
        _handPanel(
          title: '딜러 · ${_nameOf(dealer)}',
          isMe: _me == dealer,
          cards: dealerHand,
          hiddenFrom: hideDealerHole ? 1 : dealerHand.length,
          showTotal: !hideDealerHole && dealerHand.isNotEmpty,
          highlight: false,
          active: false,
          panelHeight: panelHeight,
          cardW: cardW,
          cardH: cardH,
        ),
        SizedBox(height: spacing),
        // 플레이어 영역(스플릿이면 두 손패).
        _handPanel(
          title: _split
              ? '플레이어 · ${_nameOf(bettor)} (손패 1)'
              : '플레이어 · ${_nameOf(bettor)}',
          isMe: _me == bettor,
          cards: _handOf(bettor),
          hiddenFrom: 99,
          showTotal: _handOf(bettor).isNotEmpty,
          highlight: !reveal && _phase == 'player' && _activeHand == 0,
          active: _split && _activeHand == 0,
          betLabel: _handOf(bettor).isNotEmpty ? '베팅 $_bet0' : null,
          panelHeight: panelHeight,
          cardW: cardW,
          cardH: cardH,
        ),
        if (hasSplit) ...[
          SizedBox(height: spacing),
          _handPanel(
            title: '플레이어 · ${_nameOf(bettor)} (손패 2)',
            isMe: _me == bettor,
            cards: _splitHand,
            hiddenFrom: 99,
            showTotal: _splitHand.isNotEmpty,
            highlight: !reveal && _phase == 'player' && _activeHand == 1,
            active: _activeHand == 1,
            betLabel: '베팅 $_bet1',
            panelHeight: panelHeight,
            cardW: cardW,
            cardH: cardH,
          ),
        ],
      ],
    );
  }

  Widget _handPanel({
    required String title,
    required bool isMe,
    required List<int> cards,
    required int hiddenFrom,
    required bool showTotal,
    required bool highlight,
    required bool active,
    required double panelHeight,
    required double cardW,
    required double cardH,
    String? betLabel,
  }) {
    final total = BlackjackLogic.handTotal(cards);
    final bust = BlackjackLogic.isBust(cards);
    final natural = BlackjackLogic.isNaturalBlackjack(cards);
    final soft = BlackjackLogic.isSoft(cards) && !bust;

    final Color borderColor;
    if (active || highlight) {
      borderColor = G42Colors.accent;
    } else if (bust) {
      borderColor = G42Colors.bad;
    } else {
      borderColor = G42Colors.surfaceHi;
    }

    // Height of the header row area (title + badge).
    const headerH = 22.0;

    return SizedBox(
      height: panelHeight,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: G42Colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: (active || highlight) ? 2 : 1,
          ),
        ),
        // 카드 영역은 Expanded 로 남는 높이를 흡수한다(고정 산술의 0px 슬랙으로
        // 인한 소수점 오버플로우를 원천 차단). 패널은 항상 panelHeight 에 꼭 맞는다.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            // Header row.
            SizedBox(
              height: headerH,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    const Text(
                      '(나)',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                  const Spacer(),
                  if (showTotal)
                    _totalBadge(total, bust, natural, soft)
                  else
                    const Text(
                      '?',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Card strip — Expanded 가 남는 높이를 채우고, 카드 부채는 그 안에서
            // 본래 높이(cardH)로 좌측 정렬된다. 패널이 작아도 오버플로우 없음.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: cards.isEmpty
                    ? const Text(
                        '대기 중',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      )
                    : _cardFan(cards, hiddenFrom, cardW, cardH),
              ),
            ),
            if (betLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                betLabel,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Renders cards as a horizontal overlapping fan so they always fit in one
  /// row regardless of how many cards are in the hand.
  Widget _cardFan(List<int> cards, int hiddenFrom, double cardW, double cardH) {
    const maxVisible = 10;
    final count = cards.length.clamp(0, maxVisible);
    // The overlap step: if we have many cards, shrink the step so they all fit.
    // With 2 cards, step = cardW (no overlap). With 10 cards, overlap more.
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        // Step between cards: allow overlap but keep at least 8px visible per card.
        final minStep = 8.0;
        final naturalStep = cardW + 4;
        final maxStepForAll = count > 1
            ? ((availW - cardW) / (count - 1)).clamp(minStep, naturalStep)
            : naturalStep;
        final step = maxStepForAll;
        final totalW = count > 0 ? cardW + step * (count - 1) : 0.0;
        return SizedBox(
          width: totalW,
          height: cardH,
          child: Stack(
            children: [
              for (var i = 0; i < count; i++)
                Positioned(
                  left: i * step,
                  top: 0,
                  child: i >= hiddenFrom
                      ? _faceDownCard(cardW, cardH)
                      : _cardChip(cards[i], cardW, cardH),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _totalBadge(int total, bool bust, bool natural, bool soft) {
    final Color color;
    final String text;
    if (natural) {
      color = G42Colors.good;
      text = 'BLACKJACK';
    } else if (bust) {
      color = G42Colors.bad;
      text = '버스트 $total';
    } else {
      color = G42Colors.accent;
      text = soft ? '$total (소프트)' : '$total';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _cardChip(int card, double w, double h) {
    final red = BlackjackLogic.isRed(card);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Center(
        child: Text(
          BlackjackLogic.label(card),
          style: TextStyle(
            color: red ? const Color(0xFFD63031) : const Color(0xFF1A1B2E),
            fontWeight: FontWeight.w800,
            fontSize: (w * 0.33).clamp(9.0, 15.0),
          ),
        ),
      ),
    );
  }

  Widget _faceDownCard(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: G42Colors.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: G42Colors.accent.withValues(alpha: 0.5)),
      ),
      child: const Center(
        child: Icon(
          Icons.help_outline_rounded,
          color: Colors.white38,
          size: 14,
        ),
      ),
    );
  }

  // ---- 위젯 조각: 베팅 패널 -------------------------------------------------

  Widget _betPanel() {
    final maxBet = _maxBet;
    if (maxBet <= 0) return const SizedBox.shrink();
    final amount = _betAmount.clamp(1, maxBet);
    if (amount != _betAmount) {
      // 빌드 중 직접 setState 금지 → 다음 프레임에 보정.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _betAmount = amount);
      });
    }

    void setBet(int v) => setState(() => _betAmount = v.clamp(1, maxBet));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.album_rounded,
                color: G42Colors.accent,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '$amount 칩',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                ' / 최대 $maxBet',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: amount > 1 ? () => setBet(amount - 5) : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: Slider(
                  value: amount.toDouble(),
                  min: 1,
                  max: maxBet.toDouble(),
                  divisions: maxBet > 1 ? maxBet - 1 : null,
                  label: '$amount',
                  onChanged: (v) => setBet(v.round()),
                ),
              ),
              IconButton(
                onPressed: amount < maxBet ? () => setBet(amount + 5) : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          Row(
            children: [
              for (final v in [10, 25, 50])
                if (v <= maxBet) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setBet(v),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text('$v', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setBet(maxBet),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('최대', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: _onDeal,
              icon: const Icon(Icons.casino_rounded, size: 16),
              label: Text('$amount 베팅하고 딜'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 위젯 조각: 플레이어 액션 버튼 ----------------------------------------

  Widget _actionButtons() {
    final hand = _activeHandCards;
    final activeBet = _activeHand == 1 ? _bet1 : _bet0;
    final canDouble =
        BlackjackLogic.canDouble(hand) &&
        (_currentWager + activeBet) <= _coverage;
    final canSplit =
        !_split &&
        _activeHand == 0 &&
        BlackjackLogic.canSplit(_handOf(_bettorId)) &&
        (_bet0 * 2) <= _coverage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: FilledButton.icon(
                  onPressed: _onHit,
                  icon: const Icon(Icons.add_card_rounded, size: 16),
                  label: const Text('Hit'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: _onStand,
                  icon: const Icon(Icons.front_hand_rounded, size: 16),
                  label: const Text('Stand'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (canDouble || canSplit) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: canDouble ? _onDouble : null,
                    icon: const Icon(Icons.exposure_plus_2_rounded, size: 14),
                    label: const Text('더블다운', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: canSplit ? _onSplit : null,
                    icon: const Icon(Icons.call_split_rounded, size: 14),
                    label: const Text('스플릿', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---- 위젯 조각: reveal(다음 라운드) ---------------------------------------

  Widget _revealArea() {
    final ids = widget.room.playerIds;
    final host = ids.isNotEmpty ? ids.first : '';
    final iAmHost = widget.session.hotseat || widget.session.myPlayerId == host;

    if (!iAmHost) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '다음 라운드를 기다리는 중...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: FilledButton.icon(
        onPressed: _onNextRound,
        icon: const Icon(Icons.skip_next_rounded, size: 16),
        label: const Text('다음 라운드'),
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
    );
  }

  // ---- 가림막 / 결과 오버레이 -----------------------------------------------

  Widget _curtainScreen(BuildContext context) {
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
              '${_nameOf(_bettorId)} 차례',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '기기를 넘겨받았다면 카드를 확인하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() => _curtain = false),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('내 카드 확인'),
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
        ? '${_nameOf(ids[0])} ${_chipsOf(ids[0])}칩 · ${_nameOf(ids[1])} ${_chipsOf(ids[1])}칩'
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
                const SizedBox(height: 8),
                const Text(
                  '상대 칩을 모두 획득했습니다',
                  style: TextStyle(color: Colors.white70),
                ),
                if (scoreLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    scoreLine,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
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
