import {
  Center,
  Column,
  Container,
  ElevatedButton,
  Page,
  Positioned,
  Row,
  Text,
} from 'quickjs_ui';
import {
  WEATHER_TYPES,
  WeatherBackground
} from './modules/weather_background/index.mjs';

const LABELS = {
  sunny: '晴天',
  cloudy: '多云',
  overcast: '阴天',
  haze: '霾',
  sandstorm: '沙尘',
  lightRain: '小雨',
  moderateRain: '中雨',
  largeRain: '大雨',
  thunderstorm: '雷暴',
  heavyRain: '暴雨',
  lightSnow: '小雪',
  moderateSnow: '中雪',
  largeSnow: '大雪',
  heavySnow: '暴雪',
};

export default Page({
  name: 'WeatherBackgroundModuleDemo',
  createState(props) {
    return {
      weather: 'sunny',
      paused: false,
      playToken: 0,
      viewportWidth: Number(props.width) || 360,
      viewportHeight: Number(props.height) || 640,
    };
  },
  togglePaused(state) {
    return { paused: !state.paused };
  },
  changeWeather(state, data) {
    const current = WEATHER_TYPES.indexOf(state.weather);
    const next = (current + data.offset + WEATHER_TYPES.length) % WEATHER_TYPES.length;
    return { weather: WEATHER_TYPES[next], playToken: state.playToken + 1 };
  },
  build(state, props, actions) {
    const width = Number(state.viewportWidth) || 360;
    const height = Number(state.viewportHeight) || 640;
    return Center({
      child: WeatherBackground({
        weather: state.weather,
        width,
        height,
        borderRadius: 0,
        paused: state.paused,
        playToken: state.playToken,
        child: Positioned({
          left: 16,
          right: 16,
          bottom: 18,
          child: Container({
            padding: { horizontal: 14, vertical: 12 },
            clipRadius: 22,
            backdropBlur: 10,
            decoration: {
              color: '#550f172a',
              borderRadius: 22,
              border: { color: '#44ffffff', width: 1 },
              boxShadow: {
                color: '#44000000',
                offset: { x: 0, y: 8 },
                blurRadius: 20,
                spreadRadius: 1
              }
            },
            child: Column({
              gap: 8,
              children: [
                Text(LABELS[state.weather], {
                  style: { color: '#ffffff', fontSize: 24, fontWeight: 'w800' }
                }),
                Text('独立 JS 模块 · 图片分层 · 原生 VSync', {
                  style: { color: '#e2e8f0', fontSize: 12, fontWeight: 'w600' }
                }),
                Row({
                  mainAxisAlignment: 'center',
                  gap: 8,
                  children: [
                    ElevatedButton({
                      onPressed: actions.changeWeather({ offset: -1 }),
                      child: Text('上一种')
                    }),
                    ElevatedButton({
                      onPressed: actions.togglePaused(),
                      child: Text(state.paused ? '继续' : '暂停')
                    }),
                    ElevatedButton({
                      onPressed: actions.changeWeather({ offset: 1 }),
                      child: Text('下一种')
                    })
                  ]
                })
              ]
            })
          })
        })
      })
    });
  }
});
