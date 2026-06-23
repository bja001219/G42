import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'boggle_logic.dart';
import 'boggle_rules.dart';
import 'boggle_view.dart';

/// 보글: 같은 4x4 글자판에서 제한시간 동안 인접 경로로 단어를 많이 찾는 쪽이 승리.
class BoggleGame extends GameDefinition {
  @override
  String get id => 'boggle';

  @override
  String get title => '보글';

  @override
  String get subtitle => '같은 판에서 단어 많이 찾기';

  @override
  IconData get icon => Icons.abc_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFF7971E), Color(0xFFFFD200)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final grid = BoggleLogic.randomBoard(Random());
    final found = <String, dynamic>{};
    final scores = <String, dynamic>{};
    final done = <String, dynamic>{};
    for (final pid in playerIds) {
      found[pid] = <String>[];
      scores[pid] = 0;
      done[pid] = false;
    }
    return {
      'grid': grid,
      'phase': 'playing',
      'found': found,
      'scores': scores,
      'done': done,
      // 핫시트 순차 진행용: 현재 플레이 차례. 온라인에서는 무시.
      'hsTurn': playerIds.isNotEmpty ? playerIds.first : '',
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
        return BoggleView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
          rules: const EnglishBoggleRules(),
        );
      },
    );
  }
}
