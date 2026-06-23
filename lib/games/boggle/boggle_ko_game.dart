import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'boggle_ko_logic.dart';
import 'boggle_rules.dart';
import 'boggle_view.dart';

/// 보글(한글): 같은 한글 음절판에서 제한시간 동안 한글 단어를 많이 찾는 쪽이 승리.
///
/// 영어 보글과 동일한 [BoggleView]를 [KoreanBoggleRules]로 구동한다.
class BoggleKoGame extends GameDefinition {
  @override
  String get id => 'boggle_ko';

  @override
  String get title => '보글 (한글)';

  @override
  String get subtitle => '같은 판에서 한글 단어 많이 찾기';

  @override
  IconData get icon => Icons.translate_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF56AB2F), Color(0xFFA8E063)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final grid = KoBoggleLogic.randomBoard(Random());
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
      // 핫시트 순차 진행용. 온라인에서는 무시.
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
          rules: const KoreanBoggleRules(),
        );
      },
    );
  }
}
