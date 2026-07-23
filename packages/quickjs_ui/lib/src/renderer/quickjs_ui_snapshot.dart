import 'dart:ui' as ui;

/// Page-scoped registry for captured Flutter subtree images.
///
/// JavaScript receives opaque ids while pixels remain owned by Flutter.
final class QuickjsUiSnapshotRegistry {
  QuickjsUiSnapshotRegistry({
    this.maxSnapshots = 32,
    this.maxSnapshotPixels = 16 * 1024 * 1024,
  }) : assert(maxSnapshots > 0),
       assert(maxSnapshotPixels > 0);

  final int maxSnapshots;
  final int maxSnapshotPixels;
  final Map<String, QuickjsUiSnapshot> _snapshots =
      <String, QuickjsUiSnapshot>{};
  int _nextSnapshotId = 0;

  int get length => _snapshots.length;

  QuickjsUiSnapshot? resolve(String id) => _snapshots[id];

  QuickjsUiSnapshot register({
    required String boundaryId,
    required ui.Image image,
    required double pixelRatio,
  }) {
    if (image.width * image.height > maxSnapshotPixels) {
      image.dispose();
      throw StateError('quickjs_ui snapshot exceeds $maxSnapshotPixels pixels');
    }
    final id = 'snapshot:$boundaryId:${++_nextSnapshotId}';
    while (_snapshots.length >= maxSnapshots) {
      _dispose(_snapshots.remove(_snapshots.keys.first));
    }
    final snapshot = QuickjsUiSnapshot(
      id: id,
      image: image,
      pixelRatio: pixelRatio,
    );
    _snapshots[id] = snapshot;
    return snapshot;
  }

  bool release(String id) {
    final snapshot = _snapshots.remove(id);
    _dispose(snapshot);
    return snapshot != null;
  }

  void dispose() {
    for (final snapshot in _snapshots.values) {
      snapshot.image.dispose();
    }
    _snapshots.clear();
  }

  void _dispose(QuickjsUiSnapshot? snapshot) => snapshot?.image.dispose();
}

final class QuickjsUiSnapshot {
  const QuickjsUiSnapshot({
    required this.id,
    required this.image,
    required this.pixelRatio,
  });

  final String id;
  final ui.Image image;
  final double pixelRatio;

  double get width => image.width / pixelRatio;
  double get height => image.height / pixelRatio;

  Map<String, Object?> toPayload() => <String, Object?>{
    'snapshotId': id,
    'width': width,
    'height': height,
    'pixelWidth': image.width,
    'pixelHeight': image.height,
    'pixelRatio': pixelRatio,
  };
}
