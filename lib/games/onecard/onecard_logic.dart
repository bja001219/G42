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
/// - 공격 카드(상대가 받아치지 못하면 누적 장수만큼 뽑고 턴 종료):
///   - `2`         상대 2장.
///   - `A`         상대 3장.
///   - 흑백조커(JB)  상대 5장.
///   - 컬러조커(JR)  상대 7장.
/// - 받아치기(누적): **같은 티어 이상**으로만 받아칠 수 있다(티어: 2 < A < 조커).
///   - `2` 공격 → 2 · A · 조커로 받아침.
///   - `A` 공격 → A · 조커로 받아침.
///   - 조커 공격 → 조커로만 받아침. **예외: 스페이드 A로 막으면 무효(드로우 없음).**
/// - `7`  무늬 변경(와일드): 낼 때 원하는 무늬를 지정한다.
/// - 조커: 무늬를 고르지 않는다. 컬러조커(빨강) 위에는 **아무 카드나**, 흑백조커(검정)
///   위에는 **검은 무늬(스페이드/클로버)만** 낼 수 있다.
/// - 드로우 더미 소진 시 버린 더미를 섞어 재활용한다(유한 1팩: 52 + 조커 2 = 54장).
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

  /// 흑백조커(검정 JB)가 가하는 공격 누적량.
  static const int jokerBlackAttack = 5;

  /// 컬러조커(빨강 JR)가 가하는 공격 누적량.
  static const int jokerRedAttack = 7;

  /// 에이스(A)가 가하는 공격 누적량.
  static const int aceAttack = 3;

  /// 일반 공격 카드(2)가 가하는 누적량.
  static const int twoAttack = 2;

  /// 조커 공격을 무효화할 수 있는 특수 방어 카드(스페이드 A).
  static const String spadeAce = 'SA';

  /// 활성 무늬 특수값: 컬러조커(빨강) 위에는 **아무 카드나** 낼 수 있다.
  static const String suitAny = 'ANY';

  /// 활성 무늬 특수값: 흑백조커(검정) 위에는 **검은 무늬(스페이드/클로버)만** 낼 수 있다.
  static const String suitBlack = 'BLACK';

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
  /// ### 공격 중(pending > 0) 방어/받아치기 규칙
  /// - 진행 중인 공격과 **같은 티어 이상**으로만 받아칠 수 있다(티어: 2 < A < 조커).
  ///   예) 2 공격은 2·A·조커로, A 공격은 A·조커로, 조커 공격은 조커로 받아친다.
  /// - 예외: 조커 공격은 **스페이드 A**로 막을 수 있다(받아치기 위계 무시).
  ///   스페이드 A 방어 시 누적을 무효화(드로우 없음)하는 처리는 호출부(뷰)에서 한다.
  static bool canPlay(
    String card, {
    required String topCard,
    required String activeSuit,
    int pending = 0,
    String attackKind = '',
  }) {
    if (pending > 0) {
      // 받아치기: 진행 중인 공격과 같은 티어 이상으로만(2 < A < 조커).
      final inTier = kindTier(attackKind);
      // 예외: 조커 공격은 스페이드 A로 막을 수 있다.
      if (inTier >= 3 && card == spadeAce) return true;
      final t = attackTier(card);
      return t > 0 && t >= inTier;
    }

    // 평시: 조커는 언제든 낼 수 있다(공격 개시).
    if (isJoker(card)) return true;

    // 조커가 깐 특수 활성 무늬.
    if (activeSuit == suitAny) return true; // 컬러조커 위: 아무거나.
    if (activeSuit == suitBlack) {
      // 흑백조커 위: 검은 무늬(스페이드/클로버)만.
      final s = suitOf(card);
      return s == 'S' || s == 'C';
    }

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

  /// [card]가 공격 카드면 그 누적량, 아니면 0.
  /// (2 → 2, A → 3, 흑백조커 JB → 5, 컬러조커 JR → 7)
  static int attackValue(String card) {
    if (card == jokerBlack) return jokerBlackAttack;
    if (card == jokerRed) return jokerRedAttack;
    final rank = rankOf(card);
    if (rank == 'A') return aceAttack;
    if (rank == '2') return twoAttack;
    return 0;
  }

  /// [card]의 공격 종류: 'two' / 'ace' / 'joker' / ''(공격 아님).
  static String attackKindOf(String card) {
    if (isJoker(card)) return 'joker';
    final rank = rankOf(card);
    if (rank == 'A') return 'ace';
    if (rank == '2') return 'two';
    return '';
  }

  /// 공격 카드의 받아치기 티어(2 < A < 조커). 공격 카드가 아니면 0.
  static int attackTier(String card) {
    if (isJoker(card)) return 3;
    final rank = rankOf(card);
    if (rank == 'A') return 2;
    if (rank == '2') return 1;
    return 0;
  }

  /// 진행 중인 공격 종류([attackKind])의 티어.
  static int kindTier(String kind) {
    switch (kind) {
      case 'joker':
        return 3;
      case 'ace':
        return 2;
      case 'two':
        return 1;
      default:
        return 0;
    }
  }

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
