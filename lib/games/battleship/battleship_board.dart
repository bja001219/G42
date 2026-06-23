import 'package:flutter/material.dart';

import '../../theme.dart';
import 'battleship_logic.dart';

/// 한 칸의 시각적 종류.
enum CellKind {
  /// 빈 물(미발사).
  water,

  /// 내 함선이 있는 칸(내 함대 격자에서만 표시).
  ship,

  /// 빗나간 사격('O').
  miss,

  /// 명중한 사격('X').
  hit,

  /// 배치 중 미리보기(유효).
  previewValid,

  /// 배치 중 미리보기(겹침/범위 밖).
  previewInvalid,
}

/// 10x10 격자 위젯. [cellAt]으로 각 칸의 종류를 결정한다.
class BattleshipGrid extends StatelessWidget {
  /// 인덱스(0~99) → 칸 종류.
  final CellKind Function(int index) cellAt;

  /// 칸 탭 콜백. null이면 비활성(터치 무시).
  final void Function(int index)? onTap;

  /// 격침으로 강조할 함선 칸(테두리 강조).
  final Set<int> sunkCells;

  const BattleshipGrid({
    super.key,
    required this.cellAt,
    this.onTap,
    this.sunkCells = const {},
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101A33),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: G42Colors.surfaceHi, width: 2),
            ),
            padding: const EdgeInsets.all(4),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: BattleshipLogic.cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: BattleshipLogic.size,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (context, index) {
                final kind = cellAt(index);
                return _Cell(
                  kind: kind,
                  sunk: sunkCells.contains(index),
                  onTap: onTap == null ? null : () => onTap!(index),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final CellKind kind;
  final bool sunk;
  final VoidCallback? onTap;

  const _Cell({required this.kind, required this.sunk, this.onTap});

  @override
  Widget build(BuildContext context) {
    Color color;
    Widget? child;
    switch (kind) {
      case CellKind.water:
        color = const Color(0xFF1B2A4A);
        break;
      case CellKind.ship:
        color = G42Colors.surfaceHi;
        child = const Icon(
          Icons.directions_boat_rounded,
          size: 14,
          color: Colors.white70,
        );
        break;
      case CellKind.miss:
        color = const Color(0xFF1B2A4A);
        child = const Icon(
          Icons.circle_outlined,
          size: 12,
          color: Colors.white54,
        );
        break;
      case CellKind.hit:
        color = G42Colors.bad.withValues(alpha: sunk ? 0.95 : 0.75);
        child = Icon(
          sunk ? Icons.local_fire_department_rounded : Icons.close_rounded,
          size: 16,
          color: Colors.white,
        );
        break;
      case CellKind.previewValid:
        color = G42Colors.good.withValues(alpha: 0.6);
        break;
      case CellKind.previewInvalid:
        color = G42Colors.bad.withValues(alpha: 0.5);
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: sunk ? Border.all(color: Colors.white, width: 1) : null,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}
