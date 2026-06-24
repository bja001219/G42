import 'package:flutter/material.dart';

import '../app.dart';
import '../core/game_registry.dart';
import '../core/game_session.dart';
import '../core/models/room.dart';
import '../theme.dart';

/// 인게임 화면 컨테이너. 상단 바(게임 제목 / 방 코드 / 방으로·나가기) + 실제 게임 위젯.
///
/// 게임 종류는 room.gameId 로 동적으로 조회한다(GameHostScreen은 특정 게임을
/// 알지 못한다). 온라인 전용이므로 session.hotseat 은 항상 false다.
class GameHostScreen extends StatelessWidget {
  final GameSession session;

  const GameHostScreen({super.key, required this.session});

  /// 완전 퇴장: 방을 떠나고 홈까지 돌아간다.
  Future<void> _leave(BuildContext context) async {
    final services = AppServices.of(context);
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('게임 나가기'),
        content: const Text('방에서 완전히 나갈까요? 상대방의 게임도 종료됩니다.'),
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
    // 대기실 화면까지 pop 후, 대기실에서 finished 상태를 보고 홈으로 처리한다.
    navigator.pop();
  }

  /// 대기실로 복귀(방은 유지). 대기실이 status를 waiting으로 리셋한다.
  void _backToRoom(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToRoom(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<Room>(
            stream: session.watch(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final room = snap.data!;
              final game = room.gameId.isEmpty
                  ? null
                  : GameRegistry.byId(room.gameId);

              if (game == null) {
                return _waiting(context, room);
              }

              return Column(
                children: [
                  _topBar(context, room, game.title, game.icon),
                  _opponentBar(context, room),
                  Expanded(child: game.buildGame(context, session)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _waiting(BuildContext context, Room room) {
    return Column(
      children: [
        _topBar(context, room, '게임', Icons.sports_esports_rounded),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _topBar(BuildContext context, Room room, String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '방으로',
            icon: const Icon(Icons.meeting_room_rounded),
            onPressed: () => _backToRoom(context),
          ),
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _roomCodeChip(),
          IconButton(
            tooltip: '나가기',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _leave(context),
          ),
        ],
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
