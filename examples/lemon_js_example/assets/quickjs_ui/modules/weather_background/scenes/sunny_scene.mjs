import { Positioned, Image } from 'quickjs_ui';
import { animationProps, breathe, sceneRoot } from '../core/scene_helpers.mjs';

export function SunnyScene(props) {
  const size = Math.min(props.width * 0.88, props.height * 0.95);
  return sceneRoot(props.width, props.height, [
    '#177fd1', '#55b8ec', '#bdebfb'
  ], [
    Positioned({
      right: -size * 0.2,
      top: -size * 0.13,
      child: Image({
        src: props.theme.asset('sunny/halo_2.png'),
        width: size,
        height: size,
        fit: 'contain',
        opacity: 0.42,
        filterQuality: 'low'
      })
    }),
    Positioned({
      right: -size * 0.13,
      top: -size * 0.06,
      child: Image({
        src: props.theme.asset('sunny/halo_3.png'),
        width: size,
        height: size,
        fit: 'contain',
        ...animationProps(props),
        opacity: 0.78,
        transform: {
          rotate: breathe(-0.06, 0.06, 7000),
          scale: breathe(0.98, 1.025, 4800)
        },
        filterQuality: 'low'
      })
    })
  ], [0, 0.58, 1]);
}
