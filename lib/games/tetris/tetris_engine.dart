import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import 'tetromino.dart';

/// Core Tetris game model. Holds all state and drives gravity via a timer.
/// UI listens through [ChangeNotifier].
///
/// (Ported from the standalone Tetris app's `TetrisGame`; renamed to
/// [TetrisEngine] so it doesn't collide with G42's `TetrisGame` GameDefinition.)
class TetrisEngine extends ChangeNotifier {
  static const int cols = 10;
  static const int rows = 24;

  /// After a piece can no longer fall it gets this grace period before locking.
  /// Sliding or rotating it restarts the countdown (up to [_maxLockResets]
  /// times) so you are not locked the instant it touches down.
  static const Duration _lockDelay = Duration(milliseconds: 1000);
  static const int _maxLockResets = 15;

  /// Color used for garbage rows pushed up by an opponent in versus mode.
  static const Color garbageColor = Color(0xFF64748B);

  /// Base garbage rows for clearing [lines] at once, before combo / back-to-back
  /// bonuses. Single clears send nothing; bigger clears send more.
  static int baseGarbage(int lines) {
    switch (lines) {
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 4;
      default:
        return 0;
    }
  }

  /// Total garbage rows for a clear, including combo and back-to-back bonuses.
  /// [combo] is 0-based (0 = first clear of a chain, 1 = second in a row, ...).
  /// [b2bActive] is whether a back-to-back was already running (the previous
  /// clear was a Tetris). Only Tetrises count toward back-to-back (no T-spin).
  static int attackFor(int lines, int combo, bool b2bActive) {
    if (lines <= 0) return 0;
    final b2bBonus = (lines == 4 && b2bActive) ? 1 : 0;
    return baseGarbage(lines) + _comboBonus(combo) + b2bBonus;
  }

  static int _comboBonus(int combo) {
    if (combo <= 0) return 0;
    const table = [0, 1, 1, 2, 2, 3, 3, 4]; // indexed by combo count
    return combo < table.length ? table[combo] : 4;
  }

  /// board[row][col] = null (empty) or the locked block's color.
  late List<List<Color?>> _board;
  List<List<Color?>> get board => _board;

  TetrominoType? _current;
  int _row = 0;
  int _col = 0;
  int _rot = 0;

  TetrominoType? _hold;
  TetrominoType? get hold => _hold;
  bool _canHold = true;

  final List<TetrominoType> _queue = [];
  final List<TetrominoType> _bag = [];
  final Random _rng = Random();

  /// Versus hooks (set by the versus controllers; null in single play).
  /// [onAttack] fires with the number of garbage rows to send the opponent,
  /// already including combo and back-to-back bonuses.
  void Function(int garbageRows)? onAttack;
  void Function()? onToppedOut;

  /// Visual / audio effect hook, independent of versus garbage logic. Fires
  /// with the number of lines cleared whenever a clear happens.
  void Function(int lines)? onClearEffect;

  /// Garbage rows queued by an opponent, applied after the next lock. Each
  /// entry is the gap column for that row.
  final List<int> _pendingGarbageHoles = [];
  int get pendingGarbage => _pendingGarbageHoles.length;

  /// Consecutive-clear combo (-1 = no active combo) and back-to-back state
  /// (true while consecutive Tetrises are chained). Both feed [attackFor].
  int _combo = -1;
  bool _b2b = false;
  int get combo => _combo;
  bool get backToBack => _b2b;

  int _score = 0;
  int _lines = 0;
  int _level = 1;
  bool _gameOver = false;
  bool _paused = false;

  int get score => _score;
  int get lines => _lines;
  int get level => _level;
  bool get isGameOver => _gameOver;
  bool get isPaused => _paused;

  Timer? _timer;

  /// Lock-delay timer (non-null while a grounded piece is counting down to its
  /// lock) and how many times the current piece has reset that countdown.
  Timer? _lockTimer;
  int _lockResets = 0;

  TetrisEngine() {
    _reset();
  }

  // ---------------------------------------------------------------------------
  // Public queries used by the UI
  // ---------------------------------------------------------------------------

  Color? get currentColor =>
      _current == null ? null : Tetromino.of(_current!).color;

  TetrominoType? get currentType => _current;
  int get currentRotation => _rot;
  int get currentCol => _col;

  TetrominoType get nextPiece {
    _ensureQueue();
    return _queue.first;
  }

  /// Absolute board cells occupied by the active piece.
  List<Cell> currentCells() {
    if (_current == null) return const [];
    return Tetromino.of(
      _current!,
    ).cells(_rot).map((c) => Cell(c.row + _row, c.col + _col)).toList();
  }

  /// Where the active piece would land (for the ghost preview).
  List<Cell> ghostCells() {
    if (_current == null) return const [];
    var drop = 0;
    while (!_collides(_current!, _row + drop + 1, _col, _rot)) {
      drop++;
    }
    return currentCells().map((c) => c.shift(drop, 0)).toList();
  }

