import 'dart:math';

/// 원카드(Uno류) 순수 로직 (UI / Firestore 의존 없음).
///
/// ## 카드 인코딩 (문자열)
/// - 일반 카드: `<무늬><랭크>` 형태.
///   - 무늬: `S`(스페이드), `H`(하트), `D`(다이아), `C`(클로버).
///   - 랭크: `A 2 3 4 5 6 7 8 9 10 J Q K`.
///   - 예: `'H7'`, `'SA'`, `'D10'`, `'CK'`.
/// - 조커: `'JR'`(빨강), `'JB'`(검정). (조커 사용 옵션일 때만 등장)
///
/// ## 고정 규칙 (인게임 도움말과 동일)
/// - 각자 7장 시작. 버린 더미 맨 위 카드와 **무늬 또는 랭크**가 같으면 낼 수 있다.
/// - 못 내면 1장 뽑고 턴 종료.
/// - 특수카드:
///   - `2`  공격: 다음 사람 2장 뽑기. 다음 사람이 `2`를 내면 누적(4,6...).
///           못 막으면 누적 장수를 뽑고 턴 종료.
///   - `A`  스킵: 상대 턴 건너뜀(2인이라 낸 사람이 한 번 더 둔다).
///   - `7`  무늬 변경(와일드): 낼 때 원하는 무늬를 지정한다.
///   - 조커(옵션): 공격 +5. 조커는 조커로만 방어(2와 혼합 누적 금지).
///   - 그 외(3,4,5,6,8,9,10,J,Q,K): 일반.
/// - 드로우 더미 소진 시 버린 더미(맨 위 제외)를 섞어 재활용한다.
/// - 손패를 먼저 비우면 승리.
abstract class OneCardLogic {
  static const List<String> suits = ['S', 'H', 'D', 'C'];

