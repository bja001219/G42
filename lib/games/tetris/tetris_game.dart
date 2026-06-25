import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import 'tetris_view.dart';

/// 테트리스 1:1 대전.
///
/// 두 플레이어가 각자 자기 보드를 굴리고, 라인을 지우면 상대에게 가비지 줄을
/// 보낸다(콤보/백투백 보너스 포함). 먼저 천장까지 쌓여 탑아웃되는 쪽이 패배.
///
/// 동기화: 각 클라이언트는 room.state 의 자기 좌석 칸(s0/s1)에만
/// {board, lines, garbage} 를 dotted-path 머지로 쓴다. 상대 좌석을 미러링하고,
/// 상대의 누적 가비지 증가분을 받아 자기 보드에 적용한다. 자세한 내용은
/// [TetrisVersusController] 참고.
class TetrisGame extends GameDefinition {
  @override
  String get id => 'tetris';

  @override
  String get title => '테트리스';

  @override
  String get subtitle => '라인을 지워 상대에게 줄을 보내세요';

  @override
  IconData get icon => Icons.grid_4x4_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF6366F1), Color(0xFF22D3EE)];

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) =>
      <String, dynamic>{
        's0': _emptySeat(),
        's1': _emptySeat(),
      };

  static Map<String, dynamic> _emptySeat() => <String, dynamic>{
        'board': '',
        'lines': 0,
        'garbage': 0,
      };

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return TetrisView(session: session);
  }
}