  // ---------------------------------------------------------------------------
  // Player actions
  // ---------------------------------------------------------------------------

  void moveLeft() => _tryMove(0, -1);
  void moveRight() => _tryMove(0, 1);

  void softDrop() {
    if (_current == null || _gameOver || _paused) return;
    if (_tryMove(1, 0)) {
      _score += 1;
      notifyListeners();
    } else {
      _startLockTimer(); // Grounded: begin the lock-delay grace, don't lock yet.
    }
  }

  void hardDrop() {
    if (_current == null || _gameOver || _paused) return;
    var dropped = 0;
    while (!_collides(_current!, _row + 1, _col, _rot)) {
      _row++;
      dropped++;
    }
    _score += dropped * 2;
    _lock(); // Hard drop locks immediately, bypassing the lock delay.
  }

  /// Rotate the active piece 90° clockwise, with simple wall/floor kicks.
  void rotate() {
    if (_current == null || _gameOver || _paused) return;
    final newRot = (_rot + 1) % 4;
    // Try the rotation in place, then nudge it to fit near walls/floor.
    const kicks = <Cell>[
      Cell(0, 0),
      Cell(0, -1),
      Cell(0, 1),
      Cell(0, -2),
      Cell(0, 2),
      Cell(-1, 0),
      Cell(-1, -1),
      Cell(-1, 1),
    ];
    for (final k in kicks) {
      if (!_collides(_current!, _row + k.row, _col + k.col, newRot)) {
        _row += k.row;
        _col += k.col;
        _rot = newRot;
        _refreshLockState(); // A rotation near the floor buys lock-delay time.
        notifyListeners();
        return;
      }
    }
  }

  void holdPiece() {
    if (_current == null || _gameOver || _paused || !_canHold) return;
    final previous = _hold;
    _hold = _current;
    _canHold = false;
    if (previous == null) {
      _spawn();
    } else {
      _spawn(previous);
    }
    notifyListeners();
  }

  void togglePause() => _applyPaused(!_paused);

