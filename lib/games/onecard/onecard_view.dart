import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'onecard_logic.dart';

/// 원카드 메인 인게임 위젯.
///
/// 동기화 상태는 [room.state]에서만 읽고, 핫시트 가림막 같은 임시 상태는
/// 로컬 State에 둔다. 수를 둘 때는 항상 최신 state를 복제해 통째로 submit한다.
class OneCardView extends StatefulWidget {
  final GameSession session;
  final Room room;
  final Map<String, dynamic> Function(List<String> playerIds)
  createInitialState;
  final String Function(List<String> playerIds) firstTurn;

  const OneCardView({
    super.key,
    required this.session,
    required this.room,
    required this.createInitialState,
    required this.firstTurn,
  });

  @override
  State<OneCardView> createState() => _OneCardViewState();
}

class _OneCardViewState extends State<OneCardView> {
  /// 핫시트: 정보 은닉 가림막을 띄울지.
  bool _curtain = false;

  /// 핫시트: 마지막으로 본 차례 주체(전환 감지용).
  String? _lastActor;

  final Random _rng = Random();

  // ---- 상태 접근 헬퍼 -------------------------------------------------------

  List<String> get _deck => ((widget.room.state['deck'] as List?) ?? const [])
      .map((e) => e as String)
      .toList();

  String get _discardTop =>
      (widget.room.state['discardTop'] as String?) ?? 'SA';

  String get _activeSuit => (widget.room.state['activeSuit'] as String?) ?? 'S';

  int get _pending => (widget.room.state['pending'] as int?) ?? 0;

  String get _attackKind => (widget.room.state['attackKind'] as String?) ?? '';

  String get _lastAction => (widget.room.state['lastAction'] as String?) ?? '';

  Map<String, dynamic> get _hands =>
      Map<String, dynamic>.from(widget.room.state['hands'] as Map? ?? {});

  List<String> _handOf(String pid) =>
      ((_hands[pid] as List?) ?? const []).map((e) => e as String).toList();

  String get _me => widget.session.actingPlayerId(widget.room);

  String? get _opponentId => widget.session.opponentOf(widget.room, _me)?.id;

  String _nameOf(String pid) => widget.room.playerById(pid)?.name ?? '플레이어';

  // ---- 차례 전환 시 핫시트 가림막 -------------------------------------------

  @override
  void initState() {
    super.initState();
    _lastActor = widget.room.turn;
  }

  @override
  void didUpdateWidget(covariant OneCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRaiseCurtainOnTurnChange();
  }

