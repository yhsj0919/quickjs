import {
    Column,
    Container,
    ElevatedButton,
    ListView,
    Page,
    Padding,
    Row,
    SizedBox,
    Stack,
    Svg,
    Text, Flexible,
} from 'quickjs_ui';
import {VideoPlayer} from 'quickjs_ui/video_player';

const WHITE = '#FFFFFFFF';
const WHITE_70 = '#B3FFFFFF';
const WHITE_85 = '#D9FFFFFF';
const GLASS = '#4D263142';
const GLASS_STRONG = '#66313D50';
const BORDER = '#55FFFFFF';
const SCRIM = '#33000000';
const BACKGROUND = '#FF6F7A89';

const DEFAULT_API_URL = 'https://ad.palsmon.com/api/app/weather/city';
const DEFAULT_REFRESH_MS = 10 * 60 * 1000;
const CLOCK_REFRESH_MS = 1000;
const WEATHER_VIDEO_BASE_URL = 'http://192.168.5.12:8099/media/weather_video';
const WEATHER_ICON_BASE_PATH = 'assets/quickjs_ui/weatherIcon';

const QWEATHER_TO_METEOCONS = {
    100: 'clear-day',
    150: 'clear-night',
    101: 'partly-cloudy-day',
    102: 'partly-cloudy-day',
    103: 'partly-cloudy-day',
    104: 'overcast-day',
    151: 'partly-cloudy-night',
    152: 'partly-cloudy-night',
    153: 'partly-cloudy-night',
    300: 'partly-cloudy-day-rain',
    301: 'partly-cloudy-day-rain',
    350: 'partly-cloudy-night-rain',
    351: 'partly-cloudy-night-rain',
    302: 'thunderstorms-day-rain',
    303: 'thunderstorms',
    304: 'hail',
    305: 'drizzle',
    306: 'rain',
    307: 'rain',
    308: 'extreme-rain',
    309: 'drizzle',
    310: 'extreme-rain',
    311: 'extreme-rain',
    312: 'extreme-rain',
    313: 'sleet',
    314: 'drizzle',
    315: 'rain',
    316: 'rain',
    317: 'extreme-rain',
    318: 'extreme-rain',
    399: 'rain',
    400: 'snow',
    401: 'snow',
    402: 'snow',
    403: 'extreme-snow',
    404: 'sleet',
    405: 'sleet',
    406: 'partly-cloudy-day-sleet',
    407: 'partly-cloudy-day-snow',
    408: 'snow',
    409: 'snow',
    410: 'extreme-snow',
    456: 'partly-cloudy-night-sleet',
    457: 'partly-cloudy-night-snow',
    499: 'snow',
    500: 'mist',
    501: 'fog',
    502: 'haze',
    503: 'wind-dust',
    504: 'dust',
    507: 'wind-dust',
    508: 'wind-dust',
    509: 'fog',
    510: 'fog',
    511: 'haze',
    512: 'haze',
    513: 'haze',
    514: 'fog',
    515: 'fog',
    900: 'thermometer-warmer',
    901: 'thermometer-colder',
    999: 'not-available',
};

const ICON_VIDEO_ENTRIES = [
    [[100, 900], 'lie_ri_qing.mp4'],
    [[150, 103, 153, 901], 'qing.mp4'],
    [[101, 151], 'duo_yun_1.mp4'],
    [[102, 152], 'duo_yun_2.mp4'],
    [[104, 154], 'yin_tian.mp4'],
    [[302, 303, 304], 'lei_zhen_yu.mp4'],
    [[300, 350, 305, 309, 313, 314, 399], 'xiao_yu.mp4'],
    [[301, 351, 306, 315], 'zhong_yu.mp4'],
    [[307, 308, 310, 311, 312, 316, 317, 318], 'bao_yu.mp4'],
    [[400, 407, 457, 499], 'xiao_xue.mp4'],
    [[401, 404, 405, 406, 408, 409, 456], 'zhong_xue.mp4'],
    [[402], 'da_xue.mp4'],
    [[403, 410], 'bao_xue.mp4'],
    [[500, 501, 509, 510, 514, 515], 'wu.mp4'],
    [[502, 511, 512, 513], 'mai.mp4'],
    [[503, 504, 507, 508], 'sha_chen.mp4'],
    [[200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213], 'da_feng.mp4'],
];

