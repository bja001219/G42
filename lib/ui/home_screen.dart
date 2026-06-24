import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models/room.dart';
import '../core/services/room_service.dart';
import '../theme.dart';
import 'room_lobby_screen.dart';
import 'stats_screen.dart';

/// 홈 화면: 게임 그리드 없이 "방 만들기 / 방 참가"만 제공한다.
/// 게임 선택은 방 대기실(RoomLobbyScreen)에서 방장이 한다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  RoomService get _service => AppServices.of(context).roomService;
  String get _myId => AppServices.of(context).identity.playerId;
  String get _myName => AppServices.of(context).identity.name;

  // ---- 방 만들기 ----
  Future<void> _createRoom() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = await _service.createRoom(
        host: RoomPlayer(id: _myId, name: _myName),
      );
      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => RoomLobbyScreen(code: room.code, isHost: true),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('방 생성 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 방 참가(코드) ----
  Future<void> _joinRoom() async {
    final code = await _askCode();
    if (!mounted || code == null || code.isEmpty) return;
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _service.joinRoom(
        code: code,
        player: RoomPlayer(id: _myId, name: _myName),
      );
      if (!mounted) return;
      switch (result.outcome) {
        case JoinOutcome.notFound:
          messenger.showSnackBar(
            const SnackBar(content: Text('존재하지 않는 방 코드예요.')),
          );
          break;
        case JoinOutcome.full:
          messenger.showSnackBar(const SnackBar(content: Text('이미 꽉 찬 방이에요.')));
          break;
        case JoinOutcome.joined:
          await navigator.push(
            MaterialPageRoute(
              builder: (_) => RoomLobbyScreen(code: code, isHost: false),
            ),
          );
          break;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('참가 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: G42Colors.surface,
        title: const Text('방 코드 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 4,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: '예: ABCD',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().toUpperCase()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim().toUpperCase()),
            child: const Text('참가'),
          ),
        ],
      ),
    );
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, services),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bigButton(
                      icon: Icons.add_rounded,
                      title: '방 만들기',
                      subtitle: '코드를 만들어 친구를 초대하세요',
                      onTap: _busy ? null : _createRoom,
                    ),
                    const SizedBox(height: 16),
                    _bigButton(
                      icon: Icons.login_rounded,
                      title: '방 참가',
                      subtitle: '친구가 알려준 코드로 입장하세요',
                      onTap: _busy ? null : _joinRoom,
                    ),
                    if (!services.firebaseReady) ...[
                      const SizedBox(height: 20),
                      _localNotice(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: G42Colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: G42Colors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: G42Colors.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 22,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
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
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '둘이서 즐기는 미니게임 모음',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
          const SizedBox(height: 16),
          _nicknameTile(context, services),
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
            Icon(Icons.bar_chart_rounded, size: 16, color: Colors.white70),
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
              '로컬 모드: 원격 대전은 FIREBASE_SETUP.md 설정 후 가능해요.',
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
