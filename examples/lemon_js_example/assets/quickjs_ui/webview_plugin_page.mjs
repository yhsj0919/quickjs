import {
  Column,
  ElevatedButton,
  Expanded,
  Page,
  Text,
  Wrap
} from 'quickjs_ui';
import {WebView, createWebBridge, dom} from 'quickjs_ui/webview';

const bridge = createWebBridge('webview-basic-demo');

const demoHtml = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    * { box-sizing: border-box; }
    html, body { width: 100%; height: 100%; margin: 0; }
    body {
      display: grid;
      place-items: center;
      padding: 24px;
      color: #20302a;
      background: linear-gradient(145deg, #eef8f4, #f8fbfa 60%, #edf3ff);
      font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    }
    #A {
      width: min(680px, 100%);
      padding: 28px;
      border: 1px solid #ccefe1;
      border-radius: 24px;
      background: rgba(255, 255, 255, .94);
      box-shadow: 0 22px 60px rgba(31, 72, 56, .12);
    }
    h1 { margin: 0 0 8px; font-size: 28px; }
    p { margin: 0 0 22px; color: #718079; }
    .B { display: grid; gap: 12px; }
    .C {
      padding: 18px 20px;
      border: 1px solid #e0eae5;
      border-radius: 16px;
      background: #fff;
      font-size: 17px;
    }
    .C:first-child { border-color: #67d6ad; background: #effbf6; }
  </style>
</head>
<body>
  <main id="A">
    <h1>WebView 测试页面</h1>
    <p>A 节点下面包含 B，B 下面包含多个 C。</p>
    <section class="B">
      <div class="C">第一个 C</div>
      <div class="C">第二个 C</div>
      <div class="C">第三个 C</div>
    </section>
  </main>
  <script>
    window.quickjsHost.expose('describePage', function () {
      return {
        title: document.title || '内置测试页面',
        cCount: document.querySelectorAll('#A .B .C').length
      };
    });
  </script>
</body>
</html>`;

export default Page({
  name: 'WebViewPluginPage',

  createState() {
    return {status: '页面加载中'};
  },

  build(state, _props, page) {
    return Column({
      padding: 12,
      gap: 12,
      crossAxisAlignment: 'stretch',
      children: [
        Text('WebView 插件', {
          textAlign: 'center',
          style: {fontSize: 22, fontWeight: 'bold'}
        }),
        Text(state.status, {
          textAlign: 'center',
          maxLines: 2,
          overflow: 'ellipsis'
        }),
        Wrap({
          spacing: 10,
          runSpacing: 10,
          alignment: 'center',
          children: [
            ElevatedButton({
              child: Text('读取网页方法'),
              onPressed: page.readPageMethod()
            }),
            ElevatedButton({
              child: Text('只保留第一个 C'),
              onPressed: page.keepFirstC()
            })
          ]
        }),
        Expanded({
          child: WebView({
            key: 'basic-webview',
            bridge,
            html: demoHtml,
            onPageFinished: page.pageFinished(),
            onError: page.webError()
          })
        })
      ]
    });
  },

  pageFinished() {
    return {status: '页面已加载，可测试网页方法和链式 DOM 操作'};
  },

  async readPageMethod() {
    const result = await bridge.callPage('describePage');
    return {status: `网页返回：共找到 ${result.cCount} 个 C`};
  },

  async keepFirstC() {
    await bridge.apply(
      dom('#A').find('.B').find('.C').first().isolate({
        removeOthers: true,
        fillViewport: true
      })
    );
    return {status: '已只保留 A / B 下的第一个 C'};
  },

  webError(_state, _payload, _props, event) {
    return {status: `WebView 错误：${event.message ?? 'unknown'}`};
  }
});
