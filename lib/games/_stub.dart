import 'package:flutter/material.dart';

/// 아직 구현되지 않은 게임용 임시 화면.
class ComingSoon extends StatelessWidget {
  final String title;
  const ComingSoon({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction_rounded, size: 64),
          const SizedBox(height: 16),
          Text('$title 구현 예정', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '이 게임은 곧 채워집니다.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
