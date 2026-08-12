import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../../core/game_session.dart';
import '../../core/models/room.dart';
import 'tetris_engine.dart';
import 'tetris_net.dart';

/// Drives a 1-vs-1 online Tetris battle on top of a G42 [GameSession].
///
/// Each client runs its own [TetrisEngine] locally and writes ONLY its own seat
/// cell (`state.s0` / `state.s1`) via a dotted-path merge, so the two players'
/// continuous board writes never clobber each other. We mirror the opponent's
/// seat (board + lines) and apply the increase of their cumulative "garbage
/// sent" counter as incoming garbage. The match is decided by the player who
/// tops out: they write `status=finished` + `winner=<opponent>` exactly once,
/// and G42's [GameHostScreen] shows the result overlay and records stats.
class TetrisVersusController extends ChangeNotifier {
  final GameSession session;
  final TetrisEngine player = TetrisEngine();

  /// My seat index (0 = host, 1 = guest). -1 until the first room snapshot.
  int _seat = -1;
  Room? _room;
  bool _finished = false;

  // ---- Opponent mirror (decoded from snapshots) ----
  List<List<Color?>> _oppBoard = TetrisNet.emptyBoard();
  int _oppLines = 0;
  List<List<Color?>> get opponentBoard => _oppBoard;
  int get opponentLines => _oppLines;
  bool get opponentPresent => _room?.isFull ?? false;

  // ---- Garbage accounting (both counters are cumulative / monotonic) ----
  /// Total garbage rows I have sent to the opponent (published in my seat).
  int _garbageSent = 0;

  /// Highest opponent "garbage sent" total I have already applied to my board.
  int _consumedGarbage = 0;

  bool _dirty = true; // My board changed since the last publish.
  Timer? _publishTimer;
  StreamSubscription<Room>? _roomSub;

  TetrisVersusController(this.session) {
    // Garbage exchange seam: the opponent side is the network. The engine has
    // already folded combo / back-to-back bonuses into [g].
    player.onAttack = (g) {
      if (g > 0) {
        _garbageSent += g;
        _dirty = true;
      }
    };
    player.onToppedOut = _onToppedOut;
    player.addListener(_relay);

    _roomSub = session.watch().listen(_onRoom);
    // Publish our board on a fixed, modest cadence (only when it changed) so
    // Firestore writes stay bounded regardless of how busy the game is.
    _publishTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _publish(),
    );
  }

  void _relay() {
    _dirty = true;
    notifyListeners();
  }

  String? get _opponentId => _room?.opponentOf(session.myPlayerId)?.id;

  void _onRoom(Room room) {
    _room = room;
    if (_seat < 0 && room.playerIds.contains(session.myPlayerId)) {
      _seat = session.seatIndex(room, session.myPlayerId);
    }

    final oppSeat = _seat == 0 ? 1 : 0;
    final raw = room.state['s$oppSeat'];
    if (raw is Map) {
      _oppBoard = TetrisNet.decodeBoard(raw['board'] as String?);
      _oppLines = (raw['lines'] as num?)?.toInt() ?? 0;
      final oppGarbage = (raw['garbage'] as num?)?.toInt() ?? 0;
      if (oppGarbage > _consumedGarbage) {
        if (!_finished) player.receiveGarbage(oppGarbage - _consumedGarbage);
        _consumedGarbage = oppGarbage;
      } else if (oppGarbage < _consumedGarbage) {
        // A fresh round reset the opponent's counter — resync the baseline.
        _consumedGarbage = oppGarbage;
      }
    }

    if (room.status == RoomStatus.finished && !_finished) {
      _finished = true;
      player.freeze();
    }
    notifyListeners();
  }

  void _publish() {
    if (_finished || _seat < 0 || !_dirty) return;
    _dirty = false;
    session.patch({'state.s$_seat': _seatPayload()});
  }

  Map<String, dynamic> _seatPayload() => <String, dynamic>{
    'board': TetrisNet.encodeBoard(player),
    'lines': player.lines,
    'garbage': _garbageSent,
  };

  void _onToppedOut() {
    if (_finished) return;
    _finished = true;
    player.freeze();
    if (_seat < 0) {
      notifyListeners();
      return;
    }
    // The loser authoritatively ends the match (single writer → no race), also
    // publishing the final topped-out board so the winner sees it.
    final patch = <String, dynamic>{'state.s$_seat': _seatPayload()};
    final opp = _opponentId;
    if (opp != null) {
      patch['status'] = RoomStatus.finished.name;
      patch['winner'] = opp;
    }
    session.patch(patch);
    notifyListeners();
  }

  // ---- Player input proxies ----
  void rotate() => player.rotate();
  void moveLeft() => player.moveLeft();
  void moveRight() => player.moveRight();
  void softDrop() => player.softDrop();
  void hardDrop() => player.hardDrop();
  void hold() => player.holdPiece();

  @override
  void dispose() {
    _publishTimer?.cancel();
    _roomSub?.cancel();
    player.removeListener(_relay);
    player.dispose();
    super.dispose();
  }
}
