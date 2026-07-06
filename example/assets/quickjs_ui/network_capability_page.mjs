import {
  Column,
  Container,
  ElevatedButton,
  ListView,
  Page,
  Text
} from 'quickjs_ui';

function describeError(error) {
  if (error == null) {
    return '未知错误';
  }
  if (typeof axios !== 'undefined' && axios.isAxiosError?.(error)) {
    const status = error.response?.status;
    const message = error.message ?? 'Axios 请求失败';
    return status == null ? message : `HTTP ${status}: ${message}`;
  }
  if (typeof error === 'string') {
    return error;
  }
  if (error && typeof error.message === 'string') {
    return error.message;
  }
  return String(error);
}

async function fetchPosts(apiUrl) {
  const response = await axios.get(apiUrl, {
    headers: {
      accept: 'application/json'
    }
  });
  const statusCode = response.status;
  const posts = response.data;
  const body = JSON.stringify(posts);
  return {
    error: '',
    posts: Array.isArray(posts) ? posts : [],
    statusCode,
    preview: body.length > 180 ? `${body.slice(0, 180)}...` : body
  };
}

function postCard(post) {
  return Container({
    key: `post-${post.id}`,
    padding: 12,
    margin: { bottom: 8 },
    decoration: {
      color: '$surface',
      borderRadius: 10,
      border: { color: '$outline', width: 1 }
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      gap: 6,
      children: [
        Text(`#${post.id} ${post.title ?? '无标题'}`, {
          style: { fontWeight: 'w700' }
        }),
        Text(post.body ?? '', {
          style: { color: '$outline', fontSize: 13 }
        })
      ]
    })
  });
}

export default Page({
  name: 'quickjs-ui-network-capability',

  createState(props) {
    return {
      loading: true,
      error: '',
      posts: [],
      statusCode: null,
      preview: '',
      lastLoadedAt: '',
      apiUrl:
        props.apiUrl ?? 'https://jsonplaceholder.typicode.com/posts?_limit=5'
    };
  },

  build(state, props, page) {
    const statusText = state.loading
      ? '正在加载网络数据...'
      : state.error
        ? `加载失败：${state.error}`
        : `已加载 ${state.posts.length} 条数据`;
    const axiosVersion =
      typeof axios !== 'undefined' && axios.VERSION ? axios.VERSION : '-';

    return ListView({
      padding: 16,
      gap: 12,
      children: [
        Text('网络能力测试', {
          style: { fontSize: 22, fontWeight: 'w700' }
        }),
        Text(
          '通过 QuickjsFetchMount + Axios 1.6.2 请求远程 JSON，并在 JS 页面内渲染结果。'
        ),
        Container({
          padding: 12,
          decoration: {
            color: '$surfaceContainerHighest',
            borderRadius: 8
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            gap: 6,
            children: [
              Text(`状态：${statusText}`),
              Text(`axios 可用：${typeof axios}`),
              Text(`axios 版本：${axiosVersion}`),
              Text(`请求地址：${state.apiUrl}`),
              Text(`HTTP 状态码：${state.statusCode ?? '-'}`),
              Text(`最近加载：${state.lastLoadedAt || '尚未完成'}`)
            ]
          })
        }),
        ElevatedButton({
          child: Text(state.loading ? '加载中...' : '重新加载'),
          onPressed: state.loading ? null : page.reload()
        }),
        state.error
          ? Container({
              padding: 12,
              decoration: {
                color: '$surface',
                borderRadius: 8,
                border: { color: '$error', width: 1 }
              },
              child: Text(state.error, {
                style: { color: '$error' }
              })
            })
          : null,
        state.preview
          ? Container({
              padding: 12,
              decoration: {
                color: '$surface',
                borderRadius: 8,
                border: { color: '$outline', width: 1 }
              },
              child: Column({
                crossAxisAlignment: 'stretch',
                gap: 6,
                children: [
                  Text('响应预览', { style: { fontWeight: 'w700' } }),
                  Text(state.preview, {
                    style: { fontSize: 12, color: '$outline' }
                  })
                ]
              })
            })
          : null,
        ...state.posts.map((post) => postCard(post))
      ].filter(Boolean)
    });
  },

  async onMount(state, _payload, props) {
    return loadPosts(state, props);
  },

  async reload(state, _payload, props) {
    return loadPosts({ ...state, loading: true, error: '' }, props);
  }
});

async function loadPosts(state, props) {
  const apiUrl = props.apiUrl ?? state.apiUrl;
  if (typeof axios !== 'function') {
    return {
      loading: false,
      apiUrl,
      error:
        'axios 未注入，请在 Dart 侧挂载 QuickjsFetchMount 并通过 environmentPatches 安装 axios',
      posts: [],
      statusCode: null,
      preview: '',
      lastLoadedAt: new Date().toLocaleTimeString()
    };
  }
  try {
    const result = await fetchPosts(apiUrl);
    return {
      loading: false,
      apiUrl,
      ...result,
      lastLoadedAt: new Date().toLocaleTimeString()
    };
  } catch (error) {
    return {
      loading: false,
      apiUrl,
      error: describeError(error),
      posts: [],
      statusCode: error?.response?.status ?? null,
      preview: '',
      lastLoadedAt: new Date().toLocaleTimeString()
    };
  }
}
