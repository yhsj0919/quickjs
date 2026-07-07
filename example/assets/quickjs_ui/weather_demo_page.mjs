import {
    BackdropFilter,
    ClipRRect,
    Column,
    Container,
    ElevatedButton,
    ImageFilter,
    ListView,
    Page,
    Padding,
    Row,
    SizedBox,
    Stack,
    Text,
} from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';

const WHITE = '#FFFFFFFF';
const WHITE_70 = '#B3FFFFFF';
const WHITE_85 = '#D9FFFFFF';
const GLASS = '#4D263142';
const GLASS_STRONG = '#66313D50';
const BORDER = '#55FFFFFF';
const SCRIM = '#33000000';
const BACKGROUND = '#FF6F7A89';

const CITIES = [
    {
        name: '济南市',
        date: '7月7日 星期二 五月廿三',
        condition: '阴',
        temp: 25,
        high: 31,
        low: 22,
        air: '优',
        aqi: 27,
        alert: '强对流',
        bodyTemp: 23,
        humidity: 71,
        uv: '弱',
        hourly: [
            {time: '11:00', icon: '🌥', temp: 29},
            {time: '12:00', icon: '🌥', temp: 29},
            {time: '13:00', icon: '🌥', temp: 30},
            {time: '14:00', icon: '🌥', temp: 30},
            {time: '15:00', icon: '🌥', temp: 30},
            {time: '16:00', icon: '🌥', temp: 31},
            {time: '17:00', icon: '🌥', temp: 31},
        ],
        daily: [
            {day: '今天', date: '07/07', icon: '🌥', text: '阴', high: 31, low: 22, air: '优'},
            {day: '明天', date: '07/08', icon: '⛈', text: '雷阵雨', high: 33, low: 25, air: '良'},
            {day: '后天', date: '07/09', icon: '⛈', text: '雷阵雨', high: 32, low: 25, air: '良'},
            {day: '周五', date: '07/10', icon: '⛈', text: '雷阵雨', high: 34, low: 26, air: '良'},
            {day: '周六', date: '07/11', icon: '🌥', text: '多云', high: 35, low: 25, air: '良'},
            {day: '周日', date: '07/12', icon: '☁', text: '多云', high: 35, low: 27, air: '良'},
            {day: '周一', date: '07/13', icon: '⛈', text: '雷阵雨', high: 35, low: 26, air: '良'},
        ],
    },
    {
        name: '上海市',
        date: '7月7日 星期二 五月廿三',
        condition: '多云',
        temp: 28,
        high: 33,
        low: 26,
        air: '优',
        aqi: 34,
        alert: '无预警',
        bodyTemp: 29,
        humidity: 72,
        uv: '中',
        hourly: [
            {time: '11:00', icon: '🌤', temp: 28},
            {time: '12:00', icon: '🌤', temp: 29},
            {time: '13:00', icon: '🌦', temp: 30},
            {time: '14:00', icon: '🌦', temp: 31},
            {time: '15:00', icon: '☁', temp: 31},
            {time: '16:00', icon: '☁', temp: 30},
            {time: '17:00', icon: '🌥', temp: 29},
        ],
        daily: [
            {day: '今天', date: '07/07', icon: '🌤', text: '多云', high: 33, low: 26, air: '优'},
            {day: '明天', date: '07/08', icon: '🌦', text: '阵雨', high: 34, low: 27, air: '良'},
            {day: '后天', date: '07/09', icon: '☁', text: '阴', high: 32, low: 26, air: '良'},
            {day: '周五', date: '07/10', icon: '🌤', text: '多云', high: 33, low: 27, air: '良'},
            {day: '周六', date: '07/11', icon: '☀', text: '晴', high: 35, low: 28, air: '良'},
            {day: '周日', date: '07/12', icon: '🌤', text: '多云', high: 34, low: 27, air: '良'},
            {day: '周一', date: '07/13', icon: '🌦', text: '阵雨', high: 32, low: 26, air: '良'},
        ],
    },
];

export default Page({
    name: 'quickjs-ui-weather-demo',

    createState() {
        return {
            cityIndex: 0,
            refreshCount: 0,
            axiosStatus: '正在检测 Axios...',
        };
    },

    onMount() {
        if (typeof axios !== 'function') {
            return { axiosStatus: 'Axios 未注入' };
        }
        return {
            axiosStatus: `Axios ${axios.VERSION ?? '已注入'} · Fetch/XHR 已启用`,
        };
    },

    build(state, _props, page) {
        const city = CITIES[state.cityIndex] ?? CITIES[0];
        return Stack({
            fit: 'expand',
            children: [
                VideoPlayer({
                    source: 'http://192.168.5.12:8099/media/weather_video/bao_xue.mp4',
                    playing: true,
                    loop: true,
                    fit: 'cover',
                    backgroundColor: BACKGROUND,
                }),
                Container({color: SCRIM}),
                ListView({
                    padding: {horizontal: 20, vertical: 28},
                    children: [
                        header(city, state, page),
                        hourlyCard(city.hourly),
                        dailyCard(city.daily),
                        metricsCard(city),
                    ],
                }),
            ],
        });
    },

    nextCity(state) {
        return {
            cityIndex: (state.cityIndex + 1) % CITIES.length,
            refreshCount: state.refreshCount,
        };
    },

    refresh(state) {
        return {
            refreshCount: state.refreshCount + 1,
        };
    },
});

