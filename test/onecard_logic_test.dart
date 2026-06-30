import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/onecard/onecard_logic.dart';

void main() {
  group('카드 파싱', () {
    test('무늬/랭크 추출', () {
      expect(OneCardLogic.suitOf('H7'), 'H');
      expect(OneCardLogic.rankOf('H7'), '7');
      expect(OneCardLogic.suitOf('D10'), 'D');
      expect(OneCardLogic.rankOf('D10'), '10');
      expect(OneCardLogic.rankOf('SA'), 'A');
    });

    test('조커 판정', () {
      expect(OneCardLogic.isJoker('JR'), true);
      expect(OneCardLogic.isJoker('JB'), true);
      expect(OneCardLogic.isJoker('H7'), false);
      expect(OneCardLogic.suitOf('JR'), isNull);
      expect(OneCardLogic.rankOf('JB'), isNull);
    });
  });

  group('덱 생성', () {
    test('조커 없이 52장', () {
      final deck = OneCardLogic.freshDeck(rng: Random(1));
      expect(deck.length, 52);
      expect(deck.toSet().length, 52); // 중복 없음.
    });

    test('조커 포함 54장 (1팩)', () {
      final deck = OneCardLogic.freshDeck(jokers: true, rng: Random(1));
      expect(deck.length, 54);
      expect(deck.toSet().length, 54); // 전부 유일.
      expect(deck.contains('JR'), true);
      expect(deck.contains('JB'), true);
    });
  });

  group('합법수 판정', () {
    test('무늬 일치', () {
      expect(OneCardLogic.canPlay('H3', topCard: 'H7', activeSuit: 'H'), true);
    });

    test('랭크 일치', () {
      expect(OneCardLogic.canPlay('S7', topCard: 'H7', activeSuit: 'H'), true);
    });

    test('무늬·랭크 모두 불일치면 불가', () {
      expect(OneCardLogic.canPlay('S3', topCard: 'H7', activeSuit: 'H'), false);
    });

    test('7로 바뀐 activeSuit를 따른다', () {
      // top은 H7이지만 7로 무늬가 C로 변경된 상황.
      expect(OneCardLogic.canPlay('C3', topCard: 'H7', activeSuit: 'C'), true);
      expect(OneCardLogic.canPlay('H3', topCard: 'H7', activeSuit: 'C'), false);
    });

    test('playableCards / hasPlayable', () {
      final hand = ['H3', 'S9', 'C7'];
      final playable = OneCardLogic.playableCards(
        hand,
        topCard: 'H7',
        activeSuit: 'H',
      );
      expect(playable.contains('H3'), true); // 무늬.
      expect(playable.contains('C7'), true); // 랭크.
      expect(playable.contains('S9'), false);
      expect(
        OneCardLogic.hasPlayable(hand, topCard: 'H7', activeSuit: 'H'),
        true,
      );
      expect(
        OneCardLogic.hasPlayable(['S9'], topCard: 'H7', activeSuit: 'H'),
        false,
      );
    });
  });

  group('공격 카드 값/종류', () {
    test('attackValue: 2→2, A→3, 흑백조커 JB→5, 컬러조커 JR→7, 일반→0', () {
      expect(OneCardLogic.attackValue('H2'), 2);
      expect(OneCardLogic.attackValue('SA'), 3);
      expect(OneCardLogic.attackValue('DA'), 3);
      expect(OneCardLogic.attackValue('JB'), 5);
      expect(OneCardLogic.attackValue('JR'), 7);
      expect(OneCardLogic.attackValue('H9'), 0);
      expect(OneCardLogic.attackValue('H7'), 0); // 7은 와일드지 공격 아님.
    });

    test('attackKindOf: two / ace / joker / 빈문자', () {
      expect(OneCardLogic.attackKindOf('H2'), 'two');
      expect(OneCardLogic.attackKindOf('SA'), 'ace');
      expect(OneCardLogic.attackKindOf('JR'), 'joker');
      expect(OneCardLogic.attackKindOf('JB'), 'joker');
      expect(OneCardLogic.attackKindOf('H9'), '');
    });

    test('attackTier: 2<A<조커, 그 외 0', () {
      expect(OneCardLogic.attackTier('H2'), 1);
      expect(OneCardLogic.attackTier('SA'), 2);
      expect(OneCardLogic.attackTier('JR'), 3);
      expect(OneCardLogic.attackTier('JB'), 3);
      expect(OneCardLogic.attackTier('H9'), 0);
      expect(OneCardLogic.attackTier('H7'), 0);
    });

    test('kindTier: 공격 종류 문자 → 티어', () {
      expect(OneCardLogic.kindTier('two'), 1);
      expect(OneCardLogic.kindTier('ace'), 2);
      expect(OneCardLogic.kindTier('joker'), 3);
      expect(OneCardLogic.kindTier(''), 0);
    });
  });

  group('받아치기 (같은 티어 이상)', () {
    // 2 공격(tier 1)은 2·A·조커로 받아칠 수 있다.
    test('2 공격은 2/A/조커로 받아치고, 일반 카드는 불가', () {
      for (final c in ['S2', 'SA', 'JR', 'JB']) {
        expect(
          OneCardLogic.canPlay(
            c,
            topCard: 'H2',
            activeSuit: 'H',
            pending: 2,
            attackKind: 'two',
          ),
          true,
          reason: '$c 로 2 공격을 받아칠 수 있어야 한다',
        );
      }
      expect(
        OneCardLogic.canPlay(
          'H9',
          topCard: 'H2',
          activeSuit: 'H',
          pending: 2,
          attackKind: 'two',
        ),
        false,
      );
    });

    // A 공격(tier 2)은 A·조커로만. 2(하위)로는 못 받아친다.
    test('A 공격은 A/조커로만 받아치고, 2(하위)·일반은 불가', () {
      expect(
        OneCardLogic.canPlay(
          'DA',
          topCard: 'SA',
          activeSuit: 'S',
          pending: 3,
          attackKind: 'ace',
        ),
        true,
      );
      expect(
        OneCardLogic.canPlay(
          'JR',
          topCard: 'SA',
          activeSuit: 'S',
          pending: 3,
          attackKind: 'ace',
        ),
        true,
      );
      expect(
        OneCardLogic.canPlay(
          'H2',
          topCard: 'SA',
          activeSuit: 'S',
          pending: 3,
          attackKind: 'ace',
        ),
        false,
      );
      expect(
        OneCardLogic.canPlay(
          'H9',
          topCard: 'SA',
          activeSuit: 'S',
          pending: 3,
          attackKind: 'ace',
        ),
        false,
      );
    });

    // 조커 공격(tier 3)은 조커로만 + 예외로 스페이드 A.
    test('조커 공격은 조커로만, 예외로 스페이드 A 로 막을 수 있다', () {
      expect(
        OneCardLogic.canPlay(
          'JB',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 7,
          attackKind: 'joker',
        ),
        true,
      );
      // 스페이드 A 예외.
      expect(
        OneCardLogic.canPlay(
          'SA',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 7,
          attackKind: 'joker',
        ),
        true,
      );
      // 다른 무늬 A 는 조커를 막지 못한다(스페이드 A 만 예외).
      expect(
        OneCardLogic.canPlay(
          'HA',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 7,
          attackKind: 'joker',
        ),
        false,
      );
      // 2 / 일반도 불가.
      expect(
        OneCardLogic.canPlay(
          'S2',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 7,
          attackKind: 'joker',
        ),
        false,
      );
      expect(
        OneCardLogic.canPlay(
          'S9',
          topCard: 'JR',
          activeSuit: 'S',
          pending: 7,
          attackKind: 'joker',
        ),
        false,
      );
    });

    test('누적 합산 예: 2+A=5, JR+JB=12', () {
      expect(
        OneCardLogic.attackValue('H2') + OneCardLogic.attackValue('SA'),
        5,
      );
      expect(
        OneCardLogic.attackValue('JR') + OneCardLogic.attackValue('JB'),
        12,
      );
    });

    test('playableCards: 조커 공격 방어 상황 — 손패의 조커와 스페이드 A만', () {
      final hand = ['H9', 'S2', 'JB', 'C7', 'SA', 'HA'];
      final playable = OneCardLogic.playableCards(
        hand,
        topCard: 'JR',
        activeSuit: 'S',
        pending: 7,
        attackKind: 'joker',
      );
      expect(playable.toSet(), {'JB', 'SA'});
    });
  });

  group('7 무늬 변경 (와일드)', () {
    test('isWildSuit', () {
      expect(OneCardLogic.isWildSuit('H7'), true);
      expect(OneCardLogic.isWildSuit('H8'), false);
      expect(OneCardLogic.isWildSuit('JR'), false);
    });

    test('조커는 평시(공격 없음) 어떤 더미 위에도 낼 수 있다', () {
      expect(OneCardLogic.canPlay('JR', topCard: 'H7', activeSuit: 'H'), true);
      expect(OneCardLogic.canPlay('JB', topCard: 'S10', activeSuit: 'S'), true);
    });

    test('와일드 무늬지정 후: 더미가 조커여도 지정 무늬로 이어간다', () {
      expect(OneCardLogic.canPlay('C5', topCard: 'JR', activeSuit: 'C'), true);
      expect(OneCardLogic.canPlay('H5', topCard: 'JR', activeSuit: 'C'), false);
      expect(OneCardLogic.canPlay('JB', topCard: 'JR', activeSuit: 'C'), true);
    });
  });

  group('드로우 / 재활용', () {
    test('충분한 덱에서 정상 뽑기', () {
      final deck = ['C3', 'D4', 'S5', 'H6'];
      final res = OneCardLogic.draw(deck, const [], 2, rng: Random(1));
      expect(res.drawn.length, 2);
      expect(res.deck.length, 2);
      // 원본 불변.
      expect(deck.length, 4);
    });

    test('덱 소진 시 버린 더미를 섞어 재활용 (keepTop 없이)', () {
      final deck = <String>['C3']; // 1장뿐.
      final discard = ['S5', 'D8', 'H7'];
      final res = OneCardLogic.draw(deck, discard, 3, rng: Random(1));
      // 덱1 + 재활용3 중 3장 뽑기 가능.
      expect(res.drawn.length, 3);
      // 뽑힌 카드는 모두 원래 풀(덱+버린더미)에서 나온다.
      for (final c in res.drawn) {
        expect({'C3', 'S5', 'D8', 'H7'}.contains(c), true);
      }
    });

    test('재활용도 모자라면 가능한 만큼만 뽑는다', () {
      final deck = <String>['C3'];
      final res = OneCardLogic.draw(deck, const [], 4, rng: Random(1));
      // 덱1장 + 재활용 풀 없음 → 1장만.
      expect(res.drawn.length, 1);
    });

    test('카드 보존 불변식: 뽑힌+남은덱+남은버린더미 = 원래 풀(중복 없음)', () {
      final deck = ['C3', 'D4', 'S5'];
      final discard = ['H6', 'H7', 'S8', 'D9'];
      final res = OneCardLogic.draw(deck, discard, 5, rng: Random(3));
      final after = <String>[...res.drawn, ...res.deck, ...res.discard]..sort();
      final before = <String>[...deck, ...discard]..sort();
      expect(after, before); // 한 장도 새로 생기거나 사라지지 않는다.
    });
  });

  group('승리', () {
    test('손패 0이면 승리', () {
      expect(OneCardLogic.isWinner([]), true);
      expect(OneCardLogic.isWinner(['H3']), false);
    });
  });

  group('표시', () {
    test('label', () {
      expect(OneCardLogic.label('H7'), '♥7');
      expect(OneCardLogic.label('S10'), '♠10');
      expect(OneCardLogic.label('JR'), '조커(빨강)');
      expect(OneCardLogic.label('JB'), '조커(검정)');
    });
  });
}