let refreshTimer = 0;
let clockTimer = 0;

const EMPTY_CITY = {
    name: '加载中...',
    condition: '',
    iconSource: null,
    temp: '--',
    high: '--',
    low: '--',
    air: '-',
    aqi: '-',
    alert: '-',
    bodyTemp: '--',
    humidity: '--',
    uv: '-',
    hourly: [],
    daily: [],
    videoSource: null,
};

export default Page({
    name: 'quickjs-ui-weather-demo',

    createState(props) {
        return {
            refreshCount: 0,
            clock: formatSystemClock(),
            date: formatSystemDate(),
            loading: true,
            error: '',
            axiosStatus: '正在检测 Axios...',
            city: null,
            apiUrl: props.apiUrl ?? DEFAULT_API_URL,
        };
    },

    async onMount(state, _payload, props, _event, ctx) {
        // if (ctx?.actions?.refresh) {
        //     refreshTimer = setInterval(() => ctx.actions.refresh(), props.refreshMs ?? DEFAULT_REFRESH_MS);
        // }
        if (ctx?.actions?.updateClock) {
            clockTimer = setInterval(() => ctx.actions.updateClock(), CLOCK_REFRESH_MS);
        }
        return loadWeather(state, props);
    },

    onDispose() {
        if (refreshTimer) {
            clearInterval(refreshTimer);
            refreshTimer = 0;
        }
        if (clockTimer) {
            clearInterval(clockTimer);
            clockTimer = 0;
        }
    },

    build(state, _props, page) {
        const city = state.city ?? EMPTY_CITY;
        return Stack({
            fit: 'expand',
            children: [
                city.videoSource
                    ? VideoPlayer({
                        source: city.videoSource,
                        playing: true,
                        loop: true,
                        fit: 'cover',
                        playbackSpeed: 1,  // 0.5 倍速，默认 1
                        backgroundColor: BACKGROUND,
                        showLoading: false,
                    })
                    : Container({color: BACKGROUND}),
                // Container({color: SCRIM}),
                Padding({
                    padding: {horizontal: 50, vertical: 50},

                    child: Column({
                        children: [
                            Flexible({flex: 1, child: Container({})}),
                            errorBanner(state.error),
                            header(city, state, page),
                            Flexible({flex: 1, child: Container({})}),
                            hourlyCard(city.hourly),
                            dailyCard(city.daily),
                            metricsCard(city),
                        ].filter(Boolean),
                    })
                }),
            ],
        });
    },

    async refresh(state, _payload, props) {
        const next = await loadWeather(state, props);
        return {...next, refreshCount: state.refreshCount + 1};
    },

    updateClock(state) {
        return {
            clock: formatSystemClock(),
            date: formatSystemDate(),
        };
    },
});

async function loadWeather(state, props = {}) {
    try {
        const apiUrl = props.apiUrl ?? state.apiUrl ?? DEFAULT_API_URL;
        const data = await requestJson(apiUrl);
        return {
            loading: false,
            error: '',
            axiosStatus: axiosStatusText(),
            city: mapWeatherPayload(data),
            apiUrl,
            clock: formatSystemClock(),
            date: formatSystemDate(),
        };
    } catch (error) {
        return {
            loading: false,
            error: describeError(error),
            axiosStatus: axiosStatusText(),
            city: state.city ?? null,
            clock: formatSystemClock(),
            date: formatSystemDate(),
        };
    }
}

async function requestJson(url) {
    if (typeof axios === 'function') {
        const response = await axios.get(url);
        console.log('weather api response', JSON.stringify(response.data));
        return response.data;
    }
    if (typeof fetch === 'function') {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();
        console.log('weather api response', JSON.stringify(data));
        return data;
    }
    throw new Error('Axios/Fetch 未注入');
}

function axiosStatusText() {
    if (typeof axios === 'function') {
        return `Axios ${axios.VERSION ?? '已注入'} · Fetch/XHR 已启用`;
    }
    return 'Axios 未注入';
}

