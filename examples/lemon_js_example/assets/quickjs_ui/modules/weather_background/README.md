# quickjs_ui weather_background 模块

该目录是一个自包含 JS 模块，只使用公开的 `quickjs_ui` 节点，不依赖宿主插件。

```js
import {
  WeatherBackground,
  createWeatherTheme
} from './modules/weather_background/index.mjs';

const theme = createWeatherTheme({
  assetBase: 'assets/my_page/modules/weather_background/assets'
});

WeatherBackground({
  weather: 'heavyRain',
  width: 360,
  height: 560,
  intensity: 0.8,
  fps: 30,
  paused: false,
  theme
});
```

复用时请整体移动该目录并保持内部结构，只需更新 `assetBase`。示例及页面状态刻意放在
模块之外。
