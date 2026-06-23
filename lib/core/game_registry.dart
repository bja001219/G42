import '../games/all_games.dart';
import 'game_definition.dart';

/// 등록된 게임 목록 제공자. 로비가 이걸 읽어 카드를 그린다.
abstract class GameRegistry {
  static final List<GameDefinition> games = List.unmodifiable(builtInGames);

  static GameDefinition? byId(String id) {
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }
}