  void _maybeRaiseCurtainOnTurnChange() {
    if (!widget.session.hotseat) return;
    if (widget.room.status != RoomStatus.playing) return;
    final actor = widget.room.turn;
    if (actor != null && _lastActor != null && actor != _lastActor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _curtain = true);
      });
    }
    _lastActor = actor;
  }

  // ---- 빌드 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final finished = room.status == RoomStatus.finished;

    // 핫시트 가림막 (숨김정보: 손패).
    if (!finished && _curtain && widget.session.hotseat) {
      return _curtainScreen(context);
    }

    final content = _buildTable(context, finished: finished);
    if (!finished) return content;
    return Stack(children: [content, _resultOverlay(context)]);
  }

  Widget _buildTable(BuildContext context, {required bool finished}) {
    final me = _me;
    final opp = _opponentId;
    final myHand = _handOf(me);
    final oppCount = opp != null ? _handOf(opp).length : 0;
    final myTurn = widget.session.isMyTurn(widget.room) && !finished;

    final playable = OneCardLogic.playableCards(
      myHand,
      topCard: _discardTop,
      activeSuit: _activeSuit,
      pending: _pending,
      attackKind: _attackKind,
    );
    final canPlayAny = playable.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _turnBanner(myTurn, finished),
          const SizedBox(height: 6),
          _opponentRow(opp, oppCount),
          const SizedBox(height: 6),
          Expanded(child: Center(child: _discardArea())),
          const SizedBox(height: 6),
          _drawRow(myTurn: myTurn, canPlayAny: canPlayAny),
          const SizedBox(height: 6),
          _myHandLabel(myHand.length, playable.length),
          const SizedBox(height: 4),
          _myHand(myHand, playable, myTurn),
          const SizedBox(height: 4),
          _helpButton(context),
        ],
      ),
    );
  }

  // ---- 차례 배너 ------------------------------------------------------------

  Widget _turnBanner(bool myTurn, bool finished) {
    if (finished) return const SizedBox.shrink();
    final me = _me;
    final seat = widget.session.seatIndex(widget.room, me);
    final color = seat == 0 ? G42Colors.accent : G42Colors.warn;

    final base = widget.session.hotseat
        ? '${_nameOf(me)} 차례'
        : (myTurn ? '내 차례' : '상대 차례 — 대기 중');

    final extra = _pending > 0
        ? '  ·  공격 누적 $_pending장!'
        : (_lastAction.isNotEmpty ? '  ·  $_lastAction' : '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (myTurn ? color : G42Colors.surface).withValues(
          alpha: myTurn ? 0.22 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _pending > 0
              ? G42Colors.bad
              : (myTurn ? color : G42Colors.surfaceHi),
          width: (myTurn || _pending > 0) ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _pending > 0
                ? Icons.bolt_rounded
                : (myTurn
                      ? Icons.play_arrow_rounded
                      : Icons.hourglass_empty_rounded),
            color: _pending > 0
                ? G42Colors.bad
                : (myTurn ? color : Colors.white54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$base$extra',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: myTurn || _pending > 0 ? Colors.white : Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 상대 손패(장수만) ----------------------------------------------------

  Widget _opponentRow(String? opp, int count) {
    final name = opp != null ? _nameOf(opp) : '상대';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: G42Colors.surfaceHi),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_rounded, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name 손패',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // 뒷면 카드 미니 표현.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < (count > 6 ? 6 : count); i++)
                Container(
                  width: 14,
                  height: 20,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: G42Colors.accent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '$count장',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 버린 더미 + 현재 무늬 -------------------------------------------------

  Widget _discardArea() {
    final top = _discardTop;
    final activeSuit = _activeSuit;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cardFace(top, big: true),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('현재 무늬', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  OneCardLogic.suitSymbol(activeSuit),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _suitColor(activeSuit),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  OneCardLogic.suitName(activeSuit),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---- 드로우 버튼 ----------------------------------------------------------

  Widget _drawRow({required bool myTurn, required bool canPlayAny}) {
    final pending = _pending;
    final String label;
    if (pending > 0) {
      label = '$pending장 받기 (방어 실패)';
    } else {
      label = '카드 뽑기';
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: myTurn ? _onDraw : null,
            style: FilledButton.styleFrom(
              backgroundColor: pending > 0
                  ? G42Colors.bad
                  : G42Colors.surfaceHi,
            ),
            icon: Icon(
              pending > 0
                  ? Icons.file_download_rounded
                  : Icons.add_card_rounded,
            ),
            label: Text(label),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: G42Colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: G42Colors.surfaceHi),
          ),
          child: Row(
            children: [
              const Icon(Icons.style_rounded, size: 18, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                '덱 ${_deck.length}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- 내 손패 --------------------------------------------------------------

  Widget _myHandLabel(int total, int playableCount) {
    return Row(
      children: [
        const Icon(Icons.back_hand_rounded, size: 18, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          '내 손패  ($total장)',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (playableCount > 0)
          Text(
            '낼 수 있는 카드 $playableCount장',
            style: const TextStyle(color: G42Colors.good, fontSize: 12),
          )
        else
          const Text(
            '낼 카드 없음 → 뽑기',
            style: TextStyle(color: G42Colors.warn, fontSize: 12),
          ),
      ],
    );
  }

  Widget _myHand(List<String> hand, List<String> playable, bool myTurn) {
    if (hand.isEmpty) {
      return const SizedBox(
        height: 88,
        child: Center(
          child: Text('손패가 비었습니다', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final sorted = List<String>.from(hand)..sort(_cardSort);
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final card = sorted[index];
          return Padding(
            key: ValueKey('hand-$card'),
            padding: const EdgeInsets.only(right: 6),
            child: _handCard(
              card,
              highlighted: myTurn && playable.contains(card),
              enabled: myTurn && playable.contains(card),
            ),
          );
        },
      ),
    );
  }

  Widget _handCard(
    String card, {
    required bool highlighted,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? () => _onPlay(card) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? G42Colors.good : Colors.transparent,
              width: 3,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: G42Colors.good.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: _cardFace(card),
        ),
      ),
    );
  }

  // ---- 카드 얼굴 위젯 -------------------------------------------------------

  Widget _cardFace(String card, {bool big = false}) {
    final w = big ? 72.0 : 50.0;
    final h = big ? 104.0 : 74.0;
    final isJoker = OneCardLogic.isJoker(card);
    final suit = OneCardLogic.suitOf(card);
    final rank = OneCardLogic.rankOf(card);
    final color = isJoker ? G42Colors.accent : _suitColor(suit ?? 'S');

    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: isJoker
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_rounded, color: color, size: big ? 30 : 22),
                  Text(
                    'JOKER',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: big ? 11 : 8,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            )
          // 좌상단 랭크 · 중앙 무늬 · 우하단 랭크를 Stack 으로 모서리 배치한다.
          // (Flex Column 의 spaceBetween 은 글리프 높이에 따라 1~2px 오버플로우가
          //  날 수 있어, 위치 배치인 Stack 으로 어떤 카드든 절대 넘치지 않게 한다.)
          : Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    rank ?? '',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: big ? 22 : 18,
                      height: 1.0,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    OneCardLogic.suitSymbol(suit ?? 'S'),
                    style: TextStyle(
                      color: color,
                      fontSize: big ? 30 : 22,
                      height: 1.0,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    rank ?? '',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: big ? 16 : 12,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Color _suitColor(String suit) {
    return (suit == 'H' || suit == 'D') ? G42Colors.bad : Colors.black87;
  }

  // ---- 액션: 카드 내기 ------------------------------------------------------

  Future<void> _onPlay(String card) async {
    if (!widget.session.isMyTurn(widget.room)) return;
    final me = _me;
    final opp = _opponentId;
    if (opp == null) return;

    final myHand = _handOf(me);
    if (!myHand.contains(card)) return;
    if (!OneCardLogic.canPlay(
      card,
      topCard: _discardTop,
      activeSuit: _activeSuit,
      pending: _pending,
      attackKind: _attackKind,
    )) {
      _toast('지금 낼 수 없는 카드입니다');
      return;
    }

    // 와일드(7 무늬 변경 · 조커)면 이어갈 무늬를 직접 고른다.
    // 조커는 무늬가 없으므로 반드시 새 무늬를 지정해야 다음 차례가 이어진다.
    final isWild = OneCardLogic.isWildSuit(card) || OneCardLogic.isJoker(card);
    String chosenSuit = OneCardLogic.suitOf(card) ?? _activeSuit;
    if (isWild) {
      final picked = await _pickSuit(context);
      if (picked == null) return; // 취소.
      chosenSuit = picked;
    }

    final state = _freshState();
    final hands = Map<String, dynamic>.from(state['hands'] as Map);
    final newHand = List<String>.from(myHand)..remove(card);
    hands[me] = newHand;
    state['hands'] = hands;
    state['discardTop'] = card;

    // 무늬 갱신: 와일드(7·조커)는 선택 무늬, 그 외는 카드 무늬.
    state['activeSuit'] = isWild ? chosenSuit : OneCardLogic.suitOf(card);

    // 공격 누적.
    final attack = OneCardLogic.attackValue(card);
    var nextPending = _pending;
    var nextKind = _attackKind;
    if (attack > 0) {
      nextPending = _pending + attack;
      nextKind = OneCardLogic.attackKindOf(card);
    }
    state['pending'] = nextPending;
    state['attackKind'] = nextKind;

    // 승리 판정.
    if (OneCardLogic.isWinner(newHand)) {
      state['lastAction'] = '';
      await widget.session.submit(
        state,
        status: RoomStatus.finished,
        winner: me,
      );
      return;
    }

    // 차례 결정.
    // A(스킵): 2인 게임이라 낸 사람이 한 번 더 둔다 → 내 차례 유지.
    // 그 외: 상대 차례.
    final skip = OneCardLogic.isSkip(card);
    final nextTurn = skip ? me : opp;

    state['lastAction'] = _actionText(
      card,
      attack,
      skip,
      isWild ? chosenSuit : null,
    );
    await widget.session.submit(state, nextTurn: nextTurn);
  }

  String _actionText(String card, int attack, bool skip, String? wildSuit) {
    final suitTag = wildSuit != null
        ? ' → ${OneCardLogic.suitSymbol(wildSuit)}${OneCardLogic.suitName(wildSuit)}'
        : '';
    if (attack > 0) {
      return '${OneCardLogic.label(card)} 공격!$suitTag';
    }
    if (skip) return 'A 스킵 — 한 번 더!';
    if (OneCardLogic.isWildSuit(card)) return '7 무늬 변경$suitTag';
    return '';
  }

  // ---- 액션: 뽑기 -----------------------------------------------------------

  Future<void> _onDraw() async {
    if (!widget.session.isMyTurn(widget.room)) return;
    final me = _me;
    final opp = _opponentId;
    if (opp == null) return;

    final myHand = _handOf(me);
    final pending = _pending;

    // 공격 누적이 있으면 그만큼, 없으면 1장.
    final drawCount = pending > 0 ? pending : 1;

    final result = OneCardLogic.draw(
      _deck,
      _discardPileForRecycle(),
      drawCount,
      rng: _rng,
      keepTop: _discardTop,
    );

    final state = _freshState();
    final hands = Map<String, dynamic>.from(state['hands'] as Map);
    hands[me] = [...myHand, ...result.drawn];
    state['hands'] = hands;
    state['deck'] = result.deck;
    // 공격 처리 끝 → 누적 초기화, 턴 종료(상대로).
    state['pending'] = 0;
    state['attackKind'] = '';
    state['lastAction'] = pending > 0
        ? '${_nameOf(me)} $pending장 받음'
        : '${_nameOf(me)} 1장 뽑음';

    await widget.session.submit(state, nextTurn: opp);
  }

  /// 재활용용 버린 더미. 우리는 버린 카드를 따로 보관하지 않으므로
  /// (단순화: 낸 카드는 사라진다) 맨 위 한 장만 더미로 간주한다.
  /// 덱 소진 시에는 [OneCardLogic.draw]가 빈 더미를 받아 더 못 뽑게 되며,
  /// 그 경우 가능한 만큼만 뽑는다.
  List<String> _discardPileForRecycle() => [_discardTop];

  // ---- 무늬 선택 다이얼로그 (7) ---------------------------------------------

  Future<String?> _pickSuit(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: G42Colors.surface,
          title: const Text(
            '바꿀 무늬를 고르세요',
            style: TextStyle(color: Colors.white),
          ),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in OneCardLogic.suits)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(s),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        OneCardLogic.suitSymbol(s),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: _suitColor(s),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---- 핫시트 가림막 --------------------------------------------------------

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
              '기기를 넘겨받았다면 시작하세요.\n상대에게 손패가 보이지 않게!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() => _curtain = false),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('내 손패 보기'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 결과 오버레이 + 재대국 -----------------------------------------------

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
      icon = Icons.celebration_rounded;
    } else if (iWon) {
      title = '승리!';
      color = G42Colors.good;
      icon = Icons.celebration_rounded;
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
      _curtain = false;
      _lastActor = null;
    });
    widget.session.rematch(
      widget.createInitialState(widget.room.playerIds),
      widget.firstTurn(widget.room.playerIds),
    );
  }

  // ---- 도움말 ---------------------------------------------------------------

  Widget _helpButton(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => _showHelp(context),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: Size.zero,
        ),
        icon: const Icon(
          Icons.help_outline_rounded,
          size: 16,
          color: Colors.white54,
        ),
        label: const Text(
          '규칙 보기',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    final jokers = (widget.room.state['jokers'] as bool?) ?? false;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('원카드 규칙', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _rule(
                '기본',
                '버린 더미 맨 위와 무늬 또는 숫자가 같은 카드를 냅니다. '
                    '낼 카드가 없으면 1장 뽑고 턴이 끝납니다. 손패를 먼저 비우면 승리.',
              ),
              _rule(
                '2 (공격)',
                '다음 사람이 2장을 뽑습니다. 2로 받아치면 누적(4, 6...). '
                    '못 막으면 누적된 장수를 모두 뽑고 턴이 끝납니다.',
              ),
              _rule('A (스킵)', '상대 턴을 건너뜁니다. 2인이라 낸 사람이 한 번 더 둡니다.'),
              _rule('7 (무늬 변경)', '낼 때 바꿀 무늬를 직접 고릅니다(와일드).'),
              if (jokers)
                _rule(
                  '조커 (공격 +5 · 와일드)',
                  '조커는 +5장 공격입니다. 무늬가 없으므로 낼 때 이어갈 무늬를 '
                      '직접 지정합니다. 조커 공격은 조커로만 방어할 수 있고 '
                      '2와 섞어 누적할 수 없습니다.',
                )
              else
                _rule('조커', '이 판은 조커를 사용하지 않습니다.'),
              _rule('덱 소진', '뽑을 카드가 떨어지면 버린 더미(맨 위 제외)를 섞어 재활용합니다.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _rule(String head, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            head,
            style: const TextStyle(
              color: G42Colors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(body, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  // ---- 잡다한 헬퍼 ----------------------------------------------------------

  /// 최신 room.state 복제(내 키만 바꿔 통째로 submit하기 위한 베이스).
  Map<String, dynamic> _freshState() {
    final s = widget.room.state;
    return {
      'deck': ((s['deck'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      'discardTop': (s['discardTop'] as String?) ?? 'SA',
      'activeSuit': (s['activeSuit'] as String?) ?? 'S',
      'hands': Map<String, dynamic>.from(s['hands'] as Map? ?? {}),
      'pending': (s['pending'] as int?) ?? 0,
      'attackKind': (s['attackKind'] as String?) ?? '',
      'jokers': (s['jokers'] as bool?) ?? false,
      'lastAction': (s['lastAction'] as String?) ?? '',
    };
  }

  int _cardSort(String a, String b) {
    final ja = OneCardLogic.isJoker(a);
    final jb = OneCardLogic.isJoker(b);
    if (ja || jb) {
      if (ja && jb) return a.compareTo(b);
      return ja ? 1 : -1; // 조커는 맨 뒤.
    }
    final sa = OneCardLogic.suits.indexOf(a[0]);
    final sb = OneCardLogic.suits.indexOf(b[0]);
    if (sa != sb) return sa.compareTo(sb);
    final ra = OneCardLogic.ranks.indexOf(a.substring(1));
    final rb = OneCardLogic.ranks.indexOf(b.substring(1));
    return ra.compareTo(rb);
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
