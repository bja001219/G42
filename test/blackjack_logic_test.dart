import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/blackjack/blackjack_logic.dart';

void main() {
  // 카드 인코딩: rank = card%13 (0=A..12=K), suit = card~/13.
  int card(int rank, int suit) => suit * 13 + rank;

  group('cardValue', () {
    test('A는 기본 1', () => expect(BlackjackLogic.cardValue(card(0, 0)), 1));
    test('2는 2', () => expect(BlackjackLogic.cardValue(card(1, 0)), 2));
    test('10은 10', () => expect(BlackjackLogic.cardValue(card(9, 0)), 10));
    test('J/Q/K는 10', () {
      expect(BlackjackLogic.cardValue(card(10, 0)), 10);
      expect(BlackjackLogic.cardValue(card(11, 0)), 10);
      expect(BlackjackLogic.cardValue(card(12, 0)), 10);
    });
  });

  group('handTotal - A 유연 합', () {
    test('A + K = 21 (블랙잭)', () {
      final hand = [card(0, 0), card(12, 1)];
      expect(BlackjackLogic.handTotal(hand), 21);
      expect(BlackjackLogic.isNaturalBlackjack(hand), isTrue);
    });

    test('A + 9 = 20 (A는 11)', () {
      expect(BlackjackLogic.handTotal([card(0, 0), card(8, 1)]), 20);
    });

    test('A + A + 9 = 21 (한쪽 A만 11)', () {
      final hand = [card(0, 0), card(0, 1), card(8, 2)];
      expect(BlackjackLogic.handTotal(hand), 21);
    });

    test('A + 9 + 5 = 15 (A를 1로 다운)', () {
      final hand = [card(0, 0), card(8, 1), card(4, 2)];
      expect(BlackjackLogic.handTotal(hand), 15);
    });

    test('소프트 핸드 판별: A+6 은 소프트', () {
      expect(BlackjackLogic.isSoft([card(0, 0), card(5, 1)]), isTrue);
    });

    test('소프트 핸드 판별: A+6+10 은 하드(17)', () {
      final hand = [card(0, 0), card(5, 1), card(9, 2)];
      expect(BlackjackLogic.handTotal(hand), 17);
      expect(BlackjackLogic.isSoft(hand), isFalse);
    });
  });

  group('isBust', () {
    test('K + Q + 5 = 25 버스트', () {
      expect(
        BlackjackLogic.isBust([card(12, 0), card(11, 1), card(4, 2)]),
        isTrue,
      );
    });
    test('K + Q = 20 버스트 아님', () {
      expect(BlackjackLogic.isBust([card(12, 0), card(11, 1)]), isFalse);
    });
  });

  group('compareHands', () {
    test('A가 21, B가 20 → A 승(0)', () {
      final a = [card(0, 0), card(12, 1)]; // 21
      final b = [card(9, 0), card(9, 1)]; // 20
      expect(BlackjackLogic.compareHands(a, b), 0);
    });

    test('A 버스트, B 살아있음 → B 승(1)', () {
      final a = [card(12, 0), card(11, 1), card(4, 2)]; // 25 bust
      final b = [card(9, 0), card(9, 1)]; // 20
      expect(BlackjackLogic.compareHands(a, b), 1);
    });

    test('둘 다 버스트 → 무승부(-1)', () {
      final a = [card(12, 0), card(11, 1), card(4, 2)]; // 25
      final b = [card(12, 2), card(11, 3), card(5, 0)]; // 26
      expect(BlackjackLogic.compareHands(a, b), -1);
    });

    test('동점 → push(-1)', () {
      final a = [card(9, 0), card(9, 1)]; // 20
      final b = [card(9, 2), card(9, 3)]; // 20
      expect(BlackjackLogic.compareHands(a, b), -1);
    });

    test('B가 더 높음 → B 승(1)', () {
      final a = [card(9, 0), card(8, 1)]; // 19
      final b = [card(9, 2), card(9, 3)]; // 20
      expect(BlackjackLogic.compareHands(a, b), 1);
    });
  });

  group('shuffledDeck', () {
    test('52장 0~51 순열', () {
      final deck = BlackjackLogic.shuffledDeck();
      expect(deck.length, 52);
      expect(deck.toSet().length, 52);
      expect(deck.every((c) => c >= 0 && c < 52), isTrue);
    });
  });

  // ---- 정식 룰 ------------------------------------------------------------

  group('딜러 자동 진행 (S17)', () {
    test('17 미만이면 17 이상까지 뽑는다', () {
      final dealer = [card(1, 0), card(2, 0)]; // 2+3 = 5
      final deck = [card(9, 0), card(4, 1)]; // 10, 5
      final res = BlackjackLogic.playDealer(deck, 0, dealer);
      expect(BlackjackLogic.handTotal(res.hand), 20); // 5+10+5
      expect(res.ptr, 2);
    });

    test('정확히 17이면 멈춘다 (하드 17)', () {
      final dealer = [card(9, 0), card(6, 1)]; // 10+7 = 17
      final deck = [card(9, 2)];
      final res = BlackjackLogic.playDealer(deck, 0, dealer);
      expect(res.hand.length, 2);
      expect(res.ptr, 0);
    });

    test('소프트 17(A+6)에서 멈춘다 (S17)', () {
      final dealer = [card(0, 0), card(5, 1)]; // A+6 = 17(soft)
      final deck = [card(9, 2)];
      final res = BlackjackLogic.playDealer(deck, 0, dealer);
      expect(res.hand.length, 2);
      expect(BlackjackLogic.handTotal(res.hand), 17);
      expect(res.ptr, 0);
    });

    test('16에서 한 장 더 뽑는다', () {
      final dealer = [card(9, 0), card(5, 1)]; // 10+6 = 16
      final deck = [card(0, 2)]; // A → 16+1 = 17
      final res = BlackjackLogic.playDealer(deck, 0, dealer);
      expect(res.hand.length, 3);
      expect(BlackjackLogic.handTotal(res.hand), 17);
      expect(res.ptr, 1);
    });
  });

  group('settleHand - 한 손패 정산(플레이어 기준)', () {
    final dealer18 = [card(9, 0), card(7, 1)]; // 10+8 = 18

    test('플레이어 20 vs 딜러 18 → +bet', () {
      final p = [card(9, 2), card(9, 3)]; // 20
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18,
          bet: 10,
          natural: true,
        ),
        10,
      );
    });

    test('플레이어 버스트 → -bet (딜러 무관)', () {
      final p = [card(9, 2), card(9, 3), card(4, 0)]; // 25
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18,
          bet: 10,
          natural: true,
        ),
        -10,
      );
    });

    test('딜러 버스트 → +bet', () {
      final p = [card(9, 2), card(5, 3)]; // 16
      final dealerBust = [card(9, 0), card(9, 1), card(4, 2)]; // 25
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealerBust,
          bet: 10,
          natural: true,
        ),
        10,
      );
    });

    test('동점 → push(0)', () {
      final p = [card(9, 2), card(7, 3)]; // 18
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18,
          bet: 10,
          natural: true,
        ),
        0,
      );
    });

    test('내추럴 블랙잭 → 3:2 (bet 10 → 15)', () {
      final p = [card(0, 2), card(12, 3)]; // A+K = 21 (2장)
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18,
          bet: 10,
          natural: true,
        ),
        15,
      );
    });

    test('내추럴 3:2 홀수 bet 은 내림 (bet 5 → 7)', () {
      final p = [card(0, 2), card(12, 3)];
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18,
          bet: 5,
          natural: true,
        ),
        7,
      );
    });

    test('둘 다 내추럴 → push(0)', () {
      final p = [card(0, 2), card(12, 3)]; // 21
      final d = [card(0, 0), card(10, 1)]; // A+J = 21
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: d,
          bet: 10,
          natural: true,
        ),
        0,
      );
    });

    test('딜러만 내추럴 → -bet', () {
      final p = [card(9, 2), card(9, 3)]; // 20
      final d = [card(0, 0), card(10, 1)]; // 21 natural
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: d,
          bet: 10,
          natural: true,
        ),
        -10,
      );
    });

    test('natural=false(스플릿 손패)의 2장 21은 보너스 없이 일반 비교', () {
      final p = [card(0, 2), card(12, 3)]; // 21 이지만 natural 플래그 false
      expect(
        BlackjackLogic.settleHand(
          playerHand: p,
          dealerHand: dealer18, // 18
          bet: 10,
          natural: false,
        ),
        10, // 1.5배가 아니라 1배.
      );
    });
  });

  group('settleRound - 스플릿 합산', () {
    final dealer18 = [card(9, 0), card(7, 1)]; // 18

    test('비스플릿은 단일 손패 정산을 위임', () {
      final h0 = [card(9, 2), card(9, 3)]; // 20
      expect(
        BlackjackLogic.settleRound(hand0: h0, dealerHand: dealer18, bet0: 10),
        10,
      );
    });

    test('스플릿: 한 손패 승 + 다른 손패 패 = 0', () {
      final h0 = [card(9, 2), card(9, 3)]; // 20 (승)
      final h1 = [card(4, 2), card(5, 3)]; // 5+6 = 11 (패: 11<18)
      final delta = BlackjackLogic.settleRound(
        hand0: h0,
        splitHand: h1,
        dealerHand: dealer18,
        bet0: 10,
        bet1: 10,
        split: true,
      );
      expect(delta, 0); // +10 -10
    });

    test('스플릿: 두 손패 모두 승 = +2bet', () {
      final h0 = [card(9, 2), card(9, 3)]; // 20
      final h1 = [card(9, 0), card(8, 1)]; // 19
      final delta = BlackjackLogic.settleRound(
        hand0: h0,
        splitHand: h1,
        dealerHand: dealer18,
        bet0: 10,
        bet1: 10,
        split: true,
      );
      expect(delta, 20);
    });
  });

  group('액션 가능 여부', () {
    test('canSplit: 같은 랭크 2장만', () {
      expect(BlackjackLogic.canSplit([card(7, 0), card(7, 1)]), isTrue); // 8,8
      expect(BlackjackLogic.canSplit([card(7, 0), card(8, 1)]), isFalse);
      expect(
        BlackjackLogic.canSplit([card(7, 0), card(7, 1), card(2, 2)]),
        isFalse,
      );
    });

    test('canDouble: 정확히 2장', () {
      expect(BlackjackLogic.canDouble([card(4, 0), card(5, 1)]), isTrue);
      expect(
        BlackjackLogic.canDouble([card(4, 0), card(5, 1), card(1, 2)]),
        isFalse,
      );
    });

    test('isAcePair: A 두 장', () {
      expect(BlackjackLogic.isAcePair([card(0, 0), card(0, 1)]), isTrue);
      expect(BlackjackLogic.isAcePair([card(0, 0), card(12, 1)]), isFalse);
    });
  });

  group('clampTransfer - 제로섬 칩 이동', () {
    test('정상 범위 내 이동은 그대로', () {
      expect(
        BlackjackLogic.clampTransfer(
          delta: 10,
          playerChips: 100,
          dealerChips: 100,
        ),
        10,
      );
      expect(
        BlackjackLogic.clampTransfer(
          delta: -10,
          playerChips: 100,
          dealerChips: 100,
        ),
        -10,
      );
    });

    test('획득이 딜러 보유칩을 넘으면 딜러 보유칩까지만', () {
      // 내추럴 3:2로 15 획득해야 하지만 딜러가 8밖에 없으면 8만.
      expect(
        BlackjackLogic.clampTransfer(
          delta: 15,
          playerChips: 100,
          dealerChips: 8,
        ),
        8,
      );
    });

    test('상실이 내 보유칩을 넘으면 내 보유칩까지만', () {
      expect(
        BlackjackLogic.clampTransfer(
          delta: -40,
          playerChips: 25,
          dealerChips: 100,
        ),
        -25,
      );
    });

    test('이동 후에도 합계는 보존(제로섬)', () {
      const pStart = 30;
      const dStart = 12;
      final t = BlackjackLogic.clampTransfer(
        delta: 50, // 과도한 획득 → dStart로 클램프.
        playerChips: pStart,
        dealerChips: dStart,
      );
      expect(t, 12);
      expect(pStart + t, 42);
      expect(dStart - t, 0); // 딜러 0 → 매치 종료 조건.
      expect((pStart + t) + (dStart - t), pStart + dStart);
    });
  });

  group('내추럴 3:2 커버 보장 (베팅 상한 회귀 테스트)', () {
    // 뷰의 _maxBet = floor((2*dealerChips+1)/3) 와 동일한 공식.
    int maxBetFor(int dealerChips) => (2 * dealerChips + 1) ~/ 3;

    final natural = [card(0, 2), card(12, 3)]; // A+K = 21 (2장 내추럴)
    final dealer18 = [card(9, 0), card(7, 1)]; // 18 (내추럴 아님)

    test('상한 내 베팅이면 내추럴 3:2가 딜러 칩에 의해 잘리지 않는다', () {
      for (var d = 1; d <= 200; d++) {
        final bet = maxBetFor(d);
        expect(bet, greaterThanOrEqualTo(1));
        final payout = BlackjackLogic.settleHand(
          playerHand: natural,
          dealerHand: dealer18,
          bet: bet,
          natural: true,
        );
        expect(payout, (bet * 3) ~/ 2);
        expect(
          payout,
          lessThanOrEqualTo(d),
          reason: '딜러 칩 $d 으로 지급 가능해야 함 (bet=$bet, payout=$payout)',
        );
        // 클램프가 일어나지 않아 실제 지급액 == 이상적 지급액.
        final applied = BlackjackLogic.clampTransfer(
          delta: payout,
          playerChips: 1000,
          dealerChips: d,
        );
        expect(applied, payout);
      }
    });
  });
}
