import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/game_definition.dart';
import '../core/game_session.dart';
import '../core/models/room.dart';
import '../core/services/room_service.dart';
import '../theme.dart';
import 'game_host_screen.dart';

/// 방 만들기 / 코드로 참가 화면. 두 명이 모이면 자동으로 게임으로 진입.
class RoomScreen extends StatefulWidget {
  final GameDefinition game;
  const RoomScreen({super.key, required this.game});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _joinController = TextEditingController();
  StreamSubscription<Room>? _sub;
  Room? _room;
  bool _isHost = false;
  bool _busy = false;
  bool _navigated = false;
  String? _error;

  RoomService get _service => AppServices.of(context).roomService;
  String get _myId => AppServices.of(context).identity.playerId;
  String get _myName => AppServices.of(context).identity.name;

  @override
  void dispose() {
    _sub?.cancel();
    _joinController.dispose();
    super.dispose();
  }

  // ---- 호스트: 온라인 방 만들기 ----
  Future<void> _createOnline() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await _service.createRoom(
        gameId: widget.game.id,
        host: RoomPlayer(id: _myId, name: _myName),
      );
      _isHost = true;
      _listen(room.code);
      setState(() => _room = room);
    } catch (e) {
      setState(() => _error = '방 생성 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 로컬: 같은 기기 핫시트 ----
  Future<void> _startHotseat() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = RoomPlayer(id: _myId, name: _myName);
      final room = await _service.createRoom(
        gameId: widget.game.id,
        host: host,
      );
      final p2 = RoomPlayer(id: '${_myId}__p2', name: '플레이어 2');
      await _service.joinRoom(code: room.code, player: p2);
      final ids = [host.id, p2.id];
      await _service.startGame(
        room.code,
        initialState: widget.game.createInitialState(ids),
        firstTurn: widget.game.firstTurn(ids),
      );
      if (!mounted) return;
      _goToGame(room.code, hotseat: true);
    } catch (e) {
      setState(() => _error = '시작 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 게스트: 코드로 참가 ----
  Future<void> _join() async {
    final code = _joinController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.joinRoom(
        code: code,
        player: RoomPlayer(id: _myId, name: _myName),
      );
      switch (result.outcome) {
        case JoinOutcome.notFound:
          setState(() => _error = '존재하지 않는 방 코드예요.');
          break;
        case JoinOutcome.full:
          setState(() => _error = '이미 꽉 찬 방이에요.');
          break;
        case JoinOutcome.joined:
          _isHost = false;
          _listen(code);
          setState(() => _room = result.room);
          break;
      }
    } catch (e) {
      setState(() => _error = '참가 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _listen(String code) {
    _sub?.cancel();
    _sub = _service.watchRoom(code).listen((room) {
      if (!mounted) return;
      setState(() => _room = room);

      // 호스트가 두 명 모인 걸 감지하면 게임 시작.
      if (_isHost &&
          room.isFull &&
          room.status == RoomStatus.waiting &&
          _service.isOnline) {
        final ids = room.playerIds;
        _service.startGame(
          code,
          initialState: widget.game.createInitialState(ids),
          firstTurn: widget.game.firstTurn(ids),
        );
      }

      if (room.status == RoomStatus.playing && !_navigated) {
        _goToGame(code, hotseat: false);
      }
    });
  }

  void _goToGame(String code, {required bool hotseat}) {
    _navigated = true;
    final session = GameSession(
      myPlayerId: _myId,
      roomCode: code,
      service: _service,
      hotseat: hotseat,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameHostScreen(game: widget.game, session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = _service.isOnline;
    final waitingAsHost =
        _room != null &&
        online &&
        _isHost &&
        _room!.status == RoomStatus.waiting;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(widget.game.icon, size: 22),
            const SizedBox(width: 8),
            Text(widget.game.title),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: waitingAsHost ? _waitingView() : _menuView(online),
        ),
      ),
    );
  }

  Widget _menuView(bool online) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _gameBanner(),
          const SizedBox(height: 28),
          if (online) ...[
            _sectionTitle('방 만들기', '코드를 친구에게 공유하세요'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _createOnline,
              icon: const Icon(Icons.add_rounded),
              label: const Text('새 방 만들기'),
            ),
            const SizedBox(height: 28),
            _sectionTitle('코드로 참가', '친구의 방 코드를 입력하세요'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _joinController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      hintText: '예: ABCD',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _join(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  child: const Text('참가'),
                ),
              ],
            ),
          ] else ...[
            _sectionTitle('같은 기기에서 둘이', '한 화면에서 번갈아 플레이합니다'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _startHotseat,
              icon: const Icon(Icons.sports_esports_rounded),
              label: const Text('둘이서 시작 (핫시트)'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(_error!, style: const TextStyle(color: G42Colors.bad)),
          ],
        ],
      ),
    );
  }

  Widget _waitingView() {
    final code = _room!.code;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '방 코드',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('코드를 복사했어요')));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: BoxDecoration(
                color: G42Colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: G42Colors.accent, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.copy_rounded,
                    size: 22,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '상대가 들어오길 기다리는 중...',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _gameBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: widget.game.gradient),
      ),
      child: Row(
        children: [
          Icon(widget.game.icon, size: 40, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.game.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.game.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ],
    );
  }
}
