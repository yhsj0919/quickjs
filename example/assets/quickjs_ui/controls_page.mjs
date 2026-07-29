import {
  Center,
  Column,
  Container,
  Image,
  ListView,
  Page,
  Padding,
  Placeholder,
  Row,
  SizedBox,
  Stack,
  Positioned,
  Text,
  Tooltip,
  VerticalDivider,
} from 'quickjs_ui';

function panel(title, child) {
  return Container({
    margin: { bottom: 12 },
    padding: { all: 14 },
    decoration: {
      color: '$surface',
      borderRadius: 16,
      border: { color: '$outline', width: 1 },
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      gap: 10,
      children: [
        Text(title, { style: { fontWeight: 'w800' } }),
        child,
      ],
    }),
  });
}

export default Page({
  name: 'LayoutMediaControlsPage',

  build() {
    return ListView({
      padding: { all: 16 },
      children: [
        Text('布局与媒体基础', { style: { fontSize: 24, fontWeight: 'w800' } }),
        Text('集中验证图片、占位符、分隔线、约束和分层布局。', {
          style: { color: '$outline', fontSize: 13 },
        }),
        Container({ height: 16 }),
        panel('网络图片', Image({
          src: 'https://picsum.photos/seed/quickjs-ui/640/240',
          height: 150,
          fit: 'cover',
        })),
        panel('本地图片与 Stack', SizedBox({
          height: 130,
          child: Stack({
            children: [
              Positioned({
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Container({
                  decoration: { color: '$primaryContainer', borderRadius: 14 },
                }),
              }),
              Center({
                child: Image({
                  src: 'web/icons/Icon-192.png',
                  width: 64,
                  height: 64,
                  fit: 'contain',
                }),
              }),
              Positioned({
                left: 12,
                bottom: 10,
                child: Text('Positioned label', {
                  style: { color: '$onPrimaryContainer', fontWeight: 'w700' },
                }),
              }),
            ],
          }),
        })),
        panel('Placeholder 与 VerticalDivider', Column({
          crossAxisAlignment: 'stretch',
          gap: 12,
          children: [
            SizedBox({
              height: 72,
              child: Placeholder({ color: '$outline', strokeWidth: 2, fallbackHeight: 72 }),
            }),
            SizedBox({
              height: 44,
              child: Row({
                children: [
                  Text('左侧'),
                  VerticalDivider({ width: 24, thickness: 2, color: '$primary' }),
                  Text('右侧'),
                ],
              }),
            }),
          ],
        })),
        Tooltip({
          message: '由 Flutter Tooltip 渲染',
          waitDurationMs: 300,
          child: Container({
            padding: { all: 12 },
            alignment: 'center',
            decoration: { color: '$secondaryContainer', borderRadius: 12 },
            child: Text('鼠标悬停查看 Tooltip'),
          }),
        }),
        Padding({
          padding: { top: 12 },
          child: Center({
            child: Container({
              padding: { horizontal: 14, vertical: 8 },
              decoration: {
                color: '$surfaceVariant',
                borderRadius: 999,
                border: { color: '$outline', width: 1 },
              },
              child: Text('Center + Padding + Container'),
            }),
          }),
        }),
      ],
    });
  },
});