  /// 랭크 순서(인코딩/표시용).
  static const List<String> ranks = [
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

  static const String jokerRed = 'JR';
  static const String jokerBlack = 'JB';

  /// 조커 한 장이 가하는 공격 누적량.
  static const int jokerAttack = 5;

  /// 일반 공격 카드(2)가 가하는 누적량.
  static const int twoAttack = 2;

  /// 처음 나눠줄 손패 장수.
  static const int handSize = 7;

  // ---- 카드 파싱 -----------------------------------------------------------

  static bool isJoker(String card) => card == jokerRed || card == jokerBlack;

  /// 무늬 문자. 조커는 null.
  static String? suitOf(String card) => isJoker(card) ? null : card[0];

  /// 랭크 문자열('A'~'K','10'). 조커는 null.
  static String? rankOf(String card) =>
      isJoker(card) ? null : card.substring(1);

  // ---- 덱 생성 -------------------------------------------------------------

  /// 표준 52장(+ 옵션 조커 2장)을 섞은 덱.
  static List<String> freshDeck({bool jokers = false, Random? rng}) {
    final r = rng ?? Random();
    final deck = <String>[];
    for (final s in suits) {
      for (final rank in ranks) {
        deck.add('$s$rank');
      }
    }
    if (jokers) {
      deck.add(jokerRed);
      deck.add(jokerBlack);
    }
    deck.shuffle(r);
    return deck;
  }

  // ---- 합법수 판정 ---------------------------------------------------------

  /// [card]를 현재 상태에서 낼 수 있는가.
  ///
  /// - [topCard]: 버린 더미 맨 위.
  /// - [activeSuit]: 현재 유효 무늬(7로 바뀌었을 수 있음). 보통 topCard의 무늬.
  /// - [pending]: 현재 누적된 공격 장수(0이면 공격 없음).
  ///
  /// ### 공격 중(pending > 0) 방어 규칙
  /// - 직전 공격이 일반(2) 누적이면: `2`로만 막을 수 있다.
  /// - 직전 공격이 조커면: 조커로만 막을 수 있다.
  /// - 둘을 혼합 누적할 수 없다([attackKind]로 구분).
  static bool canPlay(
    String card, {
    required String topCard,
    required String activeSuit,
    int pending = 0,
    String attackKind = '',
  }) {
    if (pending > 0) {
      // 방어만 가능.
      if (attackKind == 'joker') {
        return isJoker(card);
      }
      // 'two' 공격 진행 중: 2로만 방어.
      return !isJoker(card) && rankOf(card) == '2';
    }

    // 평시: 조커는 언제든 낼 수 있다(공격 개시).
    if (isJoker(card)) return true;

    // 무늬 또는 랭크 일치.
    if (suitOf(card) == activeSuit) return true;
    if (rankOf(card) == rankOf(topCard) && !isJoker(topCard)) return true;
    return false;
  }

  /// 손패 중 낼 수 있는 카드 목록.
  static List<String> playableCards(
    List<String> hand, {
    required String topCard,
    required String activeSuit,
    int pending = 0,
    String attackKind = '',
  }) {
    return hand
        .where(
          (c) => canPlay(
            c,
            topCard: topCard,
            activeSuit: activeSuit,
            pending: pending,
            attackKind: attackKind,
          ),
        )
        .toList();
  }

  /// 손패에 낼 수 있는 카드가 하나라도 있는가.
  static bool hasPlayable(
    List<String> hand, {
    required String topCard,
    required String activeSuit,
    int pending = 0,
    String attackKind = '',
  }) {
    return hand.any(
      (c) => canPlay(
        c,
        topCard: topCard,
        activeSuit: activeSuit,
        pending: pending,
        attackKind: attackKind,
      ),
    );
  }

  // ---- 카드 효과 -----------------------------------------------------------

  /// [card]가 공격 카드면 그 누적량(2 → 2, 조커 → 5), 아니면 0.
  static int attackValue(String card) {
    if (isJoker(card)) return jokerAttack;
    if (rankOf(card) == '2') return twoAttack;
    return 0;
  }

  /// [card]의 공격 종류: 'two' / 'joker' / ''(공격 아님).
  static String attackKindOf(String card) {
    if (isJoker(card)) return 'joker';
    if (rankOf(card) == '2') return 'two';
    return '';
  }

  /// 스킵(A)인가.
  static bool isSkip(String card) => !isJoker(card) && rankOf(card) == 'A';

  /// 무늬 변경 와일드(7)인가.
  static bool isWildSuit(String card) => !isJoker(card) && rankOf(card) == '7';

  // ---- 드로우 더미 재활용 ---------------------------------------------------

  /// 덱에서 [count]장을 뽑는다. 모자라면 [discardPile](맨 위 [keepTop] 제외)을
  /// 섞어 보충한다.
  ///
  /// 반환: (뽑힌 카드들, 남은 덱, 남은 버린 더미).
  /// 더 이상 보충할 카드가 없으면 가능한 만큼만 뽑는다.
  static DrawResult draw(
    List<String> deck,
    List<String> discardPile,
    int count, {
    Random? rng,
    String keepTop = '',
  }) {
    final r = rng ?? Random();
    final workingDeck = List<String>.from(deck);
    final workingDiscard = List<String>.from(discardPile);
    final drawn = <String>[];

    for (var i = 0; i < count; i++) {
      if (workingDeck.isEmpty) {
        // 버린 더미 재활용: 맨 위(keepTop) 한 장은 남긴다.
        final recyclable = <String>[];
        for (final c in workingDiscard) {
          recyclable.add(c);
        }
        if (keepTop.isNotEmpty && recyclable.isNotEmpty) {
          // keepTop 한 장만 제거(중복 카드 대비 단일 제거).
          recyclable.remove(keepTop);
        }
        if (recyclable.isEmpty) break; // 더 이상 보충 불가.
        recyclable.shuffle(r);
        workingDeck.addAll(recyclable);
        workingDiscard
          ..clear()
          ..addAll(keepTop.isNotEmpty ? [keepTop] : const []);
      }
      drawn.add(workingDeck.removeLast());
    }

    return DrawResult(drawn: drawn, deck: workingDeck, discard: workingDiscard);
  }

  // ---- 승리 ----------------------------------------------------------------

  /// 손패가 비었으면 승리.
  static bool isWinner(List<String> hand) => hand.isEmpty;

  // ---- 표시용 -------------------------------------------------------------

  /// 무늬 기호.
  static String suitSymbol(String suit) {
    switch (suit) {
      case 'S':
        return '♠'; // ♠
      case 'H':
        return '♥'; // ♥
      case 'D':
        return '♦'; // ♦
      case 'C':
        return '♣'; // ♣
      default:
        return '?';
    }
  }

  /// 무늬 한글 이름.
  static String suitName(String suit) {
    switch (suit) {
      case 'S':
        return '스페이드';
      case 'H':
        return '하트';
      case 'D':
        return '다이아';
      case 'C':
        return '클로버';
      default:
        return suit;
    }
  }

  /// 카드의 사람이 읽는 라벨(예: 'H7' → '♥7', 'JR' → '조커').
  static String label(String card) {
    if (card == jokerRed) return '조커(빨강)';
    if (card == jokerBlack) return '조커(검정)';
    if (isJoker(card)) return '조커';
    return '${suitSymbol(card[0])}${card.substring(1)}';
  }
}

/// [OneCardLogic.draw] 결과.
class DrawResult {
  final List<String> drawn;
  final List<String> deck;
  final List<String> discard;

  const DrawResult({
    required this.drawn,
    required this.deck,
    required this.discard,
  });
}
