import '../core/game_definition.dart';
import 'battleship/battleship_game.dart';
import 'blackjack/blackjack_game.dart';
import 'boggle/boggle_game.dart';
import 'boggle/boggle_ko_game.dart';
import 'chess/chess_game.dart';
import 'gostop/gostop_game.dart';
import 'omok/omok_game.dart';
import 'onecard/onecard_game.dart';
import 'reaction/reaction_game.dart';

/// 앱에 내장된 게임 목록.
///
/// 새 게임을 추가하려면 여기에 한 줄만 더하면 로비에 자동으로 나타난다.
final List<GameDefinition> builtInGames = <GameDefinition>[
  ChessGame(),
  OmokGame(),
  BattleshipGame(),
  ReactionGame(),
  BlackjackGame(),
  OneCardGame(),
  // 보글: 4x4(클래식)·5x5(Big Boggle)·6x6·10x10(큰판) + 한글판도 동일하게 4종.
  const BoggleGame(size: 4),
  const BoggleGame(size: 5),
  const BoggleGame(size: 6),
  const BoggleGame(size: 10),
  const BoggleKoGame(size: 4),
  const BoggleKoGame(size: 5),
  const BoggleKoGame(size: 6),
  const BoggleKoGame(size: 10),
  GoStopGame(),
];
