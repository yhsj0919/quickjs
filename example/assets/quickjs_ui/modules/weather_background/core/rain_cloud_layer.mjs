import { Container, Image, Positioned, Stack } from 'quickjs_ui';
import { animationProps, loop } from './scene_helpers.mjs';

export function RainCloudLayer(props) {
  const upperWidth = props.width * 1.32;
  const upperHeight = upperWidth * (218 / 568);
  const upperDurationMs = 150000;
  const lowerWidth = props.width * 1.18;
  const lowerHeight = lowerWidth * (287 / 568);
  const lowerDurationMs = 180000;

  return Stack({
    width: props.width,
    height: props.height,
    clipBehavior: 'none',
    children: [
      scrollingCloud({
        props,
        asset: 'heavy_rain/cloud_2.png',
        width: upperWidth,
        height: upperHeight,
        top: -upperHeight * 0.28,
        durationMs: upperDurationMs,
        phaseMs: upperDurationMs * 0.18,
        key: 'rain-cloud-upper-a'
      }),
      scrollingCloud({
        props,
        asset: 'heavy_rain/cloud_2.png',
        width: upperWidth,
        height: upperHeight,
        top: -upperHeight * 0.28,
        durationMs: upperDurationMs,
        phaseMs: upperDurationMs * 0.68,
        key: 'rain-cloud-upper-b'
      }),
      scrollingCloud({
        props,
        asset: 'heavy_rain/cloud_1.png',
        width: lowerWidth,
        height: lowerHeight,
        top: -lowerHeight * 0.08,
        durationMs: lowerDurationMs,
        phaseMs: lowerDurationMs * 0.12,
        key: 'rain-cloud-lower-a'
      }),
      scrollingCloud({
        props,
        asset: 'heavy_rain/cloud_1.png',
        width: lowerWidth,
        height: lowerHeight,
        top: -lowerHeight * 0.08,
        durationMs: lowerDurationMs,
        phaseMs: lowerDurationMs * 0.62,
        key: 'rain-cloud-lower-b'
      })
    ]
  });
}

function scrollingCloud({
  props,
  asset,
  width,
  height,
  top,
  durationMs,
  phaseMs,
  key
}) {
  return Positioned({
    key,
    left: -width,
    top,
    child: Container({
      width,
      height,
      ...animationProps(props),
      transform: {
        translate: {
          x: loop(0, props.width + width, durationMs, phaseMs)
        }
      },
      child: Image({
        src: props.theme.asset(asset),
        width,
        height,
        fit: 'fitWidth',
        filterQuality: 'low'
      })
    })
  });
}
