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
  final Map<String, Object?> _captureTokens = <String, Object?>{};
  final Map<String, _QuickjsUiCaptureClaim> _captureClaims =
      <String, _QuickjsUiCaptureClaim>{};
  int _nextSnapshotId = 0;

  int get length => _snapshots.length;
  int get pixelCount => _snapshots.values.fold<int>(
    0,
    (total, snapshot) => total + snapshot.image.width * snapshot.image.height,
  );

  QuickjsUiSnapshot? resolve(String id) => _snapshots[id];

  /// Claims one capture for a boundary/token pair for the lifetime of this
  /// page registry. Rebuilding or remounting the widget cannot claim it again.
  bool claimCapture({
    required String boundaryId,
    required Object? token,
    required Object owner,
  }) {
    if (_captureTokens.containsKey(boundaryId) &&
        _snapshotTokenEquals(_captureTokens[boundaryId], token)) {
      return false;
    }
    final active = _captureClaims[boundaryId];
    if (active != null && _snapshotTokenEquals(active.token, token)) {
      return false;
    }
    _captureClaims[boundaryId] = _QuickjsUiCaptureClaim(token, owner);
    return true;
  }

  void completeCapture({
    required String boundaryId,
    required Object? token,
    required Object owner,
  }) {
    final active = _captureClaims[boundaryId];
    if (active == null || !identical(active.owner, owner)) return;
    _captureClaims.remove(boundaryId);
    _captureTokens[boundaryId] = token;
  }

  void cancelCapture({required String boundaryId, required Object owner}) {
    final active = _captureClaims[boundaryId];
    if (active != null && identical(active.owner, owner)) {
      _captureClaims.remove(boundaryId);
    }
  }

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
    _captureTokens.clear();
    _captureClaims.clear();
  }

  void _dispose(QuickjsUiSnapshot? snapshot) => snapshot?.image.dispose();
}

final class _QuickjsUiCaptureClaim {
  const _QuickjsUiCaptureClaim(this.token, this.owner);

  final Object? token;
  final Object owner;
}

bool _snapshotTokenEquals(Object? left, Object? right) {
  if (identical(left, right) || left == right) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_snapshotTokenEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_snapshotTokenEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return false;
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
