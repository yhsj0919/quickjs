import {
  Column,
  Container,
  ElevatedButton,
  ListView,
  Page,
  Padding,
  Text,
  TextField,
} from 'quickjs_ui';

export default Page({
  name: 'TodoPage',

  createState() {
    return {
      draft: '',
      status: '2 active tasks',
      todos: [
        { id: '1', title: 'Review quickjs_ui 0.2 roadmap', done: false },
        { id: '2', title: 'Try ThemeData tokens from JS', done: false },
      ],
    };
  },

  build(state, props, page) {
    return ListView({
      padding: { all: 16 },
      children: [
        Text('QuickJS UI Todo List', {
          style: '$text.titleMedium',
        }),
        Padding({
          padding: { top: 8, bottom: 12 },
          child: Text(state.status, {
            style: { color: '$outline', fontSize: 13 },
          }),
        }),
        Container({
          padding: { all: 12 },
          margin: { bottom: 12 },
          decoration: {
            color: '$primaryContainer',
            borderRadius: 12,
            border: { color: '$outline', width: 1 },
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            children: [
              TextField({
                value: state.draft,
                labelText: 'New task',
                hintText: 'Type a todo item',
                textInputAction: 'done',
                onChanged: page.editDraft(),
                onSubmitted: page.addTodo(),
              }),
              Padding({
                padding: { top: 8 },
                child: ElevatedButton({
                  onPressed: page.addTodo(),
                  child: Text('Add todo'),
                }),
              }),
            ],
          }),
        }),
        ...state.todos.map((todo) => todoRow(todo, page)),
      ],
    });
  },

  editDraft(state, payload, props, event) {
    return { ...state, draft: event.value ?? '' };
  },

  addTodo(state, payload, props, event) {
    const title = String(event.value ?? state.draft ?? '').trim();
    if (!title) {
      return { ...state, status: 'Type a task before adding' };
    }
    const todos = [
      ...state.todos,
      { id: String(Date.now()), title, done: false },
    ];
    return {
      ...state,
      draft: '',
      todos,
      status: `${todos.filter((todo) => !todo.done).length} active tasks`,
    };
  },

  toggleTodo(state, payload) {
    const todos = state.todos.map((todo) => {
      if (todo.id !== payload?.id) {
        return todo;
      }
      return { ...todo, done: !todo.done };
    });
    return {
      ...state,
      todos,
      status: `${todos.filter((todo) => !todo.done).length} active tasks`,
    };
  },
});

function todoRow(todo, page) {
  return Container({
    margin: { bottom: 8 },
    padding: { horizontal: 12, vertical: 10 },
    decoration: {
      color: todo.done ? '$secondaryContainer' : '$surface',
      borderRadius: 10,
      border: { color: '$outline', width: 1 },
    },
    child: Column({
      crossAxisAlignment: 'stretch',
      children: [
        Text(todo.done ? 'Done' : 'Open', {
          style: {
            color: todo.done ? '$onSecondaryContainer' : '$primary',
            fontSize: 12,
            fontWeight: 'w700',
          },
        }),
        Padding({
          padding: { top: 4, bottom: 8 },
          child: Text(todo.title, {
            style: {
              color: todo.done ? '$onSecondaryContainer' : '$onSurface',
              fontSize: 15,
            },
          }),
        }),
        ElevatedButton({
          onPressed: page.toggleTodo({ id: todo.id }),
          child: Text(todo.done ? 'Reopen' : 'Done'),
        }),
      ],
    }),
  });
}
