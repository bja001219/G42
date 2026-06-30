import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'minesweeper_logic.dart';
import 'minesweeper_view.dart';

/// 지뢰찾기 — **둘이서 같은 보드를 함께** 푸는 협동 게임.
///
/// 두 플레이어가 하나의 지뢰밭을 실시간으로 공유한다. 칸을 누르면 열리고, 화면 아래
/// "깃발 모드" 버튼을 켜고 누르면 깃발을 꽂는다. 함께 안전한 칸을 모두 열면 클리어,
/// 누구든 지뢰를 밟으면 그 판은 끝(둘 다 다시하기/게임 선택 가능).
///
/// 난이도(보드 크기·지뢰 수)는 **방장이 시작 전에** 고른다(보글과 동일한 설정 흐름).
class MinesweeperGame extends GameDefinition {
  /// 난이도 프리셋: level → {rows, cols, mines}.
  static const Map<String, Map<String, int>> presets = {
    'easy': {'rows': 9, 'cols': 9, 'mines': 10},
    'normal': {'rows': 12, 'cols': 12, 'mines': 24},
    'hard': {'rows': 14, 'cols': 14, 'mines': 40},
  };

  static const Map<String, String> levelNames = {
    'easy': '쉬움',
    'normal': '보통',
    'hard': '어려움',
  };

  @override
  String get id => 'minesweeper';

  @override
  String get title => '지뢰찾기';

  @override
  String get subtitle => '둘이 함께 지뢰를 피해 모두 열기 · 난이도 선택';

  @override
  IconData get icon => Icons.flag_rounded;

  @override
  List<Color> get gradient => const [Color(0xFF3A6073), Color(0xFF16222A)];

  @override
  bool get hasSetup => true;

  @override
  Map<String, dynamic> get defaultConfig => const <String, dynamic>{
    'level': 'easy',
  };

  /// 설정 → 안전한 level 문자열.
  static String _level(Map<String, dynamic> config) {
    final lv = config['level'] as String?;
    return presets.containsKey(lv) ? lv! : 'easy';
  }

  static Map<String, int> _preset(Map<String, dynamic> config) =>
      presets[_level(config)]!;

  @override
  String configSummary(Map<String, dynamic> config) {
    final p = _preset(config);
    return '${p['rows']}×${p['cols']} · 지뢰 ${p['mines']}';
  }

  Map<String, dynamic> _initialState(Map<String, dynamic> config) {
    final level = _level(config);
    final p = presets[level]!;
    return MinesweeperState.fresh(
      rows: p['rows']!,
      cols: p['cols']!,
      mines: p['mines']!,
      config: <String, dynamic>{'level': level},
    );
  }

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) =>
      _initialState(defaultConfig);

  @override
  Map<String, dynamic> createInitialStateConfigured(
    List<String> playerIds,
    Map<String, dynamic> config,
  ) => _initialState(config.isEmpty ? defaultConfig : config);

  @override
  Widget buildSetup(
    BuildContext context,
    Map<String, dynamic> config,
    ValueChanged<Map<String, dynamic>> onChanged,
  ) => _MinesweeperSetup(level: _level(config), onChanged: onChanged);

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return MinesweeperView(session: session, room: room);
      },
    );
  }
}

/// 시작 전 난이도 선택(쉬움/보통/어려움). 부모(설정 시트)가 상태를 들고 있고
/// 이 위젯은 현재 level을 그리며 변경 시 onChanged로 새 맵을 올린다.
class _MinesweeperSetup extends StatelessWidget {
  final String level;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _MinesweeperSetup({required this.level, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MinesweeperGame.presets[level]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('난이도', style: _labelStyle),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final lv in MinesweeperGame.presets.keys) ...[
              Expanded(child: _levelButton(lv)),
              if (lv != MinesweeperGame.presets.keys.last)
                const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: G42Colors.surfaceHi,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${p['rows']}×${p['cols']} 보드 · 지뢰 ${p['mines']}개\n'
            '둘이 같은 보드를 함께 풀어요. 칸을 누르면 열리고, 아래 "깃발 모드"를 켜고 '
            '누르면 깃발을 꽂아요. 안전한 칸을 모두 열면 클리어!',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _levelButton(String lv) {
    final sel = lv == level;
    final p = MinesweeperGame.presets[lv]!;
    return GestureDetector(
      onTap: () => onChanged(<String, dynamic>{'level': lv}),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel
              ? G42Colors.accent.withValues(alpha: 0.20)
              : G42Colors.surfaceHi,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? G42Colors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              MinesweeperGame.levelNames[lv]!,
              style: TextStyle(
                color: sel ? Colors.white : Colors.white60,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${p['rows']}×${p['cols']}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
}
