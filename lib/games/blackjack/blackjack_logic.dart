import 'dart:math';

/// 블랙잭 순수 로직 (UI / Firestore 의존 없음).
///
/// 카드 인코딩:
/// - 한 장의 카드는 0~51 정수.
/// - rank = card % 13  (0=A, 1=2, ... 9=10, 10=J, 11=Q, 12=K)
/// - suit = card ~/ 13 (0=♠, 1=♥, 2=♦, 3=♣)
///
/// 손패(hand)는 카드 정수의 평탄 `List<int>` 로만 보관한다(중첩 배열 금지).
///
/// 정식 룰(딜러 방식):
/// - 매 라운드 한 명이 '딜러', 다른 한 명이 '플레이어(베팅)' 가 되어 교대한다.
/// - 플레이어는 hit / stand / double down / split 으로 손패를 만든다.
/// - 딜러는 17 이상이 될 때까지 자동으로 뽑는다(S17: 소프트 17에서 스탠드).
/// - 내추럴 블랙잭(2장 21)은 3:2 배당. 칩은 두 사람 사이에서만 이동(제로섬).
abstract class BlackjackLogic {
  static const int deckSize = 52;
  static const int blackjack = 21;

  /// 각 플레이어 시작 칩.
  static const int startingChips = 100;

  /// 딜러 스탠드 기준(이 값 이상이면 멈춘다).
  static const int dealerStandsOn = 17;

  static const List<String> _suits = ['♠', '♥', '♦', '♣'];
  static const List<String> _ranks = [
    'A',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'J',
    'Q',
    'K',
  ];

  static int rankOf(int card) => card % 13;
  static int suitOf(int card) => card ~/ 13;

  /// 카드 표시용 라벨 (예: 'A♠', '10♥').
  static String label(int card) =>
      '${_ranks[rankOf(card)]}${_suits[suitOf(card)]}';

  /// 빨강 무늬(♥/♦)인가.
  static bool isRed(int card) {
    final s = suitOf(card);
    return s == 1 || s == 2;
  }

  /// 카드 한 장의 기본 값. A=1(유연 처리는 [handTotal]에서), J/Q/K=10.
  static int cardValue(int card) {
    final r = rankOf(card);
    if (r == 0) return 1; // Ace base
    if (r >= 10) return 10; // J,Q,K
    return r + 1; // 2..10
  }

  /// 손패 합계. A는 21을 넘지 않는 한 11로 계산(유연 합).
  static int handTotal(List<int> hand) {
    var total = 0;
    var aces = 0;
    for (final c in hand) {
      final r = rankOf(c);
      if (r == 0) aces++;
      total += cardValue(c);
    }
    // A 하나를 11로 올릴 수 있으면 올린다(+10).
    while (aces > 0 && total + 10 <= blackjack) {
      total += 10;
      aces--;
    }
    return total;
  }

  /// 손패에 ace가 있고, 그것을 11로 쳐서 합에 반영된 상태(소프트 핸드)인가.
  static bool isSoft(List<int> hand) {
    var hard = 0;
    var aces = 0;
    for (final c in hand) {
      if (rankOf(c) == 0) aces++;
      hard += cardValue(c);
    }
    return aces > 0 && hard + 10 <= blackjack;
  }

  static bool isBust(List<int> hand) => handTotal(hand) > blackjack;

  /// 정확히 2장으로 21(에이스 + 10값) → 내추럴 블랙잭.
  static bool isNaturalBlackjack(List<int> hand) =>
      hand.length == 2 && handTotal(hand) == blackjack;

  /// 셔플된 덱(0~51 순열) 생성.
  static List<int> shuffledDeck([Random? rng]) {
    final r = rng ?? Random();
    final deck = List<int>.generate(deckSize, (i) => i);
    deck.shuffle(r);
    return deck;
  }

  /// 라운드 승자 판정(딜러 없는 대칭 비교용 — 호환/테스트 보존).
  ///
  /// 반환: 0 = handA 승, 1 = handB 승, -1 = 무승부(push).
  static int compareHands(List<int> handA, List<int> handB) {
    final bustA = isBust(handA);
    final bustB = isBust(handB);
    if (bustA && bustB) return -1;
    if (bustA) return 1;
    if (bustB) return 0;
    final tA = handTotal(handA);
    final tB = handTotal(handB);
    if (tA > tB) return 0;
    if (tB > tA) return 1;
    return -1; // push
  }

