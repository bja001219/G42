import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../core/game_session.dart';
import '../../core/models/room.dart';
import '../../theme.dart';
import 'boggle_logic.dart';
import 'boggle_rules.dart';
import 'boggle_view.dart';

/// 보글(단어 찾기) — 영어/한글 + 4×4~10×10 크기를 **방장이 시작 전에 설정**한다.
///
/// 설정값(`{size, lang}`)은 방 대기실에서 정해져 `room.state['config']`에 저장되고,
/// 게임 시작 시 그 설정으로 글자판을 생성한다. 인게임에서는 config로부터 [BoggleRules]를
/// 만들어 영어/한글·크기를 모두 한 위젯([BoggleView])으로 구동한다.
class BoggleGame extends GameDefinition {
  const BoggleGame();

  static const int minSize = 4;
  static const int maxSize = 10;

  @override
  String get id => 'boggle';

  @override
  String get title => '보글';

  @override
  String get subtitle => '글자판에서 단어 찾기 · 크기/언어 선택';

  @override
  IconData get icon => Icons.grid_view_rounded;

  @override
  List<Color> get gradient => const [Color(0xFFF7971E), Color(0xFFFFD200)];

  @override
  bool get hasSetup => true;

  @override
  Map<String, dynamic> get defaultConfig => const <String, dynamic>{
    'size': 8,
    'lang': 'ko',
  };

  // ---- 설정 정규화 / 규칙 빌드 ----------------------------------------------

  static int _clampSize(int s) => s.clamp(minSize, maxSize);

  /// 외부에서 들어온 설정을 안전한 {size:int, lang:'ko'|'en'}로 정규화한다.
  static Map<String, dynamic> _normalize(Map<String, dynamic> config) {
    final size = _clampSize((config['size'] as num?)?.toInt() ?? 8);
    final lang = (config['lang'] as String?) == 'en' ? 'en' : 'ko';
    return <String, dynamic>{'size': size, 'lang': lang};
  }

  static BoggleRules _rulesFor(Map<String, dynamic> config) {
    final c = _normalize(config);
    final size = c['size'] as int;
    return c['lang'] == 'en'
        ? EnglishBoggleRules(size: size)
        : KoreanBoggleRules(size: size);
  }

  @override
  String configSummary(Map<String, dynamic> config) {
    final c = _normalize(config);
    final size = c['size'] as int;
    final lang = c['lang'] == 'en' ? 'English' : '한글';
    return '$size×$size · $lang';
  }

  // ---- 초기 상태 -------------------------------------------------------------

  Map<String, dynamic> _initialState(
    List<String> playerIds,
    Map<String, dynamic> config,
  ) {
    final cfg = _normalize(config);
    final rules = _rulesFor(cfg);
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
      'config': cfg, // 인게임에서 규칙(크기/언어) 복원용.
      'phase': 'playing',
      'found': found,
      'scores': scores,
      'done': done,
      // 핫시트 순차 진행용. 온라인에서는 무시.
      'hsTurn': playerIds.isNotEmpty ? playerIds.first : '',
    };
  }

  @override
  Map<String, dynamic> createInitialState(List<String> playerIds) =>
      _initialState(playerIds, defaultConfig);

  @override
  Map<String, dynamic> createInitialStateConfigured(
    List<String> playerIds,
    Map<String, dynamic> config,
  ) => _initialState(playerIds, config.isEmpty ? defaultConfig : config);

  // ---- 설정 UI ---------------------------------------------------------------

  @override
  Widget buildSetup(
    BuildContext context,
    Map<String, dynamic> config,
    ValueChanged<Map<String, dynamic>> onChanged,
  ) => _BoggleSetup(config: _normalize(config), onChanged: onChanged);

  // ---- 인게임 ----------------------------------------------------------------

  @override
  Widget buildGame(BuildContext context, GameSession session) {
    return StreamBuilder<Room>(
      stream: session.watch(),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final config = _normalize(
          Map<String, dynamic>.from(
            (room.state['config'] as Map?) ?? defaultConfig,
          ),
        );
        return BoggleView(
          session: session,
          room: room,
          createInitialState: (ids) => _initialState(ids, config),
          firstTurn: firstTurn,
          rules: _rulesFor(config),
        );
      },
    );
  }
}

/// 보글 시작 전 설정(언어 + 보드 크기). 부모(설정 시트)가 상태를 들고 있고,
/// 이 위젯은 현재 [config]를 그리며 변경 시 [onChanged]로 새 맵을 올려준다.
class _BoggleSetup extends StatelessWidget {
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _BoggleSetup({required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final size = (config['size'] as num?)?.toInt() ?? 8;
    final lang = (config['lang'] as String?) ?? 'ko';
    final duration = BoggleLogic.durationFor(size);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('언어', style: _labelStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _langButton('한글', 'ko', lang)),
            const SizedBox(width: 10),
            Expanded(child: _langButton('English', 'en', lang)),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Text('보드 크기', style: _labelStyle),
            const Spacer(),
            Text(
              '$size × $size',
              style: const TextStyle(
                color: G42Colors.accent,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        Slider(
          value: size.toDouble(),
          min: BoggleGame.minSize.toDouble(),
          max: BoggleGame.maxSize.toDouble(),
          divisions: BoggleGame.maxSize - BoggleGame.minSize,
          label: '$size×$size',
          activeColor: G42Colors.accent,
          onChanged: (v) =>
              onChanged(<String, dynamic>{...config, 'size': v.round()}),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('4×4 쉬움', style: _hintStyle),
            Text('10×10 큰 판', style: _hintStyle),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: G42Colors.surfaceHi,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '칸 ${size * size}개 · 제한시간 약 $duration초\n'
            '${lang == 'en' ? '영어 단어' : '한글 단어'}를 인접한 글자로 이어 찾으세요.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _langButton(String label, String value, String current) {
    final sel = value == current;
    return GestureDetector(
      onTap: () => onChanged(<String, dynamic>{...config, 'lang': value}),
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
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.white60,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
  static const _hintStyle = TextStyle(color: Colors.white38, fontSize: 11);
}
