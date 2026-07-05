export function VideoPlayer(props = {}) {
  const key = props.key ?? props.playerKey ?? 'video-player';
  const progress = props.onProgress == null
    ? undefined
    : {
        ...props.onProgress,
        throttleMs: props.progressThrottleMs ?? 250,
        coalesceKey: props.progressCoalesceKey ?? `${key}:progress`
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
