import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';
import 'package:quickjs_ui/src/diagnostics/quickjs_ui_diag.dart';
import 'package:video_player/video_player.dart';

class QuickjsUiNativeVideoPlayerPage extends StatelessWidget {
  const QuickjsUiNativeVideoPlayerPage({super.key});

  static const String path = 'assets/quickjs_ui/native_video_player_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Native VideoPlayer')),
      body: QuickjsUiView.asset(
        path: path,
        registry: nativeVideoPlayerRegistry(),
        initialProps: const <String, Object?>{
          'title': '0.4 native renderer injection',
          'autoplay': true,
          'loop': true,
        },
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI native video player error: $error'),
        ),
      ),
    );
  }
}

QuickjsUiComponentRegistry nativeVideoPlayerRegistry() {
  return QuickjsUiComponentRegistry.defaults()
    ..register(
      'VideoPlayer',
      (context, node) => _QuickjsUiVideoPlayerHost(context: context, node: node),
    );
}

class _QuickjsUiVideoPlayerHost extends StatefulWidget {
  const _QuickjsUiVideoPlayerHost({
    required this.context,
    required this.node,
  });

  final QuickjsUiRenderContext context;
  final QuickjsUiNode node;

  @override
  State<_QuickjsUiVideoPlayerHost> createState() =>
      _QuickjsUiVideoPlayerHostState();
}

class _QuickjsUiVideoPlayerHostState extends State<_QuickjsUiVideoPlayerHost> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _endedDispatched = false;
  String? _activeSource;
  int _restartToken = 0;
  int _seekToken = 0;
  int _lastProgressDispatchMs = -1;
  int _listenerTicks = 0;
  int _progressDispatches = 0;
  static const int _progressDispatchIntervalMs = 50;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiVideoPlayerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSource = _sourceFromNode(widget.node);
    if (nextSource != _activeSource) {
      _disposeController();
      _initializeController();
      return;
    }
    final restartToken = widget.node.props['restartToken'];
    if (restartToken is num && restartToken.toInt() != _restartToken) {
      _restartToken = restartToken.toInt();
      QuickjsUiDiag.log('video', 'restartToken=$_restartToken');
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.seekTo(Duration.zero));
        _endedDispatched = false;
        _lastProgressDispatchMs = 0;
      }
    }
    final seekToken = widget.node.props['seekToken'];
    if (seekToken is num && seekToken.toInt() != _seekToken) {
      _seekToken = seekToken.toInt();
      final seekPositionMs = widget.node.props['seekPositionMs'];
      QuickjsUiDiag.log(
        'video',
        'seekToken=$_seekToken seekPositionMs=$seekPositionMs',
      );
      final controller = _controller;
      if (controller != null &&
          controller.value.isInitialized &&
          seekPositionMs is num) {
        final positionMs = seekPositionMs.toInt().clamp(0, 1 << 31);
        unawaited(_seekTo(controller, Duration(milliseconds: positionMs)));
      }
    }
    final loop = _loopFromNode(widget.node);
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setLooping(loop));
    }
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
      return;
    }
    _activeSource = source;
    _endedDispatched = false;
    _lastProgressDispatchMs = -1;
    final controller = VideoPlayerController.networkUrl(Uri.parse(source));
    _controller = controller;
    try {
      await controller.initialize();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _dispatchError('$error');
      return;
    }
    if (!mounted || !identical(_controller, controller)) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(_loopFromNode(widget.node));
    setState(() {
      _initialized = true;
    });
    controller.addListener(_handleControllerUpdate);
    final onReady = QuickjsUiProps.event(widget.node.props['onReady']);
    if (onReady != null) {
      QuickjsUiDiag.log(
        'video',
        'onReady durationMs=${controller.value.duration.inMilliseconds}',
      );
      widget.context.dispatch(<String, Object?>{
        ...onReady,
        'durationMs': controller.value.duration.inMilliseconds,
      });
    }
    _syncPlaying();
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _listenerTicks += 1;
    final value = controller.value;
    final onProgress = QuickjsUiProps.event(widget.node.props['onProgress']);
    if (onProgress != null) {
      final positionMs = value.position.inMilliseconds;
      final intervalReached =
          _lastProgressDispatchMs < 0 ||
          (positionMs - _lastProgressDispatchMs).abs() >=
              _progressDispatchIntervalMs;
      final shouldDispatchProgress =
          intervalReached || !value.isPlaying;
      if (shouldDispatchProgress) {
        _progressDispatches += 1;
        final reason = _lastProgressDispatchMs < 0
            ? 'first'
            : !value.isPlaying
            ? 'notPlaying'
            : 'interval';
        QuickjsUiDiag.count(
          'video.progress',
          detail:
              'reason=$reason positionMs=$positionMs '
              'isPlaying=${value.isPlaying} '
              'ticks=$_listenerTicks dispatches=$_progressDispatches',
        );
        _lastProgressDispatchMs = positionMs;
        widget.context.dispatchEvent(
          onProgress,
          defaultCoalesceKey:
              'VideoPlayer:${widget.node.props['key'] ?? 'demo-player'}:onProgress',
          payload: <String, Object?>{
            'positionMs': positionMs,
            'durationMs': value.duration.inMilliseconds,
            'isPlaying': value.isPlaying,
          },
        );
      }
    }
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_endedDispatched &&
        !_loopFromNode(widget.node)) {
      _endedDispatched = true;
      final onEnded = QuickjsUiProps.event(widget.node.props['onEnded']);
      if (onEnded != null) {
        QuickjsUiDiag.log(
          'video',
          'onEnded positionMs=${value.position.inMilliseconds} '
          'durationMs=${value.duration.inMilliseconds} loop=false',
        );
        widget.context.dispatch(onEnded);
      }
    }
  }

  Future<void> _seekTo(
    VideoPlayerController controller,
    Duration position,
  ) async {
    await controller.seekTo(position);
    if (!mounted || !identical(_controller, controller)) {
      return;
    }
    _lastProgressDispatchMs = position.inMilliseconds;
    _endedDispatched = false;
    QuickjsUiDiag.log('video', 'seekTo positionMs=${position.inMilliseconds}');
    final onProgress = QuickjsUiProps.event(widget.node.props['onProgress']);
    if (onProgress != null) {
      widget.context.dispatchEvent(
        onProgress,
        defaultCoalesceKey:
            'VideoPlayer:${widget.node.props['key'] ?? 'demo-player'}:onProgress',
        payload: <String, Object?>{
          'positionMs': position.inMilliseconds,
          'durationMs': controller.value.duration.inMilliseconds,
          'isPlaying': controller.value.isPlaying,
        },
      );
    }
  }

  void _syncPlaying() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final playing = widget.node.props['playing'] == true;
    if (playing) {
      if (!controller.value.isPlaying) {
        unawaited(controller.play());
      }
      return;
    }
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  void _dispatchError(String message) {
    final onError = QuickjsUiProps.event(widget.node.props['onError']);
    if (onError != null) {
      widget.context.dispatch(<String, Object?>{
        ...onError,
        'message': message,
      });
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initialized = false;
    _activeSource = null;
    if (controller != null) {
      controller.removeListener(_handleControllerUpdate);
      unawaited(controller.dispose());
    }
  }

  String? _sourceFromNode(QuickjsUiNode node) {
    return QuickjsUiProps.string(node.props['source'], name: 'VideoPlayer.source');
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
    if (!_initialized || controller == null || !controller.value.isInitialized) {
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
      child: VideoPlayer(controller),
    );
  }
}
