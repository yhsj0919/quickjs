import {
  Column,
  Container,
  ElevatedButton,
  ListView,
  Padding,
  Page,
  Text,
  TextField,
} from 'quickjs_ui';

export default Page({
  name: 'ProfileFormPage',

  createState() {
    return {
      name: 'Ada Lovelace',
      email: 'ada@example.com',
      bio: 'Computing notes and analytical engines.',
      errors: {},
      status: 'Profile draft is ready',
    };
  },

  build(state, props, page) {
    return ListView({
      padding: { all: 16 },
      children: [
        Text('QuickJS UI Profile Form', {
          style: '$text.titleMedium',
        }),
        Padding({
          padding: { top: 8, bottom: 12 },
          child: Text(state.status, {
            style: { color: '$outline', fontSize: 13 },
          }),
        }),
        Container({
          padding: { all: 14 },
          decoration: {
            color: '$surface',
            borderRadius: 12,
            border: { color: '$outline', width: 1 },
          },
          child: Column({
            crossAxisAlignment: 'stretch',
            children: [
              TextField({
                value: state.name,
                labelText: 'Name',
                textInputAction: 'next',
                onChanged: page.updateField({ field: 'name' }),
                onFocus: page.focusField({ field: 'name' }),
                onBlur: page.blurField({ field: 'name' }),
              }),
              fieldError(state.errors.name),
              Padding({
                padding: { top: 10 },
                child: TextField({
                  value: state.email,
                  labelText: 'Email',
                  keyboardType: 'emailAddress',
                  textInputAction: 'next',
                  onChanged: page.updateField({ field: 'email' }),
                  onFocus: page.focusField({ field: 'email' }),
                  onBlur: page.blurField({ field: 'email' }),
                }),
              }),
              fieldError(state.errors.email),
              Padding({
                padding: { top: 10 },
                child: TextField({
                  value: state.bio,
                  labelText: 'Bio',
                  maxLines: 3,
                  textInputAction: 'done',
                  onChanged: page.updateField({ field: 'bio' }),
                  onSubmitted: page.saveProfile(),
                  onFocus: page.focusField({ field: 'bio' }),
                  onBlur: page.blurField({ field: 'bio' }),
                }),
              }),
              fieldError(state.errors.bio),
              Padding({
                padding: { top: 12 },
                child: ElevatedButton({
                  onPressed: page.saveProfile(),
                  child: Text('Save profile'),
                }),
              }),
            ],
          }),
        }),
        Padding({
          padding: { top: 12 },
          child: Container({
            padding: { all: 12 },
            decoration: {
              color: '$primaryContainer',
              borderRadius: 12,
            },
            child: Column({
              crossAxisAlignment: 'stretch',
              children: [
                Text('Preview', {
                  style: { color: '$onPrimaryContainer', fontWeight: 'w700' },
                }),
                Text(`${state.name} · ${state.email}`, {
                  style: { color: '$onPrimaryContainer', fontSize: 13 },
                }),
                Text(state.bio, {
                  style: { color: '$onPrimaryContainer', fontSize: 13 },
                }),
              ],
            }),
          }),
        }),
      ],
    });
  },

  updateField(state, payload, props, event) {
    const next = {
      ...state,
      [payload.field]: event.value ?? '',
    };
    return {
      ...next,
      errors: validate(next),
      status: `Editing ${payload.field}`,
    };
  },

  focusField(state, payload) {
    return { ...state, status: `Focused ${payload.field}` };
  },

  blurField(state, payload) {
    return {
      ...state,
      errors: validate(state),
      status: `Updated ${payload.field}`,
    };
  },

  saveProfile(state) {
    const errors = validate(state);
    if (Object.keys(errors).length > 0) {
      return {
        ...state,
        errors,
        status: 'Fix validation errors before saving',
      };
    }
    return {
      ...state,
      errors,
      status: `Saved profile for ${state.name}`,
    };
  },
});

function validate(state) {
  const errors = {};
  if (!String(state.name ?? '').trim()) {
    errors.name = 'Name is required';
  }
  const email = String(state.email ?? '').trim();
  if (!email) {
    errors.email = 'Email is required';
  } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    errors.email = 'Enter a valid email address';
  }
  if (String(state.bio ?? '').trim().length < 12) {
    errors.bio = 'Bio must be at least 12 characters';
  }
  return errors;
}

function fieldError(message) {
  if (!message) {
    return Padding({ padding: { top: 0 }, child: Text('') });
  }
  return Padding({
    padding: { top: 4 },
    child: Text(message, {
      style: { color: '$error', fontSize: 12, fontWeight: 'w600' },
    }),
  });
}
