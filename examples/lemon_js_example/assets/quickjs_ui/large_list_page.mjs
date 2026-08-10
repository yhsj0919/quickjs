import { ListView, Page, Text } from 'quickjs_ui';

// QuickJS -> Dart 转换器会把单次返回的对象图限制在 10,000 个节点内。
// 此测试保持在协议安全预算内；每个 Text 会贡献节点对象及其标量属性。
const itemCount = 2000;

export default Page({
  name: 'LargeListPage',

  createState() {
    return {};
  },

  build() {
    return ListView({
      key: 'large-list',
      itemExtent: 64,
      cacheExtent: 320,
      padding: { vertical: 8 },
      addAutomaticKeepAlives: false,
      children: Array.from({ length: itemCount }, (_, index) =>
        Text(`列表项 ${index + 1} / ${itemCount}`, {
          key: `large-row-${index}`,
        })
      ),
    });
  },
});
