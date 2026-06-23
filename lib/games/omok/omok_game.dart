import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'omok_board.dart';
import 'omok_logic.dart';

/// 오목 (15x15 자유 5목).
///
/// - seat 0(호스트) = 흑(선공), seat 1(게스트) = 백.
/// - state: { 'board': 225자 String, 'lastMove': int }
class OmokGame extends GameDefinition {
  @override
  String get id => 'omok';

  @override
  String get title => '오목';

  @override
  String get subtitle => '5목을 먼저 만들면 승리';

  @override
  IconData get icon => Icons.grid_on_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFE8A87C), Color(0xFFC38D5F)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) => {
    'board': emptyOmokBoard(),
    'lastMove': -1,
  };

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: OmokBoard(
            session: session,
            room: room,
            onRematch: () => session.rematch(
              createInitialState(room.playerIds),
              firstTurn(room.playerIds),
            ),
          ),
        );
      },
    );
  }
}
