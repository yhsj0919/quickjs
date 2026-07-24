final class QuickjsUiCanvasSceneRegistry {
  QuickjsUiCanvasSceneRegistry({this.maxScenes = 32}) : assert(maxScenes > 0);

  final int maxScenes;
  final Map<String, QuickjsUiCanvasScene> _scenes =
      <String, QuickjsUiCanvasScene>{};

  QuickjsUiCanvasScene? resolve(String key) => _scenes[key];
  int get length => _scenes.length;

  void register(String key, QuickjsUiCanvasScene scene) {
    _scenes.remove(key);
    while (_scenes.length >= maxScenes) {
      _scenes.remove(_scenes.keys.first);
    }
    _scenes[key] = scene;
  }

  void clear() => _scenes.clear();
}

final class QuickjsUiCanvasScene {
  const QuickjsUiCanvasScene({
    required this.commands,
    required this.staticCommands,
  });

  final List<Map<String, Object?>> commands;
  final List<Map<String, Object?>> staticCommands;
}
