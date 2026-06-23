import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'chess_board.dart';
import 'chess_logic.dart';

/// 체스 — 완전한 합법수 엔진 + 보드 UI.
///
/// seat 0(호스트) = 백(선공), seat 1 = 흑.
class ChessGame extends GameDefinition {
  @override
  String get id => 'chess';

  @override
  String get title => '체스';

  @override
  String get subtitle => '클래식 2인 전략';

  @override
  IconData get icon => Icons.castle_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF4E5BA6), Color(0xFF8A63D2)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final pos = ChessPosition.initial();
    return <String, dynamic>{
      'board': pos.board,
      'castling': pos.castling,
      'enPassant': pos.enPassant,
    };
  }

  @override
  String firstTurn(List<String> playerIds) => playerIds.first; // 호스트=백 선공

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
          child: ChessBoard(
            session: session,
            room: room,
            createInitialState: createInitialState,
            firstTurn: firstTurn,
          ),
        );
      },
    );
  }
}
