import 'package:flutter_test/flutter_test.dart';
import 'package:g42/games/boggle/boggle_game.dart';

void main() {
  const game = BoggleGame();
  const ids = ['a', 'b'];

  test('단일 보글 게임: 설정 지원 + 기본값', () {
    expect(game.id, 'boggle');
    expect(game.hasSetup, true);
    expect(game.defaultConfig['size'], isA<int>());
    expect(game.defaultConfig['lang'], anyOf('ko', 'en'));
  });

  test('configSummary 표기', () {
    expect(game.configSummary({'size': 5, 'lang': 'ko'}), '5×5 · 한글');
    expect(game.configSummary({'size': 10, 'lang': 'en'}), '10×10 · English');
  });

  group('createInitialStateConfigured', () {
    test('영어 7×7 → 49칸 소문자 + config 저장', () {
      final s = game.createInitialStateConfigured(ids, {
        'size': 7,
        'lang': 'en',
      });
      final grid = s['grid'] as String;
      expect(grid.length, 49);
      expect(RegExp(r'^[a-z]{49}$').hasMatch(grid), true);
      expect((s['config'] as Map)['size'], 7);
      expect((s['config'] as Map)['lang'], 'en');
      expect((s['found'] as Map).keys, containsAll(ids));
      expect((s['scores'] as Map)['a'], 0);
    });

    test('한글 5×5 → 25칸 전부 한글 음절', () {
      final s = game.createInitialStateConfigured(ids, {
        'size': 5,
        'lang': 'ko',
      });
      final grid = s['grid'] as String;
      expect(grid.length, 25);
      expect(grid.runes.every((r) => r >= 0xAC00 && r <= 0xD7A3), true);
      expect((s['config'] as Map)['lang'], 'ko');
    });

    test('크기 범위 클램프 (3→4, 12→10)', () {
      final small = game.createInitialStateConfigured(ids, {
        'size': 3,
        'lang': 'en',
      });
      expect((small['grid'] as String).length, 16);
      expect((small['config'] as Map)['size'], 4);

      final big = game.createInitialStateConfigured(ids, {
        'size': 12,
        'lang': 'en',
      });
      expect((big['grid'] as String).length, 100);
      expect((big['config'] as Map)['size'], 10);
    });

    test('빈 설정이면 기본값으로 생성', () {
      final s = game.createInitialStateConfigured(ids, const {});
      final size = game.defaultConfig['size'] as int;
      expect((s['grid'] as String).length, size * size);
      expect((s['config'] as Map)['size'], size);
    });

    test('createInitialState(설정 없음)도 기본값 사용', () {
      final s = game.createInitialState(ids);
      final size = game.defaultConfig['size'] as int;
      expect((s['grid'] as String).length, size * size);
    });
  });
}
