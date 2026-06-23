import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'blackjack_logic.dart';
import 'blackjack_view.dart';

/// 블랙잭 (2인 헤드투헤드, 정식 룰 + 칩 베팅).
///
/// - 매 라운드 한 명이 '딜러', 다른 한 명이 '플레이어(베팅)' 가 되어 교대한다.
/// - 플레이어가 칩을 걸고 hit / stand / double down / split.
/// - 딜러는 17 이상까지 자동 진행(S17). 내추럴 블랙잭은 3:2.
/// - 승부에 따라 칩이 두 사람 사이에서 이동(제로섬). 누군가 칩이 0이면 매치 종료.
///
/// state(전부 평탄, 중첩 배열 없음):
///   'deck' `List<int>`, 'ptr' int,
///   'chips' `{pid:int}`, 'hands' `{pid:List<int>}`, 'splitHand' `List<int>`,
///   'dealer' pid, 'phase' 'bet'|'player'|'reveal',
///   'bet0' int, 'bet1' int, 'split' bool, 'activeHand' int,
///   'roundNo' int, 'lastDelta' int (플레이어 기준 직전 라운드 칩 증감)
class BlackjackGame extends GameDefinition {
  @override
  String get id => 'blackjack';

  @override
  String get title => '블랙잭';

  @override
  String get subtitle => '칩을 걸고 21에 도전 — 딜러를 이겨라';

  @override
  IconData get icon => Icons.style_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF11998E), Color(0xFF38EF7D)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final deck = BlackjackLogic.shuffledDeck();
    final host = playerIds.first;
    final guest = playerIds.length > 1 ? playerIds[1] : host;

    final chips = <String, dynamic>{};
    final hands = <String, dynamic>{};
    for (final pid in playerIds) {
      chips[pid] = BlackjackLogic.startingChips;
      hands[pid] = <int>[];
    }

    return {
      'deck': deck,
      'ptr': 0,
      'chips': chips,
      'hands': hands,
      'splitHand': <int>[],
      // 1라운드: 호스트(seat0)가 플레이어(베팅·선공), 게스트(seat1)가 딜러.
      'dealer': guest,
      'phase': 'bet',
      'bet0': 0,
      'bet1': 0,
      'split': false,
      'activeHand': 0,
      'roundNo': 1,
      'lastDelta': 0,
    };
  }

  // 첫 차례는 기본값(호스트) = 1라운드 베팅 플레이어.

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return BlackjackView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
        );
      },
    );
  }
}