  void restart() {
    _reset();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal mechanics
  // ---------------------------------------------------------------------------

  bool _tryMove(int dRow, int dCol) {
    if (_current == null || _gameOver || _paused) return false;
    if (_collides(_current!, _row + dRow, _col + dCol, _rot)) return false;
    _row += dRow;
    _col += dCol;
    _refreshLockState();
    notifyListeners();
    return true;
  }

  bool _collides(TetrominoType type, int row, int col, int rot) {
    for (final c in Tetromino.of(type).cells(rot)) {
      final r = row + c.row;
      final cc = col + c.col;
      if (cc < 0 || cc >= cols || r >= rows) return true;
      if (r >= 0 && _board[r][cc] != null) return true;
    }
    return false;
  }

  void _lock() {
    _cancelLock();
    final color = Tetromino.of(_current!).color;
    for (final c in currentCells()) {
      if (c.row < 0) {
        // Locked above the visible field -> top out.
        _endGame();
        return;
      }
      _board[c.row][c.col] = color;
    }
    _clearLines();
    _applyPendingGarbage();
    if (_gameOver) {
      notifyListeners();
      return;
    }
    _canHold = true;
    _spawn();
    notifyListeners();
  }

  void _clearLines() {
    var cleared = 0;
    for (var r = rows - 1; r >= 0; r--) {
      if (_board[r].every((cell) => cell != null)) {
        _board.removeAt(r);
        _board.insert(0, List<Color?>.filled(cols, null));
        cleared++;
        r++; // Re-check this index after rows shifted down.
      }
    }
    if (cleared > 0) {
      const lineScores = {1: 100, 2: 300, 3: 500, 4: 800};
      _score += (lineScores[cleared] ?? 0) * _level;
      _lines += cleared;
      final newLevel = 1 + _lines ~/ 10;
      if (newLevel != _level) {
        _level = newLevel;
        _startTimer(); // Apply the faster gravity.
      }
      // Combo (consecutive clears) and back-to-back (consecutive Tetrises) add
      // bonus garbage on top of the base table.
      _combo += 1;
      final attack = attackFor(cleared, _combo, _b2b);
      _b2b = cleared == 4;
      onAttack?.call(attack);
      onClearEffect?.call(cleared);
    } else {
      _combo = -1; // A lock that clears no lines breaks the combo chain.
    }
  }

  void _spawn([TetrominoType? type]) {
    _cancelLock();
    _lockResets = 0; // Fresh move-reset budget for the new piece.
    final t = type ?? _takeFromQueue();
    _current = t;
    _rot = 0;
    _col = (cols - Tetromino.of(t).boxSize) ~/ 2;
    _row = 0;
    if (_collides(t, _row, _col, _rot)) {
      _endGame();
    }
  }

  void _endGame() {
    _gameOver = true;
    // Drop the active piece so no stray block/ghost renders over the stack
    // behind the game-over overlay. All actions are gated by _gameOver, so a
    // null _current is never dereferenced until restart() re-spawns.
    _current = null;
    _timer?.cancel();
    _cancelLock();
    onToppedOut?.call();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lock delay: a grounded piece waits [_lockDelay] before locking, and moving
  // or rotating it restarts that wait (capped by [_maxLockResets]).
  // ---------------------------------------------------------------------------

  bool get _grounded =>
      _current != null && _collides(_current!, _row + 1, _col, _rot);

  /// Ensure a grounded piece has a lock countdown running (used when a piece
  /// settles without a move, e.g. spawned directly onto the stack). Does not
  /// consume the move-reset budget.
  void _startLockTimer() {
    if (_gameOver || _paused || _current == null) return;
    _lockTimer ??= Timer(_lockDelay, _lockNow);
  }

  /// Re-evaluate the lock countdown after the piece moved or rotated. A grounded
  /// move restarts the grace, but only [_maxLockResets] times per piece — the
  /// budget is cleared only on spawn, so brief un-groundings (e.g. a rotation
  /// floor-kick lifting the piece) can't refresh it. Once the budget is spent
  /// the countdown is kept alive even while airborne, so a spinning piece can't
  /// stall the board forever.
  void _refreshLockState() {
    if (_current == null) return;
    final exhausted = _lockResets >= _maxLockResets;
    if (!_grounded) {
      if (!exhausted) {
        _lockTimer?.cancel();
        _lockTimer = null;
      }
      return;
    }
    if (exhausted) {
      _lockTimer ??= Timer(_lockDelay, _lockNow);
      return;
    }
    _lockResets++;
    _lockTimer?.cancel();
    _lockTimer = Timer(_lockDelay, _lockNow);
  }

  void _lockNow() {
    _lockTimer = null;
    if (_gameOver || _paused || _current == null) return;
    // A rotation kick may have left the piece hovering; settle it to its
    // resting position before locking so blocks never freeze mid-air.
    while (!_collides(_current!, _row + 1, _col, _rot)) {
      _row++;
    }
    _lock();
  }

  void _cancelLock() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Versus support: garbage rows and external pause / freeze control
  // ---------------------------------------------------------------------------

  /// Queue [lines] garbage rows from an opponent. They are pushed up from the
  /// bottom (sharing a single gap column) after the current piece locks.
  void receiveGarbage(int lines) {
    if (lines <= 0 || _gameOver) return;
    final hole = _rng.nextInt(cols);
    for (var i = 0; i < lines; i++) {
      _pendingGarbageHoles.add(hole);
    }
    notifyListeners();
  }

  void _applyPendingGarbage() {
    if (_pendingGarbageHoles.isEmpty) return;
    for (final hole in _pendingGarbageHoles) {
      final overflow = _board[0].any((cell) => cell != null);
      _board.removeAt(0);
      final row = List<Color?>.filled(cols, garbageColor);
      row[hole] = null;
      _board.add(row);
      if (overflow) {
        _pendingGarbageHoles.clear();
        _endGame();
        return;
      }
    }
    _pendingGarbageHoles.clear();
  }

  /// Externally pause/resume (used by the versus controller for both boards).
  void setPaused(bool value) => _applyPaused(value);

  void _applyPaused(bool value) {
    if (_gameOver || _paused == value) return;
    _paused = value;
    if (value) {
      // Freeze the lock-delay countdown while paused.
      _lockTimer?.cancel();
      _lockTimer = null;
    } else if (_grounded) {
      // Resume through the capped path so toggling pause can't hand out an
      // unlimited series of fresh graces.
      _refreshLockState();
    }
    notifyListeners();
  }

  /// Stop gravity without ending the game (freezes the winner's board).
  void freeze() {
    _timer?.cancel();
    _cancelLock();
  }

  TetrominoType _takeFromQueue() {
    _ensureQueue();
    return _queue.removeAt(0);
  }

  /// 7-bag randomiser: each batch of 7 contains every piece exactly once.
  void _ensureQueue() {
    while (_queue.length < 5) {
      if (_bag.isEmpty) {
        _bag.addAll(TetrominoType.values);
        _bag.shuffle(_rng);
      }
      _queue.add(_bag.removeAt(0));
    }
  }

  Duration get _gravityInterval =>
      Duration(milliseconds: max(90, 800 - (_level - 1) * 70));

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_gravityInterval, (_) => _gravityStep());
  }

  void _gravityStep() {
    if (_gameOver || _paused || _current == null) return;
    if (!_tryMove(1, 0)) {
      _startLockTimer(); // Grounded: let the lock-delay grace run before locking.
    }
  }

  void _reset() {
    _cancelLock();
    _board = List.generate(rows, (_) => List<Color?>.filled(cols, null));
    _score = 0;
    _lines = 0;
    _level = 1;
    _gameOver = false;
    _paused = false;
    _hold = null;
    _canHold = true;
    _combo = -1;
    _b2b = false;
    _pendingGarbageHoles.clear();
    _queue.clear();
    _bag.clear();
    _spawn();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lockTimer?.cancel();
    super.dispose();
  }
}
