import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models/player_stats.dart';
import '../theme.dart';

/// 내 통산 전적 화면.
///
/// AppServices 의 scoreStore 를 구독해 통산점/승/패/승률을 실시간 표시한다.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final me = services.identity;

    return Scaffold(
      appBar: AppBar(title: const Text('내 전적')),
      body: SafeArea(
        child: StreamBuilder<PlayerStats>(
          stream: services.scoreStore.watchStats(
            me.playerId,
            fallbackName: me.name,
          ),
          builder: (context, snapshot) {
            final stats =
                snapshot.data ?? PlayerStats.empty(me.playerId, me.name);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _profileHeader(stats),
                const SizedBox(height: 24),
                _statGrid(stats),
                const SizedBox(height: 24),
                _modeNotice(services.scoreStore.label),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _profileHeader(PlayerStats stats) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: G42Colors.accent,
          child: Icon(Icons.person, size: 30, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stats.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '통산 ${stats.rounds}판',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        _winRateBadge(stats.winRate),
      ],
    );
  }

  Widget _winRateBadge(double rate) {
    final pct = (rate * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: G42Colors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            '$pct%',
            style: const TextStyle(
              color: G42Colors.accent,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            '승률',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _statGrid(PlayerStats stats) {
    final cells = <Widget>[
      _statCard(
        '통산 점수',
        '${stats.totalScore}',
        G42Colors.accent,
        Icons.star_rounded,
      ),
      _statCard(
        '승',
        '${stats.wins}',
        G42Colors.good,
        Icons.emoji_events_rounded,
      ),
      _statCard('패', '${stats.losses}', G42Colors.bad, Icons.close_rounded),
      _statCard(
        '나가리',
        '${stats.nagari}',
        G42Colors.warn,
        Icons.handshake_rounded,
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.5,
      children: cells,
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _modeNotice(String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: G42Colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded, size: 18, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '저장 모드: $label',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
