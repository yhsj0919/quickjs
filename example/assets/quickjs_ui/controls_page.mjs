import {
    Center,
    Column,
    Container,
    Image,
    ListView,
    Page,
    Padding,
    SizedBox,
    Stack,
    Text,
    TextField,
} from 'quickjs_ui';

export default Page({
    name: 'ControlsPage',

    createState() {
        return {
            name: 'Ada',
            status: 'ready'
        };
    },

    build(state, props, page) {
        return ListView({
            padding: {all: 16},
            children: [
                Padding({
                    padding: {bottom: 12},
                    child: Text('QuickJS UI controls', {
                        style: '$text.titleMedium'
                    })
                }),
                Container({
                    padding: {all: 12},
                    margin: {bottom: 12},
                    decoration: {
                        color: '$primaryContainer',
                        borderRadius: 10,
                        border: {color: '$outline', width: 1}
                    },
                    child: Column({
                        crossAxisAlignment: 'stretch',
                        children: [
                            Text('ThemeData tokens from JS', {
                                style: {color: '$onPrimaryContainer', fontWeight: 'w700'}
                            }),
                            Text('This card uses $primaryContainer, $outline and $text.titleMedium.', {
                                style: {color: '$onPrimaryContainer', fontSize: 13}
                            })
                        ]
                    })
                }),
                Container({
                    padding: {all: 12},
                    margin: {bottom: 12},
                    decoration: {
                        color: '$surface',
                        borderRadius: 10,
                        border: {color: '$outline', width: 1}
                    },
                    child: Column({
                        crossAxisAlignment: 'stretch',
                        children: [
                            Text('Third-party image resource', {
                                style: {fontWeight: 'w700'}
                            }),
                            Padding({
                                padding: {top: 8, bottom: 8},
                                child: Image({
                                    src: 'https://picsum.photos/seed/quickjs-ui/320/120',
                                    height: 120,
                                    fit: 'cover'
                                })
                            }),
                            Text('Loaded with Image.network and styled by ThemeData tokens.', {
                                style: {color: '$outline', fontSize: 13}
                            })
                        ]
                    })
                }),
                Container({
                    padding: {all: 12},
                    margin: {bottom: 12},
                    decoration: {
                        color: '#f4f7fb',
                        borderRadius: 10,
                        border: {color: '#c7d2e3', width: 1}
                    },
                    child: Column({
                        crossAxisAlignment: 'stretch',
                        children: [
                            Text(`TextField value: ${state.name}`),
                            Text(`Input status: ${state.status}`),
                            TextField({
                                value: state.name,
                                labelText: 'Name',
                                hintText: 'Type a name',
                                textInputAction: 'done',
                                onChanged: page.changeName(),
                                onSubmitted: page.submitName(),
                                onFocus: page.focusName(),
                                onBlur: page.blurName()
                            })
                        ]
                    })
                }),
                SizedBox({
                    height: 120,
                    child: Stack({
                        alignment: 'center',
                        children: [
                            Container({
                                width: 220,
                                height: 96,
                                decoration: {
                                    color: '$primary',
                                    borderRadius: 14
                                }
                            }),
                            Image({
                                src: 'web/icons/Icon-192.png',
                                width: 54,
                                height: 54,
                                fit: 'contain'
                            }),
                            Padding({
                                padding: {top: 72},
                                child: Text('Stack + Image + Padding', {
                                    style: {color: '$onPrimary', fontSize: 13, fontWeight: 'w600'}
                                })
                            })
                        ]
                    })
                }),
                Center({
                    child: Container({
                        margin: {top: 12},
                        padding: {horizontal: 14, vertical: 8},
                        decoration: {
                            color: '$secondaryContainer',
                            borderRadius: 999,
                            border: {color: '$outline', width: 1}
                        },
                        child: Text('Center + Container from JS schema', {
                            style: {color: '$onSecondaryContainer'}
                        })
                    })
                })
            ]
        });
    },

    changeName(state, payload, props, event) {
        return {...state, name: event.value ?? '', status: 'changed'};
    },

    submitName(state, payload, props, event) {
        return {...state, name: event.value ?? state.name, status: 'submitted'};
    },

    focusName(state) {
        return {...state, status: 'focused'};
    },

    blurName(state) {
        return {...state, status: 'blurred'};
    }
});
