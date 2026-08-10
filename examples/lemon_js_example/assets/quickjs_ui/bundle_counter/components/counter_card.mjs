import { Column, Container, Text } from 'quickjs_ui';
import { actionRow } from './action_row.mjs';

export function counterCard({ count, onIncrement, onReset }) {
  return Container({
    width: 280,
    padding: {
      horizontal: 18,
      vertical: 16
    },
    margin: {
      top: 16
    },
    decoration: {
      color: '#ffffff',
      borderRadius: 12,
      border: {
        color: '#d6dde3',
        width: 1
      }
    },
    child: Column({
      crossAxisAlignment: 'center',
      children: [
        Text('Bundle module counter', {
          style: {
            fontSize: 14,
            color: '#607d8b'
          }
        }),
        Text(`Count: ${count}`, {
          style: {
            fontSize: 28,
            fontWeight: 'bold',
            color: '#111827'
          }
        }),
        actionRow({ onIncrement, onReset })
      ]
    })
  });
}
