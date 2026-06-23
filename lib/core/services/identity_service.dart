import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 로컬에 영구 저장되는 내 정체성(플레이어 id + 표시 이름).
class IdentityService {
  String playerId;
  String name;
  final SharedPreferences _prefs;

  IdentityService._(this._prefs, this.playerId, this.name);

  static Future<IdentityService> load() async {
    final prefs = await SharedPreferences.getInstance();

    var id = prefs.getString('playerId');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('playerId', id);
    }

    var name = prefs.getString('playerName');
    if (name == null || name.isEmpty) {
      name = '플레이어-${id.substring(0, 4)}';
      await prefs.setString('playerName', name);
    }

    return IdentityService._(prefs, id, name);
  }

  Future<void> setName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    name = trimmed;
    await _prefs.setString('playerName', name);
  }
}
