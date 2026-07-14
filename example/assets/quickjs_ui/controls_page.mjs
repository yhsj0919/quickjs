import {
    AnimatedContainer,
    AnimatedOpacity,
    AnimatedPadding,
    Center,
    Column,
    Container,
    ElevatedButton,
    GestureDetector,
    Hero,
    Image,
    ListView,
    Page,
    Padding,
    Placeholder,
    Row,
    SizedBox,
    Stack,
    Text,
    TextField,
    TextFormField,
    Tooltip,
    VerticalDivider,
} from 'quickjs_ui';

export default Page({
    name: 'ControlsPage',

    createState() {
        return {
            name: 'Ada',
            status: 'ready',
            formValue: 'QuickJS UI',
            gestureCount: 0,
            animated: false
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
                        gap: 12,
                        children: [
                            Text('Planned controls', {
                                style: {fontWeight: 'w700', color: '$primary'}
                            }),
                            SizedBox({
                                height: 44,
                                child: Row({
                                    children: [
                                        Text('Vertical'),
                                        VerticalDivider({
                                            width: 24,
                                            thickness: 2,
                                            color: '$primary'
                                        }),
                                        Text('Divider')
                                    ]
                                })
                            }),
                            SizedBox({
                                height: 72,
                                child: Placeholder({
                                    color: '$outline',
                                    strokeWidth: 2,
                                    fallbackHeight: 72
                                })
                            }),
                            GestureDetector({
                                onTap: page.tapGesture(),
                                child: Container({
                                    padding: {all: 12},
                                    decoration: {
                                        color: '$secondaryContainer',
                                        borderRadius: 8
                                    },
                                    child: Text(`GestureDetector taps: ${state.gestureCount}`, {
                                        style: {color: '$onSecondaryContainer'}
                                    })
                                })
                            }),
                            TextFormField({
                                value: state.formValue,
                                labelText: 'TextFormField',
                                helperText: 'At least 3 characters',
                                ...(state.formValue.length < 3
                                    ? {errorText: 'Value is too short'}
                                    : {}),
                                onChanged: page.changeFormValue()
                            }),
                            Tooltip({
                                message: 'Rendered by Flutter Tooltip',
                                waitDurationMs: 300,
                                child: Container({
                                    padding: {all: 10},
                                    alignment: 'center',
                                    decoration: {
                                        color: '$primaryContainer',
                                        borderRadius: 8
                                    },
                                    child: Text('Long press for Tooltip')
                                })
                            }),
                            ElevatedButton({
                                label: state.animated ? 'Reset animation' : 'Run animation',
                                onPressed: page.toggleAnimation()
                            }),
                            AnimatedContainer({
                                durationMs: 260,
                                animationCurve: 'easeInOut',
                                height: state.animated ? 84 : 48,
                                padding: state.animated ? 16 : 6,
                                alignment: 'center',
                                decoration: {
                                    color: state.animated ? '$primary' : '$primaryContainer',
                                    borderRadius: state.animated ? 20 : 6
                                },
                                child: AnimatedOpacity({
                                    durationMs: 260,
                                    opacity: state.animated ? 1 : 0.45,
                                    child: AnimatedPadding({
                                        durationMs: 260,
                                        padding: state.animated ? 8 : 0,
                                        child: Text('AnimatedContainer + Opacity + Padding', {
                                            style: {
                                                color: state.animated
                                                    ? '$onPrimary'
                                                    : '$onPrimaryContainer'
                                            }
                                        })
                                    })
                                })
                            }),
                            Hero({
                                tag: 'controls-page-hero',
                                child: Container({
                                    height: 52,
                                    alignment: 'center',
                                    decoration: {
                                        color: '$tertiary',
                                        borderRadius: 26
                                    },
                                    child: Text('Hero tag: controls-page-hero', {
                                        style: {color: '$onTertiary'}
                                    })
                                })
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
        return {name: event.value ?? '', status: 'changed'};
    },

    submitName(state, payload, props, event) {
        return {name: event.value ?? state.name, status: 'submitted'};
    },

    focusName(state) {
        return {status: 'focused'};
    },

    blurName(state) {
        return {status: 'blurred'};
    },

    tapGesture(state) {
        return {gestureCount: state.gestureCount + 1};
    },

    changeFormValue(state, payload, props, event) {
        return {formValue: event.value ?? ''};
    },

    toggleAnimation(state) {
        return {animated: !state.animated};
    }
});