  // ---- 정식 룰: 딜러 진행 / 정산 / 액션 가능 여부 -------------------------

  /// 딜러가 한 장 더 받아야 하는가(17 미만이면 히트).
  static bool dealerShouldHit(List<int> hand) =>
      handTotal(hand) < dealerStandsOn;

  /// 딜러 자동 진행: 17 이상이 될 때까지 [deck]에서 카드를 뽑는다(결정적).
  ///
  /// 반환: 최종 딜러 손패와 갱신된 포인터. 덱이 소진되면 그 자리에서 멈춘다.
  static ({List<int> hand, int ptr}) playDealer(
    List<int> deck,
    int ptr,
    List<int> dealerHand,
  ) {
    final hand = List<int>.from(dealerHand);
    var p = ptr;
    while (dealerShouldHit(hand) && p < deck.length) {
      hand.add(deck[p++]);
    }
    return (hand: hand, ptr: p);
  }

  /// 한 손패의 정산(플레이어 기준 칩 증감, 제로섬).
  ///
  /// [bet]: 이 손패에 건 칩(더블다운이면 2배가 들어온다).
  /// [natural]: 이 손패가 2장 내추럴 보너스(3:2) 대상인지(스플릿 손패는 false).
  /// 양수 = 플레이어 획득, 음수 = 플레이어 상실, 0 = push(환수).
  static int settleHand({
    required List<int> playerHand,
    required List<int> dealerHand,
    required int bet,
    required bool natural,
  }) {
    if (isBust(playerHand)) return -bet; // 플레이어 버스트는 무조건 패.
    final dealerNatural = isNaturalBlackjack(dealerHand);
    final playerNatural = natural && isNaturalBlackjack(playerHand);
    if (playerNatural && dealerNatural) return 0; // 둘 다 내추럴 → push.
    if (playerNatural) return (bet * 3) ~/ 2; // 내추럴 블랙잭 3:2 보너스.
    if (dealerNatural) return -bet; // 딜러만 내추럴 → 패.
    if (isBust(dealerHand)) return bet; // 딜러 버스트 → 승.
    final pt = handTotal(playerHand);
    final dt = handTotal(dealerHand);
    if (pt > dt) return bet;
    if (pt < dt) return -bet;
    return 0; // push(동점 환수).
  }

  /// 라운드 정산(플레이어 기준 순 칩 증감). 스플릿이면 두 손패를 합산.
  static int settleRound({
    required List<int> hand0,
    List<int>? splitHand,
    required List<int> dealerHand,
    required int bet0,
    int bet1 = 0,
    bool split = false,
  }) {
    var delta = settleHand(
      playerHand: hand0,
      dealerHand: dealerHand,
      bet: bet0,
      natural: !split, // 스플릿 손패의 21은 내추럴 보너스 대상 아님.
    );
    if (split && splitHand != null) {
      delta += settleHand(
        playerHand: splitHand,
        dealerHand: dealerHand,
        bet: bet1,
        natural: false,
      );
    }
    return delta;
  }

  /// 제로섬 칩 이동 클램프. [delta]는 플레이어 기준 이상적 증감(+획득/-상실).
  ///
  /// 어느 쪽도 0 미만이 되지 않도록 실제 이동량으로 보정한다(딜러가 다 못 주면
  /// 가진 만큼만, 플레이어가 다 못 잃으면 가진 만큼만). 반환은 실제 적용 증감.
  static int clampTransfer({
    required int delta,
    required int playerChips,
    required int dealerChips,
  }) {
    if (delta >= 0) return delta > dealerChips ? dealerChips : delta;
    final loss = -delta;
    return -(loss > playerChips ? playerChips : loss);
  }

  /// 스플릿 가능 여부: 2장이고 같은 랭크.
  static bool canSplit(List<int> hand) =>
      hand.length == 2 && rankOf(hand[0]) == rankOf(hand[1]);

  /// 더블다운 가능 여부(칩 커버는 호출측에서 확인): 정확히 2장.
  static bool canDouble(List<int> hand) => hand.length == 2;

  /// 에이스 페어인가(스플릿 시 각 손패는 한 장만 받고 종료).
  static bool isAcePair(List<int> hand) =>
      hand.length == 2 && rankOf(hand[0]) == 0 && rankOf(hand[1]) == 0;
}
