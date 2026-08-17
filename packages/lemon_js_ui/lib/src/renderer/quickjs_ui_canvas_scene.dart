// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

final class JsUiCanvasSceneRegistry {
  JsUiCanvasSceneRegistry({this.maxScenes = 32}) : assert(maxScenes > 0);

  final int maxScenes;
  final Map<String, JsUiCanvasScene> _scenes = <String, JsUiCanvasScene>{};

  JsUiCanvasScene? resolve(String key) => _scenes[key];
  int get length => _scenes.length;

  void register(String key, JsUiCanvasScene scene) {
    _scenes.remove(key);
    while (_scenes.length >= maxScenes) {
      _scenes.remove(_scenes.keys.first);
    }
    _scenes[key] = scene;
  }

  void clear() => _scenes.clear();
}

final class JsUiCanvasScene {
  const JsUiCanvasScene({required this.commands, required this.staticCommands});

  final List<Map<String, Object?>> commands;
  final List<Map<String, Object?>> staticCommands;
}
