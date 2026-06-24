import '../core/game_definition.dart';
import 'battleship/battleship_game.dart';
import 'blackjack/blackjack_game.dart';
import 'boggle/boggle_game.dart';
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
  // 보글: 단일 게임. 영/한 + 4×4~10×10 크기는 방장이 시작 전 설정.
  const BoggleGame(),
  GoStopGame(),
];
