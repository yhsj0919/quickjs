import { ElevatedButton, Row, Text } from 'quickjs_ui';

export function actionRow({ onIncrement, onReset }) {
  return Row({
    mainAxisAlignment: 'center',
    children: [
      ElevatedButton({
        child: Text('添加'),
        onPressed: onIncrement
      }),
      ElevatedButton({
        child: Text('重置'),
        onPressed: onReset
      })
    ]
  });
}
