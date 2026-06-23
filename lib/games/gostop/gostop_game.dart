import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'gostop_logic.dart';
import 'gostop_view.dart';

/// 고스톱(2인 맞고): 화투 48장 + 보너스 3장으로 번갈아 패를 내고,
/// 7점 이상이면 고/스톱을 선택해 점수를 겨룬다.
class GoStopGame extends GameDefinition {
  @override
  String get id => 'gostop';

  @override
  String get title => '고스톱';

  @override
  String get subtitle => '둘이 치는 맞고';

  @override
  IconData get icon => Icons.style_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFE53935), Color(0xFFFFB300)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    return GoStopLogic.createInitialState(playerIds, seed);
  }

  /// 첫 판은 무작위로 선을 정한다(호스트가 1회 호출).
  @override
  String firstTurn(List<String> playerIds) {
    if (playerIds.isEmpty) return '';
    return playerIds[Random().nextInt(playerIds.length)];
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
        return GoStopView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
        );
      },
    );
  }
}
