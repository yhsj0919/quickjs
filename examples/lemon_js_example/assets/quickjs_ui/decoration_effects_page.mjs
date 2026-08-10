import { Column, Container, Page, Text, Wrap } from 'quickjs_ui';

export default Page({
  name: 'DecorationEffectsPage',
  build() {
    return Container({ color: '#f4f7fb', padding: 22, child: Column({ gap: 18, children: [
      Text('渐变、边框与阴影', { style: { fontSize: 28, fontWeight: 'w800' } }),
      Container({
        height: 160, padding: 20,
        decoration: {
          gradient: { type: 'linear', colors: ['#2563eb', '#7c3aed', '#ec4899'], stops: [0, 0.55, 1], begin: 'topLeft', end: 'bottomRight' },
          borderRadius: 22,
          border: {
            left: { color: '#bfdbfe', width: 2 }, top: { color: '#ddd6fe', width: 1 },
            right: { color: '#fbcfe8', width: 2 }, bottom: { color: '#f5d0fe', width: 2 }
          },
          boxShadow: [
            { color: '#552563eb', offset: { x: 8, y: 14 }, blurRadius: 24, spreadRadius: 2 },
            { color: '#33ec4899', offset: { x: -5, y: 3 }, blurRadius: 12 }
          ]
        },
        child: Text('线性渐变 · 分边边框 · 双层阴影 · 阴影偏移', { style: { color: '#ffffff', fontSize: 18, fontWeight: 'w700' } })
      }),
      Wrap({ spacing: 16, children: [
        Container({ width: 90, height: 90, decoration: { shape: 'circle', gradient: { type: 'radial', colors: ['#fef3c7', '#f59e0b', '#b45309'], stops: [0, 0.62, 1], center: 'topLeft', radius: 0.9 }, boxShadow: { color: '#55f59e0b', offset: { x: 3, y: 7 }, blurRadius: 12 } } }),
        Container({ width: 210, padding: 16, decoration: { gradient: { type: 'linear', colors: ['#06b6d4', '#6366f1', '#8b5cf6'], begin: 'centerLeft', end: 'centerRight' }, borderRadius: 14 }, child: Text('横向三色渐变', { textAlign: 'center', style: { color: '#ffffff' } }) })
      ] })
    ] }) });
  }
});
