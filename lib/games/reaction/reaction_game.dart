import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'reaction_view.dart';

/// 반응속도 대결: 무작위 지연 후 초록 불에 더 빨리 반응한 사람이 라운드 승.
/// 베스트 오브 N(5선승 아님 — 본 게임은 3선취).
class ReactionGame extends GameDefinition {
  /// 선취 라운드 수.
  static const int targetWins = 3;

  @override
  String get id => 'reaction';

  @override
  String get title => '반응속도';

  @override
  String get subtitle => '초록 불에 먼저 반응하면 승리';

  @override
  IconData get icon => Icons.bolt_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFFF512F), Color(0xFFDD2476)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) {
    final wins = <String, dynamic>{};
    final reaction = <String, dynamic>{};
    for (final pid in playerIds) {
      wins[pid] = 0;
      reaction[pid] = 0; // 0 = 미기록
    }
    return {
      'phase': 'arming', // arming | go | roundResult | over
      'round': 1,
      'wins': wins,
      'reaction': reaction,
      // 'go' 관측 후 초록까지 기다릴 지연(ms). 각 기기가 로컬 기준으로 카운트.
      'goDelayMillis': 0,
      // 핫시트 진행용: 현재 측정 중인 플레이어 인덱스(0/1). 온라인에선 무시.
      'hotseatActive': 0,
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
        return ReactionView(
          session: session,
          room: room,
          createInitialState: createInitialState,
          firstTurn: firstTurn,
          targetWins: targetWins,
        );
      },
    );
  }
}
