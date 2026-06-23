import 'package:flutter/material.dart';

import '../app.dart';
import '../core/game_definition.dart';
import '../core/game_registry.dart';
import '../theme.dart';
import 'room_screen.dart';
import 'stats_screen.dart';

/// 첫 화면: 게임 선택 로비. GameRegistry에 게임을 추가하면 자동으로 늘어난다.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final games = GameRegistry.games;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(context, services)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _GameCard(
                    game: games[i],
                    onTap: () => _openGame(context, games[i]),
                  ),
                  childCount: games.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGame(BuildContext context, GameDefinition game) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RoomScreen(game: game)));
  }

  Widget _header(BuildContext context, AppServices services) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(text: 'G'),
                    TextSpan(
                      text: '42',
                      style: TextStyle(color: G42Colors.accent),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _statsButton(context),
              const SizedBox(width: 8),
              _modeChip(services),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '둘이서 즐기는 미니게임 모음',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
          const SizedBox(height: 16),
          _nicknameTile(context, services),
          if (!services.firebaseReady) ...[
            const SizedBox(height: 12),
            _localNotice(),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statsButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const StatsScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: G42Colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 16,
              color: Colors.white70,
            ),
            SizedBox(width: 6),
            Text(
              '전적',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(AppServices services) {
    final online = services.roomService.isOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: online
            ? G42Colors.good.withValues(alpha: 0.15)
            : G42Colors.warn.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
            size: 16,
            color: online ? G42Colors.good : G42Colors.warn,
          ),
          const SizedBox(width: 6),
          Text(
            services.roomService.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: online ? G42Colors.good : G42Colors.warn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nicknameTile(BuildContext context, AppServices services) {
    return GestureDetector(
      onTap: () => _editName(context, services),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: G42Colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: G42Colors.accent,
              child: Icon(Icons.person, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '내 닉네임',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  Text(
                    services.identity.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _localNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: G42Colors.warn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: G42Colors.warn.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: G42Colors.warn),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '로컬 모드: 같은 기기에서 둘이 번갈아 플레이합니다.\n원격 대전은 FIREBASE_SETUP.md 설정 후 가능해요.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, AppServices services) async {
    final controller = TextEditingController(text: services.identity.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('닉네임 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '닉네임 입력'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await services.identity.setName(result);
      if (mounted) setState(() {});
    }
  }
}

class _GameCard extends StatelessWidget {
  final GameDefinition game;
  final VoidCallback onTap;
  const _GameCard({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: game.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(game.icon, size: 30, color: Colors.white),
            ),
            const Spacer(),
            Text(
              game.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              game.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.group_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  '2인',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
