import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'onecard_logic.dart';
import 'onecard_view.dart';

/// 원카드(Uno류): 버린 더미 맨 위와 무늬 또는 숫자가 맞는 카드를 내며
/// 손패를 먼저 비우면 승리. 2(공격)/A(스킵)/7(무늬변경) 특수카드.
class OneCardGame extends GameDefinition {
  /// 조커 정식 사용 여부. true면 빨강/검정 조커 2장이 덱에 포함되며
  /// 공격 +5 · 조커-전용 방어 · 와일드 무늬지정 규칙이 적용된다.
  static const bool useJokers = true;

  @override
  String get id => 'onecard';

  @override
  String get title => '원카드';

  @override
  String get subtitle => '카드를 먼저 다 내면 승리';

  @override
  IconData get icon => Icons.filter_none_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFFC466B), Color(0xFF3F5EFB)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final deck = OneCardLogic.freshDeck(jokers: useJokers, rng: Random());

    // 각자 7장 분배.
    final hands = <String, dynamic>{};
    for (final pid in playerIds) {
      final hand = <String>[];
      for (var i = 0; i < OneCardLogic.handSize; i++) {
        hand.add(deck.removeLast());
      }
      hands[pid] = hand;
    }

    // 시작 카드는 특수효과가 없는 일반 카드여야 깔끔하다.
    // 덱에서 특수(2/A/7/조커)가 아닌 카드를 찾아 맨 위로.
    String top = deck.removeLast();
    final stash = <String>[];
    while (_isSpecial(top) && deck.isNotEmpty) {
      stash.add(top);
      top = deck.removeLast();
    }
    deck.addAll(stash); // 미사용 특수카드는 덱으로 되돌림.

    return {
      'deck': deck,
      'discardTop': top,
      'activeSuit': OneCardLogic.suitOf(top) ?? 'S',
      'hands': hands,
      'pending': 0,
      'attackKind': '', // 'two' | 'joker' | ''
      'jokers': useJokers,
      'lastAction': '', // UI 안내 문구
    };
  }

  static bool _isSpecial(String card) =>
      OneCardLogic.isJoker(card) ||
      OneCardLogic.isSkip(card) ||
      OneCardLogic.isWildSuit(card) ||
      OneCardLogic.rankOf(card) == '2';

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return OneCardView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
        );
      },
    );
  }
}
