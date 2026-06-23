import 'package:flutter/material.dart';

import '../app.dart';
import '../core/game_definition.dart';
import '../core/game_session.dart';
import '../core/models/room.dart';
import '../theme.dart';

/// 인게임 화면 컨테이너. 상단 바(방 코드 / 상대 / 나가기) + 실제 게임 위젯.
class GameHostScreen extends StatelessWidget {
  final GameDefinition game;
  final GameSession session;

  const GameHostScreen({super.key, required this.game, required this.session});

  Future<void> _leave(BuildContext context) async {
    // async gap 이전에 context 의존 객체를 미리 확보한다.
    final services = AppServices.of(context);
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('게임 나가기'),
        content: const Text('정말 나갈까요? 상대방의 게임도 종료됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속하기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: G42Colors.bad),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await services.roomService.leaveRoom(session.roomCode, session.myPlayerId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _leave(context),
          ),
          title: Row(
            children: [
              Icon(game.icon, size: 20),
              const SizedBox(width: 8),
              Text(game.title),
            ],
          ),
          actions: [_roomCodeChip(), const SizedBox(width: 12)],
        ),
        body: SafeArea(
          child: StreamBuilder<Room>(
            stream: session.watch(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: [
                  _opponentBar(context, snap.data!),
                  Expanded(child: game.buildGame(context, session)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _roomCodeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag_rounded, size: 14, color: Colors.white38),
          const SizedBox(width: 2),
          Text(
            session.roomCode,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _opponentBar(BuildContext context, Room room) {
    if (session.hotseat) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: G42Colors.surface,
        child: const Text(
          '핫시트 모드 · 한 기기에서 번갈아 플레이',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    final opp = room.opponentOf(session.myPlayerId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: G42Colors.surface,
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            size: 16,
            color: Colors.white38,
          ),
          const SizedBox(width: 6),
          Text(
            opp == null ? '상대 없음' : '상대: ${opp.name}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
