import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'battleship_logic.dart';
import 'battleship_view.dart';

/// 배틀쉽: 10x10 격자에 함대([5,4,3,2])를 숨기고 번갈아 폭격해
/// 상대 함대를 먼저 전멸시키면 승리.
class BattleshipGame extends GameDefinition {
  @override
  String get id => 'battleship';

  @override
  String get title => '배틀쉽';

  @override
  String get subtitle => '함대를 숨기고 먼저 격침';

  @override
  IconData get icon => Icons.sailing_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF2193B0), Color(0xFF6DD5ED)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final boards = <String, dynamic>{};
    final shots = <String, dynamic>{};
    final ready = <String, dynamic>{};
    for (final pid in playerIds) {
      boards[pid] = BattleshipLogic.emptyBoard();
      shots[pid] = BattleshipLogic.emptyShots();
      ready[pid] = false;
    }
    return {
      'phase': 'placing',
      'boards': boards,
      'shots': shots,
      'ready': ready,
    };
  }

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return BattleshipView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
        );
      },
    );
  }
}
