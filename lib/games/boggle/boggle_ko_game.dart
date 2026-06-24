import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'boggle_rules.dart';
import 'boggle_view.dart';

/// 보글(한글): 같은 NxN 한글 음절판에서 제한시간 동안 한글 단어를 많이 찾는 쪽이 승리.
///
/// 영어 보글과 동일한 [BoggleView]를 [KoreanBoggleRules]로 구동한다.
/// [size]로 4x4·5x5·6x6 모드를 만든다.
class BoggleKoGame extends GameDefinition {
  /// 격자 한 변(4·5·6).
  final int size;

  const BoggleKoGame({this.size = 4});

  KoreanBoggleRules get rules => KoreanBoggleRules(size: size);

  @override
  // 4x4는 기존 id 'boggle_ko' 유지(하위 호환), 그 외는 'boggle_ko5'/'boggle_ko6'.
  String get id => size == 4 ? 'boggle_ko' : 'boggle_ko$size';

  @override
  String get title => '보글(한글) $size×$size';

  @override
  String get subtitle => '같은 판에서 한글 단어 많이 찾기';

  @override
  IconData get icon => Icons.translate_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF56AB2F), Color(0xFFA8E063)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final grid = rules.randomBoard(Random());
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
          rules: rules,
        );
      },
    );
  }
}
