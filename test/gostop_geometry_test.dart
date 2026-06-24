import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/gostop/gostop_geometry.dart';

void main() {
  for (final size in const [Size(360, 740), Size(412, 915), Size(320, 568)]) {
    group('GoStopGeometry $size', () {
      final g = GoStopGeometry(size);

      test('zones tile vertically and cover full height', () {
        final oz = g.opponentZone, f = g.fieldZone, mz = g.myZone;
        expect(oz.top, 0);
        expect(
          (oz.bottom - f.top).abs() < 0.001,
          true,
          reason: 'opp/field gap',
        );
        expect((f.bottom - mz.top).abs() < 0.001, true, reason: 'field/my gap');
        expect(
          (mz.bottom - size.height).abs() < 0.001,
          true,
          reason: 'my bottom != height: ${mz.bottom}',
        );
        expect(g.deckCenter, f.center);
      });

      test('floorAnchor deterministic + inside fieldZone with card margin', () {
        final f = g.fieldZone;
        final present = [1, 3, 5, 9, 12, 2, 7];
        final margin = g.cardWidth * 0.5;
        for (final m in present) {
          final a1 = g.floorAnchor(m, present);
          final a2 = g.floorAnchor(m, present.reversed.toList());
          expect(a1, a2, reason: 'month $m not deterministic vs list order');
          expect(a1.dx >= f.left + margin - 0.5, true, reason: 'm$m left');
          expect(a1.dx <= f.right - margin + 0.5, true, reason: 'm$m right');
          expect(a1.dy >= f.top, true, reason: 'm$m top');
          expect(a1.dy <= f.bottom, true, reason: 'm$m bottom');
        }
        // stable for identical present set
        expect(g.floorAnchor(5, [5]), g.floorAnchor(5, [5]));
      });

      test('floor card rects (incl. triple stack) do not wildly overflow', () {
        final f = g.fieldZone;
        final present = [1, 3, 5, 9, 12, 2, 7];
        for (final m in present) {
          final anchor = g.floorAnchor(m, present);
          final so = g.stackOffset(2);
          final cx = anchor.dx + so.dx, cy = anchor.dy + so.dy;
          final cardH = g.cardWidth / (5 / 8);
          expect(cx - g.cardWidth / 2 >= f.left - 1, true, reason: 'm$m L');
          expect(
            cx + g.cardWidth / 2 <= f.right + g.cardWidth,
            true,
            reason: 'm$m R',
          );
          expect(cy - cardH / 2 >= f.top - 1, true, reason: 'm$m T');
          expect(cy + cardH / 2 <= f.bottom + cardH, true, reason: 'm$m B');
        }
      });

      test('stackOffset cascades right-down by index', () {
        final s0 = g.stackOffset(0),
            s1 = g.stackOffset(1),
            s2 = g.stackOffset(2);
        expect(s0, Offset.zero);
        expect(s1.dx > s0.dx && s1.dy > s0.dy, true);
        expect(s2.dx > s1.dx && s2.dy > s1.dy, true);
      });

      test('handSlot fan: ascending x, spread <= 30deg, single centered', () {
        final single = g.handSlot(0, 1);
        expect(single.angle, 0.0);
        for (final n in [5, 8, 10]) {
          double prevX = double.negativeInfinity;
          double maxAbs = 0;
          for (var i = 0; i < n; i++) {
            final s = g.handSlot(i, n);
            maxAbs = math.max(maxAbs, s.angle.abs());
            expect(s.pos.dx >= prevX - 1e-6, true, reason: 'n$n i$i x asc');
            prevX = s.pos.dx;
          }
          // full spread <= 30deg => half-spread <= 15deg
          expect(
            maxAbs <= 15.1 * math.pi / 180,
            true,
            reason: 'n$n spread ${maxAbs * 180 / math.pi}deg',
          );
        }
      });

      test('capturedSlot row order + cascade + mine-below-opponent', () {
        final gw = g.capturedSlot(GoStopGroup.gwang, 0, true);
        final an = g.capturedSlot(GoStopGroup.animal, 0, true);
        final ri = g.capturedSlot(GoStopGroup.ribbon, 0, true);
        final ju = g.capturedSlot(GoStopGroup.junk, 0, true);
        expect(
          gw.dy < an.dy && an.dy < ri.dy && ri.dy < ju.dy,
          true,
          reason: 'row order',
        );
        final gwO = g.capturedSlot(GoStopGroup.gwang, 0, false);
        expect(gwO.dy < gw.dy, true, reason: 'opp above mine');
        expect(
          g.capturedSlot(GoStopGroup.junk, 5, true).dx >
              g.capturedSlot(GoStopGroup.junk, 0, true).dx,
          true,
        );
      });

      test('extra bands exist and sit within table', () {
        expect(g.opponentHandBand.width > 0, true);
        expect(g.bottomBand.width > 0, true);
        expect(g.bottomBand.bottom <= size.height + 0.001, true);
        expect(g.cardWidth > 0, true);
      });
    });
  }
}