function mapWeatherPayload(data) {
    const payload = data?.data ?? data;
    const item = payload?.list?.[0];
    if (!item) {
        throw new Error(`天气接口未返回 list 数据，实际 keys: ${Object.keys(payload ?? {}).join(',') || 'empty'}`);
    }

    const now = item.now ?? {};
    const location = payload.location ?? {};
    const air = item.current_airquality?.[0];
    const alert = item.current_weatheralert?.alerts?.[0];
    const uv = item.indices?.find((entry) => entry.name === '紫外线指数');
    const today = item.days?.[0] ?? {};

    return {
        name: location.city_name ?? `${item.city ?? '未知'}市`,
        condition: now.text ?? '',
        iconSource: weatherIconSource(now.icon),
        videoSource: weatherVideoForIcon(now.icon),
        temp: toNumber(now.temp),
        high: toNumber(today.tempMax),
        low: toNumber(today.tempMin),
        air: air?.category ?? '-',
        aqi: air?.aqi ?? '-',
        alert: alert?.eventType?.name ?? '无预警',
        bodyTemp: toNumber(now.feelsLike),
        humidity: toNumber(now.humidity),
        uv: uv?.category ?? '-',
        hourly: mapHourly(item.hours ?? []),
        daily: mapDaily(item.days ?? [], item.daily_airquality ?? []),
    };
}

function mapHourly(hours) {
    const now = Date.now();
    const upcoming = hours.filter((hour) => {
        const time = Date.parse(hour.fxTime ?? '');
        return Number.isFinite(time) && time >= now - 60 * 60 * 1000;
    });

    return upcoming.slice(0, 7).map((hour) => ({
        time: formatHourTime(hour.fxTime),
        iconSource: weatherIconSource(hour.icon),
        temp: toNumber(hour.temp),
    }));
}

function mapDaily(days, dailyAir) {
    return days.slice(0, 7).map((day, index) => {
        const airEntry = dailyAir[index]?.indexes?.[0];
        return {
            day: dayLabel(index, day.fxDate),
            date: formatShortDate(day.fxDate),
            iconSource: weatherIconSource(day.iconDay),
            text: day.textDay ?? '',
            high: toNumber(day.tempMax),
            low: toNumber(day.tempMin),
            air: airEntry?.category ?? '-',
        };
    });
}

function videoUrl(fileName) {
    return `${WEATHER_VIDEO_BASE_URL}/${fileName}`;
}

function weatherVideoForIcon(iconCode) {
    const code = Number(iconCode);
    if (!Number.isFinite(code)) {
        return null;
    }
    const entry = ICON_VIDEO_ENTRIES.find(([codes]) => codes.includes(code));
    return entry ? videoUrl(entry[1]) : null;
}

function weatherIconSource(iconCode) {
    if (iconCode == null || iconCode === '') {
        return null;
    }
    const name = QWEATHER_TO_METEOCONS[Number(iconCode)] ?? 'not-available';
    return `${WEATHER_ICON_BASE_PATH}/${name}.svg`;
}

function weatherIconView(source, size = 36) {
    if (!source) {
        return SizedBox({width: size, height: size});
    }
    return Svg({
        src: source,
        width: size,
        height: size,
        fit: 'contain',
        semanticLabel: 'weather icon',
    });
}

function formatSystemClock(date = new Date()) {
    return [date.getHours(), date.getMinutes(), date.getSeconds()]
        .map((value) => String(value).padStart(2, '0'))
        .join(':');
}

