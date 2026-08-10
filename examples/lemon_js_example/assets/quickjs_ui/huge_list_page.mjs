import { ListView, Page, Text } from 'quickjs_ui';

const itemCount = 100000;

export default Page({
  name: 'HugeListPage',

  createState() {
    return {};
  },

  build() {
    return ListView.builder({
      key: 'huge-list',
      itemCount,
      prefetchItemCount: 30,
      cacheExtent: 320,
      padding: { vertical: 8 },
      itemKey: index => `huge-row-${index}`,
      itemBuilder: index =>
        Text(`超长列表项 ${index + 1} / ${itemCount}`),
    });
  },
});