function header(city, state, page) {
    return Column({
        crossAxisAlignment: 'center',
        children: [
            Text(city.name, {
                textAlign: 'center',
                style: {color: WHITE, fontSize: 22, fontWeight: 'w700'},
            }),
            Row({
                mainAxisAlignment: 'center',
                children: [
                    Text('11:47', {
                        style: {color: WHITE, fontSize: 72, fontWeight: 'w300'},
                    }),
                    Padding({
                        padding: {left: 10, top: 16},
                        child: Column({
                            crossAxisAlignment: 'start',
                            children: [
                                Text(`${city.temp}°  🌥`, {
                                    style: {color: WHITE, fontSize: 38, fontWeight: 'w400'},
                                }),
                                Text(`${city.high}° / ${city.low}°`, {
                                    style: {color: WHITE, fontSize: 18, fontWeight: 'w700'},
                                }),
                            ],
                        }),
                    }),
                ],
            }),
            Text(city.date, {
                textAlign: 'center',
                style: {color: WHITE, fontSize: 18, fontWeight: 'w700'},
            }),
            Padding({
                padding: {top: 8},
                child: Text(state.axiosStatus, {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 13, fontWeight: 'w600'},
                }),
            }),
            Padding({
                padding: {top: 12, bottom: 20},
                child: Row({
                    mainAxisAlignment: 'center',
                    children: [
                        ElevatedButton({
                            onPressed: page.nextCity(),
                            child: Text('切换城市'),
                        }),
                        Padding({
                            padding: {left: 8},
                            child: ElevatedButton({
                                onPressed: page.refresh(),
                                child: Text(state.refreshCount > 0 ? `已刷新 ${state.refreshCount}` : '刷新'),
                            }),
                        }),
                    ],
                }),
            }),
        ],
    });
}

function hourlyCard(items) {
    return glassCard({
        margin: {bottom: 18},
        child: SizedBox({
            height: 150,
            child: ListView({
                scrollDirection: 'horizontal',
                children: items.map((item) => hourlyItem(item)),
            }),
        }),
    });
}

function hourlyItem(item) {
    return Container({
        width: 72,
        padding: {vertical: 8},
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(item.time, {
                    style: {color: WHITE, fontSize: 16, fontWeight: 'w700'},
                }),
                Padding({
                    padding: {top: 18, bottom: 18},
                    child: Text(item.icon, {
                        style: {fontSize: 28},
                    }),
                }),
                Text(`${item.temp}°`, {
                    style: {color: WHITE, fontSize: 24, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function dailyCard(items) {
    return glassCard({
        margin: {bottom: 18},
        child: Column({
            crossAxisAlignment: 'stretch',
            children: [
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: items.map((item) => dailyColumn(item)),
                }),
                Padding({
                    padding: {top: 18, bottom: 10},
                    child: temperatureBands(items),
                }),
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: items.map((item) => airPill(item.air)),
                }),
            ],
        }),
    });
}

function dailyColumn(item) {
    return SizedBox({
        width: 68,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(item.day, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 15, fontWeight: 'w700'},
                }),
                Text(item.date, {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 12},
                }),
                Padding({
                    padding: {top: 12, bottom: 8},
                    child: Text(item.icon, {style: {fontSize: 24}}),
                }),
                Text(item.text, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 14, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function temperatureBands(items) {
    return Column({
        crossAxisAlignment: 'stretch',
        children: [
            Row({
                mainAxisAlignment: 'spaceBetween',
                children: items.map((item) => tempPoint(`${item.high}℃`)),
            }),
            Container({
                height: 2,
                margin: {top: 4, bottom: 10, horizontal: 24},
                color: WHITE_70,
            }),
            Row({
                mainAxisAlignment: 'spaceBetween',
                children: items.map((item) => tempPoint(`${item.low}℃`)),
            }),
        ],
    });
}

function tempPoint(label) {
    return SizedBox({
        width: 54,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(label, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 12, fontWeight: 'w600'},
                }),
                Container({
                    width: 8,
                    height: 8,
                    margin: {top: 3},
                    decoration: {
                        color: WHITE,
                        borderRadius: 4,
                    },
                }),
            ],
        }),
    });
}

function airPill(text) {
    return Container({
        width: 40,
        padding: {vertical: 4},
        decoration: {
            color: GLASS_STRONG,
            borderRadius: 16,
        },
        child: Text(text, {
            textAlign: 'center',
            style: {color: WHITE, fontSize: 12, fontWeight: 'w700'},
        }),
    });
}

function metricsCard(city) {
    return glassCard({
        child: Row({
            mainAxisAlignment: 'spaceBetween',
            children: [
                metricColumn('◔', city.air, `当前AQI指数为${city.aqi}`),
                metricColumn('☁', city.alert, '预警'),
                metricColumn('♨', `${city.bodyTemp}℃`, '体感温度'),
                metricColumn('♢', `${city.humidity}%`, '湿度'),
                metricColumn('UV', city.uv, '紫外线'),
            ],
        }),
    });
}

function metricColumn(icon, value, label) {
    return SizedBox({
        width: 86,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(icon, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 28, fontWeight: 'w700'},
                }),
                Padding({
                    padding: {top: 8, bottom: 6},
                    child: Text(value, {
                        textAlign: 'center',
                        style: {color: WHITE, fontSize: 18, fontWeight: 'w700'},
                    }),
                }),
                Text(label, {
                    textAlign: 'center',
                    style: {color: WHITE_85, fontSize: 12, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function glassCard({child, margin = {bottom: 0}}) {
    return Container({
        margin,
        child: ClipRRect({
            borderRadius: 14,
            child: BackdropFilter({
                filter: ImageFilter.blur({sigmaX: 14, sigmaY: 14}),
                child: Container({
                    padding: {all: 16},
                    decoration: {
                        color: GLASS,
                        borderRadius: 14,
                        border: {color: BORDER, width: 1},
                    },
                    child,
                }),
            }),
        }),
    });
}