function formatSystemDate(date = new Date()) {
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][date.getDay()];
    const lunar = formatLunarDate(date);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${week}${lunar ? ` ${lunar}` : ''}`;
}

function formatLunarDate(date) {
    try {
        const formatter = new Intl.DateTimeFormat('zh-CN-u-ca-chinese', {
            month: 'long',
            day: 'numeric',
        });
        return formatter.format(date).replace('月', '月');
    } catch (_) {
        return '';
    }
}

function formatHourTime(fxTime) {
    const match = `${fxTime ?? ''}`.match(/T(\d{2}:\d{2})/);
    return match?.[1] ?? '--:--';
}

function parseDate(dateStr) {
    if (!dateStr) {
        return null;
    }
    const date = new Date(`${dateStr}T12:00:00`);
    return Number.isNaN(date.getTime()) ? null : date;
}

function formatShortDate(dateStr) {
    const date = parseDate(dateStr);
    if (!date) {
        return '--/--';
    }
    return `${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}`;
}

function dayLabel(index, fxDate) {
    if (index === 0) return '今天';
    if (index === 1) return '明天';
    if (index === 2) return '后天';
    const date = parseDate(fxDate);
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return date ? week[date.getDay()] : `第${index + 1}天`;
}

function toNumber(value) {
    const number = Number(value);
    return Number.isFinite(number) ? number : value ?? '-';
}

function describeError(error) {
    if (error == null) return '未知错误';
    if (typeof axios !== 'undefined' && axios.isAxiosError?.(error)) {
        const status = error.response?.status;
        const message = error.response?.data?.msg ?? error.message ?? 'Axios 请求失败';
        return status == null ? message : `HTTP ${status}: ${message}`;
    }
    if (typeof error === 'string') return error;
    if (error && typeof error.message === 'string') return error.message;
    return String(error);
}

function errorBanner(message) {
    if (!message) {
        return null;
    }
    return Container({
        margin: {bottom: 12},
        padding: {all: 12},
        decoration: {
            color: '#66FF5252',
            borderRadius: 12,
            border: {color: '#FFFF5252', width: 1},
        },
        child: Text(message, {
            style: {color: WHITE, fontSize: 13, fontWeight: 'w600'},
        }),
    });
}

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
                    Text(`${state.clock}`, {
                        style: {color: WHITE, fontSize: 72, fontWeight: 'w300'},
                    }),
                    Padding({
                        padding: {left: 10, top: 16},
                        child: Column({
                            crossAxisAlignment: 'start',
                            children: [
                                Row({
                                    crossAxisAlignment: 'center',
                                    children: [
                                        Text(`${city.temp}°`, {
                                            style: {color: WHITE, fontSize: 38, fontWeight: 'w400'},
                                        }),
                                        Padding({
                                            padding: {left: 8},
                                            child: weatherIconView(city.iconSource, 42),
                                        }),
                                    ],
                                }),
                                Text(`${city.high}° / ${city.low}°`, {
                                    style: {color: WHITE, fontSize: 18, fontWeight: 'w700'},
                                }),
                            ],
                        }),
                    }),
                ],
            }),
            Text(state.date, {
                textAlign: 'center',
                style: {color: WHITE, fontSize: 18, fontWeight: 'w700'},
            }),
            SizedBox({height: 32}),
        ],
    });
}

function fixedHourlyItems(items) {
    const source = Array.isArray(items) ? items.slice(0, 7) : [];
    while (source.length < 7) {
        source.push({time: '--:--', iconSource: null, temp: '--'});
    }
    return source;
}

function fixedDailyItems(items) {
    const source = Array.isArray(items) ? items.slice(0, 7) : [];
    while (source.length < 7) {
        source.push(emptyDailyItem(source.length));
    }
    return source;
}

function emptyDailyItem(index) {
    return {
        day: index === 0 ? '今天' : '--',
        date: '--/--',
        iconSource: null,
        text: '--',
        high: '--',
        low: '--',
        air: '-',
    };
}

function hourlyCard(items) {
    const displayItems = fixedHourlyItems(items);
    return glassCard({
        margin: {bottom: 18},
        child: Row({
            mainAxisAlignment: 'spaceBetween',
            children: displayItems.map((item) => hourlyItem(item)),
        }),
    });
}

function hourlyItem(item) {
    return SizedBox({
        width: 68,
        child: Column({
            crossAxisAlignment: 'center',
            children: [
                Text(item.time, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 15, fontWeight: 'w700'},
                }),
                SizedBox({height: 16}),
                Padding({
                    padding: {top: 12, bottom: 8},
                    child: weatherIconView(item.iconSource, 36),
                }),
                Text(`${item.temp}°`, {
                    textAlign: 'center',
                    style: {color: WHITE, fontSize: 14, fontWeight: 'w700'},
                }),
            ],
        }),
    });
}

function dailyCard(items) {
    const displayItems = fixedDailyItems(items);
    return glassCard({
        margin: {bottom: 18},
        child: Column({
            crossAxisAlignment: 'stretch',
            children: [
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => dailyColumn(item)),
                }),
                Padding({
                    padding: {top: 18, bottom: 10},
                    child: temperatureBands(displayItems),
                }),
                Row({
                    mainAxisAlignment: 'spaceBetween',
                    children: displayItems.map((item) => airPill(item.air)),
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
                    child: weatherIconView(item.iconSource, 36),
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
                    decoration: {color: WHITE, borderRadius: 4},
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
        padding: {all: 16},
        decoration: {
            color: GLASS,
            borderRadius: 14,
            border: {color: BORDER, width: 1},
        },
        child,
    });
}
