import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:video_player/video_player.dart' as native;

const String quickjsUiVideoPlayerModuleSpecifier = 'quickjs_ui/video_player';

const String quickjsUiVideoPlayerModuleSource = '''
export function VideoPlayer(props = {}) {
  const key = props.key ?? props.playerKey ?? 'video-player';
  const progress = props.onProgress == null
    ? undefined
    : {
        ...props.onProgress,
        throttleMs: props.progressThrottleMs ?? 250,
        coalesceKey: props.progressCoalesceKey ?? `\${key}:progress`
      };
  return {
    type: 'VideoPlayer',
    key,
    source: props.source,
    playing: props.playing === true,
    loop: props.loop === true,
    aspectRatio: props.aspectRatio ?? 16 / 9,
    restartToken: props.restartToken ?? 0,
    seekToken: props.seekToken ?? 0,
    seekPositionMs: props.seekPositionMs ?? 0,
    onReady: props.onReady,
    onProgress: progress,
    onEnded: props.onEnded,
    onError: props.onError
  };
}
''';

final class QuickjsUiVideoPlayerPlugin {
  const QuickjsUiVideoPlayerPlugin._();

  static const QuickjsHostMount mount = QuickjsHostMount(
    name: 'quickjs_ui:plugin:video_player',
    modules: <QuickjsHostModule>[
      QuickjsHostModule.esModule(
        specifier: quickjsUiVideoPlayerModuleSpecifier,
        source: quickjsUiVideoPlayerModuleSource,
      ),
    ],
  );

  static QuickjsUiComponentRegistry registry([
    QuickjsUiComponentRegistry? base,
  ]) {
    final registry = base ?? QuickjsUiComponentRegistry.defaults();
    registry.register('VideoPlayer', build);
    return registry;
  }

  static Widget build(QuickjsUiRenderContext context, QuickjsUiNode node) {
    return _QuickjsUiVideoPlayerHost(context: context, node: node);
  }
}

class _QuickjsUiVideoPlayerHost extends StatefulWidget {
  const _QuickjsUiVideoPlayerHost({required this.context, required this.node});

  final QuickjsUiRenderContext context;
  final QuickjsUiNode node;

  @override
  State<_QuickjsUiVideoPlayerHost> createState() =>
      _QuickjsUiVideoPlayerHostState();
}

class _QuickjsUiVideoPlayerHostState extends State<_QuickjsUiVideoPlayerHost> {
  static const int _progressDispatchIntervalMs = 50;
  static const Duration _stalePauseRecoveryThreshold = Duration(seconds: 30);

  native.VideoPlayerController? _controller;
  bool _initialized = false;
  bool _endedDispatched = false;
  String? _activeSource;
  int _restartToken = 0;
  int _seekToken = 0;
  int _lastProgressDispatchMs = -1;
  int _lastProgressDurationMs = -1;
  int _playbackSyncVersion = 0;
  int _seekRequestVersion = 0;
  bool _applyingPlaying = false;
  bool _pendingPlayingSync = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiVideoPlayerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final source = _sourceFromNode(widget.node);
    if (source != _activeSource) {
      _disposeController();
      _initializeController();
      return;
    }

