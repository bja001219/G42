import '../core/game_definition.dart';
import 'chess/chess_game.dart';
import 'omok/omok_game.dart';
import 'battleship/battleship_game.dart';

/// 앱에 내장된 게임 목록.
///
/// 새 게임을 추가하려면 여기에 한 줄만 더하면 로비에 자동으로 나타난다.
final List<GameDefinition> builtInGames = <GameDefinition>[
  ChessGame(),
  OmokGame(),
  BattleshipGame(),
];