    _syncRestart();
    _syncSeek();
    _syncLoop();
    _syncPlaying();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initializeController() async {
    final source = _sourceFromNode(widget.node);
    if (source == null || source.isEmpty) {
      _dispatchError('VideoPlayer.source is required');
      return;
    }

    _activeSource = source;
    _playbackSyncVersion += 1;
    _seekRequestVersion += 1;
    _endedDispatched = false;
    _lastProgressDispatchMs = -1;
    _lastProgressDurationMs = -1;
    _pausedAt = null;

    final controller = native.VideoPlayerController.networkUrl(
      Uri.parse(source),
    );
    _controller = controller;
    try {
      await controller.initialize();
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      await controller.dispose();
      return;
    }

    await controller.setLooping(_loopFromNode(widget.node));
    controller.addListener(_handleControllerUpdate);
    setState(() {
      _initialized = true;
    });

    _syncPlaying(force: true);
    final onReady = QuickjsUiProps.event(widget.node.props['onReady']);
    if (onReady != null) {
      widget.context.dispatchEvent(
        onReady,
        payload: <String, Object?>{
          'durationMs': controller.value.duration.inMilliseconds,
        },
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_controller, controller)) {
        _syncPlaying(force: true);
      }
    });
  }

  void _syncRestart() {
    final restartToken = widget.node.props['restartToken'];
    if (restartToken is! num || restartToken.toInt() == _restartToken) {
      return;
    }
    _restartToken = restartToken.toInt();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _endedDispatched = false;
    _lastProgressDispatchMs = 0;
    final version = ++_seekRequestVersion;
    unawaited(_seekTo(controller, Duration.zero, version));
  }

  void _syncSeek() {
    final seekToken = widget.node.props['seekToken'];
    if (seekToken is! num || seekToken.toInt() == _seekToken) {
      return;
    }
    _seekToken = seekToken.toInt();
    final seekPositionMs = widget.node.props['seekPositionMs'];
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        seekPositionMs is! num) {
      return;
    }
    final positionMs = seekPositionMs.toInt().clamp(0, 1 << 31);
    final version = ++_seekRequestVersion;
    unawaited(_seekTo(controller, Duration(milliseconds: positionMs), version));
  }

  void _syncLoop() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    unawaited(controller.setLooping(_loopFromNode(widget.node)));
  }

  void _syncPlaying({bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final playing = widget.node.props['playing'] == true;
    if (_applyingPlaying) {
      _pendingPlayingSync = true;
      return;
    }
    if (!force && controller.value.isPlaying == playing) {
      return;
    }
    final version = ++_playbackSyncVersion;
    _applyingPlaying = true;
    unawaited(_applyPlaying(controller, playing, version));
  }

  Future<void> _applyPlaying(
    native.VideoPlayerController controller,
    bool playing,
    int syncVersion,
  ) async {
    if (playing && _shouldRecoverControllerBeforePlay(controller)) {
      await _recoverControllerForPlayback(controller, syncVersion);
      return;
    }
    try {
      if (playing) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      if (mounted) {
        _applyingPlaying = false;
      }
      return;
    }
    _applyingPlaying = false;
    _pausedAt = playing ? null : DateTime.now();
    _completePlayingSync(syncVersion);
  }

  bool _shouldRecoverControllerBeforePlay(
    native.VideoPlayerController controller,
  ) {
    final pausedAt = _pausedAt;
    if (pausedAt == null || controller.value.isPlaying) {
      return false;
    }
    return DateTime.now().difference(pausedAt) >= _stalePauseRecoveryThreshold;
  }

  Future<void> _recoverControllerForPlayback(
    native.VideoPlayerController oldController,
    int syncVersion,
  ) async {
    final source = _activeSource;
    if (source == null || source.isEmpty) {
      _applyingPlaying = false;
      return;
    }

    final position = oldController.value.position;
    final loop = _loopFromNode(widget.node);
    oldController.removeListener(_handleControllerUpdate);
    _controller = null;
    _seekRequestVersion += 1;
    _endedDispatched = false;
    if (mounted) {
      setState(() {
        _initialized = false;
      });
    }
    await oldController.dispose();

    final controller = native.VideoPlayerController.networkUrl(
      Uri.parse(source),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        if (mounted) {
          _applyingPlaying = false;
        }
        return;
      }
      await controller.setLooping(loop);
      if (position > Duration.zero) {
        await controller.seekTo(position);
      }
      controller.addListener(_handleControllerUpdate);
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
      if (syncVersion == _playbackSyncVersion) {
        await controller.play();
      }
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        _applyingPlaying = false;
        _dispatchError('$error');
      }
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      if (mounted) {
        _applyingPlaying = false;
      }
      return;
    }
    _applyingPlaying = false;
    _pausedAt = null;
    _lastProgressDispatchMs = position.inMilliseconds;
    _lastProgressDurationMs = controller.value.duration.inMilliseconds;
    _completePlayingSync(syncVersion);
  }

  void _completePlayingSync(int syncVersion) {
    if (syncVersion != _playbackSyncVersion || _pendingPlayingSync) {
      _pendingPlayingSync = false;
      _syncPlaying(force: true);
      return;
    }
  }

  Future<void> _seekTo(
    native.VideoPlayerController controller,
    Duration position,
    int requestVersion,
  ) async {
    await controller.seekTo(position);
    if (!mounted ||
        !identical(_controller, controller) ||
        requestVersion != _seekRequestVersion) {
      return;
    }
    _lastProgressDispatchMs = position.inMilliseconds;
    _lastProgressDurationMs = controller.value.duration.inMilliseconds;
    _endedDispatched = false;
    _dispatchProgress(positionMs: position.inMilliseconds, force: true);
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final value = controller.value;
    final positionMs = value.position.inMilliseconds;
    final durationMs = value.duration.inMilliseconds;
    final schemaPlaying = widget.node.props['playing'] == true;
    final intervalReached =
        _lastProgressDispatchMs < 0 ||
        (positionMs - _lastProgressDispatchMs).abs() >=
            _progressDispatchIntervalMs;
    final durationChanged = durationMs != _lastProgressDurationMs;
    if (schemaPlaying
        ? intervalReached
        : _lastProgressDispatchMs < 0 || durationChanged) {
      _dispatchProgress(positionMs: positionMs);
    }

    if (durationMs > 0 &&
        value.position >= value.duration &&
        !_endedDispatched &&
        !_loopFromNode(widget.node)) {
      _endedDispatched = true;
      final onEnded = QuickjsUiProps.event(widget.node.props['onEnded']);
      if (onEnded != null) {
        widget.context.dispatchEvent(onEnded);
      }
    }
  }

  void _dispatchProgress({required int positionMs, bool force = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final onProgress = QuickjsUiProps.event(widget.node.props['onProgress']);
    if (onProgress == null) {
      return;
    }
    final durationMs = controller.value.duration.inMilliseconds;
    if (!force &&
        positionMs == _lastProgressDispatchMs &&
        durationMs == _lastProgressDurationMs) {
      return;
    }
    _lastProgressDispatchMs = positionMs;
    _lastProgressDurationMs = durationMs;
    widget.context.dispatchEvent(
      onProgress,
      defaultCoalesceKey:
          'VideoPlayer:${widget.node.props['key'] ?? 'video-player'}:onProgress',
      kind: QuickjsUiEventKind.sample,
      payload: <String, Object?>{
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': controller.value.isPlaying,
      },
    );
  }

  void _dispatchError(String message) {
    final onError = QuickjsUiProps.event(widget.node.props['onError']);
    if (onError == null) {
      return;
    }
    widget.context.dispatchEvent(
      onError,
      payload: <String, Object?>{'message': message},
    );
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initialized = false;
    _activeSource = null;
    _applyingPlaying = false;
    _pendingPlayingSync = false;
    _pausedAt = null;
    _playbackSyncVersion += 1;
    _seekRequestVersion += 1;
    if (controller != null) {
      controller.removeListener(_handleControllerUpdate);
      unawaited(controller.dispose());
    }
  }

  String? _sourceFromNode(QuickjsUiNode node) {
    return QuickjsUiProps.string(
      node.props['source'],
      name: 'VideoPlayer.source',
    );
  }

  bool _loopFromNode(QuickjsUiNode node) {
    return node.props['loop'] == true;
  }

  double _aspectRatioFromNode(QuickjsUiNode node) {
    final value = node.props['aspectRatio'];
    if (value is num && value > 0) {
      return value.toDouble();
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_initialized ||
        controller == null ||
        !controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _aspectRatioFromNode(widget.node),
        child: const ColoredBox(
          color: Color(0xFF111827),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio == 0
          ? _aspectRatioFromNode(widget.node)
          : controller.value.aspectRatio,
      child: native.VideoPlayer(controller),
    );
  }
}
