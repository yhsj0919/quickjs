import 'dart:async';
import 'dart:convert';

import 'package:quickjs/quickjs.dart';

enum QuickjsUiHostCapability {
  toast,
  confirm,
  dialog,
  snackbar,
  bottomSheet,
  navigation,
  clipboard,
  storage,
  network,
  fileSystem,
  nativeCall,
}

enum QuickjsUiCapabilityConflictPolicy { reject, replace, namespace }

typedef QuickjsUiToastHandler =
    FutureOr<Object?> Function(String message, Map<String, Object?> options);

typedef QuickjsUiConfirmHandler =
    FutureOr<bool> Function(String message, Map<String, Object?> options);

typedef QuickjsUiDialogHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

typedef QuickjsUiSnackbarHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

typedef QuickjsUiBottomSheetHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

typedef QuickjsUiNavigationHandler =
    FutureOr<Object?> Function(Map<String, Object?> intent);

typedef QuickjsUiClipboardReadHandler = FutureOr<String?> Function();

typedef QuickjsUiClipboardWriteHandler =
    FutureOr<Object?> Function(String text);

typedef QuickjsUiNetworkHandler =
    FutureOr<Object?> Function(Map<String, Object?> request);

typedef QuickjsUiFileSystemHandler =
    FutureOr<Object?> Function(Map<String, Object?> operation);

typedef QuickjsUiNativeCallHandler =
    FutureOr<Object?> Function(String method, Object? payload);

final class QuickjsUiHostMethod {
  const QuickjsUiHostMethod({
    required this.name,
    required this.callback,
    this.permission,
    this.inputSchema = const <String, Object?>{},
    this.outputSchema = const <String, Object?>{},
    this.isAsync = true,
    this.debugName,
  });

  final String name;
  final QuickjsHostProviderCallback callback;
  final String? permission;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final bool isAsync;
  final String? debugName;
}

final class QuickjsUiHostCapabilityOptions {
  const QuickjsUiHostCapabilityOptions({
    this.enabled = const <QuickjsUiHostCapability>{
      QuickjsUiHostCapability.toast,
      QuickjsUiHostCapability.confirm,
    },
  });

  const QuickjsUiHostCapabilityOptions.none()
    : enabled = const <QuickjsUiHostCapability>{};

  const QuickjsUiHostCapabilityOptions.all()
    : enabled = const <QuickjsUiHostCapability>{
        QuickjsUiHostCapability.toast,
        QuickjsUiHostCapability.confirm,
        QuickjsUiHostCapability.dialog,
        QuickjsUiHostCapability.snackbar,
        QuickjsUiHostCapability.bottomSheet,
        QuickjsUiHostCapability.navigation,
        QuickjsUiHostCapability.clipboard,
        QuickjsUiHostCapability.storage,
        QuickjsUiHostCapability.network,
        QuickjsUiHostCapability.fileSystem,
        QuickjsUiHostCapability.nativeCall,
      };

  final Set<QuickjsUiHostCapability> enabled;

  bool isEnabled(QuickjsUiHostCapability capability) {
    return enabled.contains(capability);
  }
}

final class QuickjsUiHostApiHandlers {
  const QuickjsUiHostApiHandlers({
    this.onToast,
    this.onConfirm,
    this.onDialog,
    this.onSnackbar,
    this.onBottomSheet,
    this.onNavigationIntent,
    this.onClipboardReadText,
    this.onClipboardWriteText,
    this.onNetworkRequest,
    this.onFileSystemOperation,
    this.onNativeCall,
  });

  final QuickjsUiToastHandler? onToast;
  final QuickjsUiConfirmHandler? onConfirm;
  final QuickjsUiDialogHandler? onDialog;
  final QuickjsUiSnackbarHandler? onSnackbar;
  final QuickjsUiBottomSheetHandler? onBottomSheet;
  final QuickjsUiNavigationHandler? onNavigationIntent;
  final QuickjsUiClipboardReadHandler? onClipboardReadText;
  final QuickjsUiClipboardWriteHandler? onClipboardWriteText;
  final QuickjsUiNetworkHandler? onNetworkRequest;
  final QuickjsUiFileSystemHandler? onFileSystemOperation;
  final QuickjsUiNativeCallHandler? onNativeCall;
}

final class QuickjsUiHostMethodDeclaration {
  const QuickjsUiHostMethodDeclaration({
    required this.name,
    this.providerName,
    this.inputSchema = const <String, Object?>{},
    this.outputSchema = const <String, Object?>{},
    this.isAsync = true,
  });

  final String name;
  final String? providerName;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final bool isAsync;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      if (providerName != null) 'providerName': providerName,
      'async': isAsync,
      if (inputSchema.isNotEmpty) 'inputSchema': inputSchema,
      if (outputSchema.isNotEmpty) 'outputSchema': outputSchema,
    };
  }
}

final class QuickjsUiCapabilityGroup {
  const QuickjsUiCapabilityGroup({
    required this.name,
    required this.mounts,
    this.namespace,
    this.permissions = const <String>{},
    this.methods = const <QuickjsUiHostMethodDeclaration>[],
  });

  factory QuickjsUiCapabilityGroup.system({
    String name = 'quickjs_ui:host:system',
    QuickjsUiHostCapabilityOptions options =
        const QuickjsUiHostCapabilityOptions(),
    QuickjsUiHostApiHandlers handlers = const QuickjsUiHostApiHandlers(),
    Map<String, Object?> storage = const <String, Object?>{},
  }) {
    return QuickjsUiCapabilityGroup(
      name: name,
      namespace: 'system',
      mounts: <QuickjsHostMount>[
        _buildSystemMount(
          name: name,
          options: options,
          handlers: handlers,
          storage: Map<String, Object?>.of(storage),
        ),
      ],
      permissions: {for (final capability in options.enabled) capability.name},
      methods: _systemMethodDeclarations(options),
    );
  }

  factory QuickjsUiCapabilityGroup.methods({
    required String name,
    required List<QuickjsUiHostMethod> methods,
    String namespace = 'app',
    String globalName = 'quickjsUiApp',
    Set<String> permissions = const <String>{},
  }) {
    final providerEntries = <QuickjsHostProvider>[];
    final declarations = <QuickjsUiHostMethodDeclaration>[];
    final apiEntries = <String>[];
    final resolvedPermissions = <String>{...permissions};

    for (final method in methods) {
      final methodName = _validateMethodName(method.name);
      final providerName = '$namespace.$methodName';
      providerEntries.add(
        QuickjsHostProvider.dart(
          name: providerName,
          debugName: method.debugName ?? '$name.$methodName',
          callback: method.callback,
        ),
      );
      declarations.add(
        QuickjsUiHostMethodDeclaration(
          name: '$globalName.$methodName',
          providerName: providerName,
          inputSchema: method.inputSchema,
          outputSchema: method.outputSchema,
          isAsync: method.isAsync,
        ),
      );
      resolvedPermissions.add(method.permission ?? providerName);
      apiEntries.add(
        '[${jsonEncode(methodName)}](...args) { return providers[${jsonEncode(providerName)}](...args); }',
      );
    }

    return QuickjsUiCapabilityGroup(
      name: name,
      namespace: namespace,
      permissions: Set<String>.unmodifiable(resolvedPermissions),
      methods: List<QuickjsUiHostMethodDeclaration>.unmodifiable(declarations),
      mounts: <QuickjsHostMount>[
        QuickjsHostMount(
          name: name,
          providers: List<QuickjsHostProvider>.unmodifiable(providerEntries),
          environmentPatches: <QuickjsHostScript>[
            QuickjsHostScript.js(
              name: '$name:globals.js',
              globals: <String>[globalName],
              source:
                  '''
(() => {
  const providers = globalThis.__quickjsHostProviders;
  const current = globalThis[${jsonEncode(globalName)}] ?? {};
  globalThis[${jsonEncode(globalName)}] = Object.freeze({
    ...current,
    ${apiEntries.join(',\n    ')}
  });
})();
''',
            ),
          ],
        ),
      ],
    );
  }

  factory QuickjsUiCapabilityGroup.functions({
    required String name,
    required Map<String, Function> functions,
    String namespace = 'app',
    String globalName = 'quickjsUiApp',
    Set<String> permissions = const <String>{},
  }) {
    return QuickjsUiCapabilityGroup.methods(
      name: name,
      namespace: namespace,
      globalName: globalName,
      permissions: permissions,
      methods: <QuickjsUiHostMethod>[
        for (final entry in functions.entries)
          QuickjsUiHostMethod(
            name: entry.key,
            callback: (args, _) => Function.apply(entry.value, args),
          ),
      ],
    );
  }

  final String name;
  final String? namespace;
  final List<QuickjsHostMount> mounts;
  final Set<String> permissions;
  final List<QuickjsUiHostMethodDeclaration> methods;
}

final class QuickjsUiHostCapabilities {
  const QuickjsUiHostCapabilities({
    this.groups = const <QuickjsUiCapabilityGroup>[],
    this.conflictPolicy = QuickjsUiCapabilityConflictPolicy.reject,
  });

  factory QuickjsUiHostCapabilities.system({
    QuickjsUiHostCapabilityOptions options =
        const QuickjsUiHostCapabilityOptions(),
    QuickjsUiHostApiHandlers handlers = const QuickjsUiHostApiHandlers(),
    Map<String, Object?> storage = const <String, Object?>{},
    QuickjsUiCapabilityConflictPolicy conflictPolicy =
        QuickjsUiCapabilityConflictPolicy.reject,
  }) {
    return QuickjsUiHostCapabilities(
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.system(
          options: options,
          handlers: handlers,
          storage: storage,
        ),
      ],
      conflictPolicy: conflictPolicy,
    );
  }

  final List<QuickjsUiCapabilityGroup> groups;
  final QuickjsUiCapabilityConflictPolicy conflictPolicy;

  List<QuickjsHostMount> get mounts => toMounts();

  Set<String> get permissions {
    return <String>{for (final group in groups) ...group.permissions};
  }

  List<QuickjsUiHostMethodDeclaration> get methods {
    return List<QuickjsUiHostMethodDeclaration>.unmodifiable(
      groups.expand((group) => group.methods),
    );
  }

  List<Map<String, Object?>> get methodMaps {
    return List<Map<String, Object?>>.unmodifiable(
      methods.map((method) => method.toMap()),
    );
  }

  List<QuickjsHostMount> toMounts() {
    final resolved = <QuickjsHostMount>[];
    for (final group in groups) {
      _validateMethodDeclarations(group);
      for (final mount in group.mounts) {
        _appendMount(resolved, group, mount);
      }
    }
    return List<QuickjsHostMount>.unmodifiable(resolved);
  }

  void _appendMount(
    List<QuickjsHostMount> resolved,
    QuickjsUiCapabilityGroup group,
    QuickjsHostMount mount,
  ) {
    final conflicts = <int>{
      for (var i = 0; i < resolved.length; i++)
        if (_mountsConflict(resolved[i], mount)) i,
    };
    if (conflicts.isEmpty) {
      resolved.add(mount);
      return;
    }
    switch (conflictPolicy) {
      case QuickjsUiCapabilityConflictPolicy.reject:
        throw StateError(
          'quickjs_ui host capability conflict for mount "${mount.name}"',
        );
      case QuickjsUiCapabilityConflictPolicy.replace:
        for (final index in conflicts.toList().reversed) {
          resolved.removeAt(index);
        }
        resolved.add(mount);
      case QuickjsUiCapabilityConflictPolicy.namespace:
        resolved.add(_namespaceMount(group, mount, resolved.length));
    }
  }
}

void _validateMethodDeclarations(QuickjsUiCapabilityGroup group) {
  final providerNames = <String>{
    for (final mount in group.mounts)
      for (final provider in mount.providers) provider.name,
  };
  final declaredProviderNames = <String>{};

  for (final method in group.methods) {
    if (method.name.trim().isEmpty) {
      throw StateError(
        'quickjs_ui capability group "${group.name}" declares an empty method name',
      );
    }
    _validateStructuredValue(method.inputSchema, 'inputSchema', method.name);
    _validateStructuredValue(method.outputSchema, 'outputSchema', method.name);

    final providerName = method.providerName;
    if (providerName == null) {
      continue;
    }
    if (providerName.trim().isEmpty) {
      throw StateError(
        'quickjs_ui capability method "${method.name}" declares an empty providerName',
      );
    }
    if (!providerNames.contains(providerName)) {
      throw StateError(
        'quickjs_ui capability method "${method.name}" references unknown provider "$providerName"',
      );
    }
    declaredProviderNames.add(providerName);
  }

  final missing = providerNames.difference(declaredProviderNames);
  if (missing.isNotEmpty) {
    throw StateError(
      'quickjs_ui capability group "${group.name}" exposes providers without method declarations: ${missing.join(', ')}',
    );
  }
}

void _validateStructuredValue(Object? value, String field, String methodName) {
  if (value == null || value is bool || value is num || value is String) {
    return;
  }
  if (value is List) {
    for (final item in value) {
      _validateStructuredValue(item, field, methodName);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw StateError(
          'quickjs_ui capability method "$methodName" $field must use string keys',
        );
      }
      _validateStructuredValue(entry.value, field, methodName);
    }
    return;
  }
  throw StateError(
    'quickjs_ui capability method "$methodName" $field must be a structured value',
  );
}

String _validateMethodName(String value) {
  final name = value.trim();
  if (name.isEmpty) {
    throw StateError('quickjs_ui host method name must not be empty');
  }
  if (name.contains('.')) {
    throw StateError(
      'quickjs_ui host method name "$name" must be local to its JS global',
    );
  }
  return name;
}

List<QuickjsUiHostMethodDeclaration> _systemMethodDeclarations(
  QuickjsUiHostCapabilityOptions options,
) {
  final methods = <QuickjsUiHostMethodDeclaration>[];

  void method(
    QuickjsUiHostCapability capability,
    String name, {
    String? providerName,
    Map<String, Object?> inputSchema = const <String, Object?>{},
    Map<String, Object?> outputSchema = const <String, Object?>{},
  }) {
    if (!options.isEnabled(capability)) {
      return;
    }
    methods.add(
      QuickjsUiHostMethodDeclaration(
        name: name,
        providerName: providerName,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
      ),
    );
  }

  method(
    QuickjsUiHostCapability.toast,
    'quickjsUiHost.toast',
    providerName: 'quickjs_ui.host.toast',
    inputSchema: _objectSchema(
      <String, Object?>{'message': _stringSchema(), 'options': _objectSchema()},
      const <String>['message'],
    ),
    outputSchema: _objectSchema(),
  );
  method(
    QuickjsUiHostCapability.confirm,
    'quickjsUiHost.confirm',
    providerName: 'quickjs_ui.host.confirm',
    inputSchema: _objectSchema(
      <String, Object?>{'message': _stringSchema(), 'options': _objectSchema()},
      const <String>['message'],
    ),
    outputSchema: _boolSchema(),
  );
  method(
    QuickjsUiHostCapability.navigation,
    'quickjsUiHost.navigationIntent',
    providerName: 'quickjs_ui.host.navigation',
    inputSchema: _objectSchema(<String, Object?>{'intent': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.dialog,
    'quickjsUiHost.dialog',
    providerName: 'quickjs_ui.host.dialog',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.snackbar,
    'quickjsUiHost.snackbar',
    providerName: 'quickjs_ui.host.snackbar',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.bottomSheet,
    'quickjsUiHost.bottomSheet',
    providerName: 'quickjs_ui.host.bottomSheet',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.clipboard,
    'quickjsUiHost.clipboard.readText',
    providerName: 'quickjs_ui.host.clipboard.readText',
    outputSchema: <String, Object?>{
      'oneOf': <Object?>[_stringSchema(), _nullSchema()],
    },
  );
  method(
    QuickjsUiHostCapability.clipboard,
    'quickjsUiHost.clipboard.writeText',
    providerName: 'quickjs_ui.host.clipboard.writeText',
    inputSchema: _objectSchema(<String, Object?>{'text': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.storage,
    'quickjsUiHost.storage.getItem',
    providerName: 'quickjs_ui.host.storage.getItem',
    inputSchema: _objectSchema(<String, Object?>{'key': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.storage,
    'quickjsUiHost.storage.setItem',
    providerName: 'quickjs_ui.host.storage.setItem',
    inputSchema: _objectSchema(
      <String, Object?>{'key': _stringSchema(), 'value': _anySchema()},
      const <String>['key'],
    ),
    outputSchema: _boolSchema(),
  );
  method(
    QuickjsUiHostCapability.storage,
    'quickjsUiHost.storage.removeItem',
    providerName: 'quickjs_ui.host.storage.removeItem',
    inputSchema: _objectSchema(<String, Object?>{'key': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.network,
    'quickjsUiHost.network',
    providerName: 'quickjs_ui.host.network',
    inputSchema: _objectSchema(<String, Object?>{'request': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.fileSystem,
    'quickjsUiHost.fileSystem',
    providerName: 'quickjs_ui.host.fileSystem',
    inputSchema: _objectSchema(<String, Object?>{'operation': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    QuickjsUiHostCapability.nativeCall,
    'quickjsUiHost.nativeCall',
    providerName: 'quickjs_ui.host.nativeCall',
    inputSchema: _objectSchema(
      <String, Object?>{'method': _stringSchema(), 'payload': _anySchema()},
      const <String>['method'],
    ),
    outputSchema: _anySchema(),
  );
  return List<QuickjsUiHostMethodDeclaration>.unmodifiable(methods);
}

QuickjsHostMount _buildSystemMount({
  required String name,
  required QuickjsUiHostCapabilityOptions options,
  required QuickjsUiHostApiHandlers handlers,
  required Map<String, Object?> storage,
}) {
  final providers = <QuickjsHostProvider>[];
  final apiEntries = <String>[];

  void provider(
    QuickjsUiHostCapability capability,
    String name,
    QuickjsHostProviderCallback callback,
  ) {
    if (!options.isEnabled(capability)) {
      return;
    }
    providers.add(
      QuickjsHostProvider.dart(
        name: name,
        debugName: 'quickjs_ui host ${capability.name}',
        callback: callback,
      ),
    );
  }

  provider(QuickjsUiHostCapability.toast, 'quickjs_ui.host.toast', (args, _) {
    final message = _stringArg(args, 0, 'toast message');
    final options = _mapArg(args, 1);
    return handlers.onToast?.call(message, options) ??
        <String, Object?>{'shown': true, 'message': message};
  });
  if (options.isEnabled(QuickjsUiHostCapability.toast)) {
    apiEntries.add(
      'toast(message, options = {}) { return providers[${jsonEncode('quickjs_ui.host.toast')}](message, options); }',
    );
  }

  provider(QuickjsUiHostCapability.confirm, 'quickjs_ui.host.confirm', (
    args,
    _,
  ) {
    final message = _stringArg(args, 0, 'confirm message');
    final options = _mapArg(args, 1);
    return handlers.onConfirm?.call(message, options) ?? false;
  });
  if (options.isEnabled(QuickjsUiHostCapability.confirm)) {
    apiEntries.add(
      'confirm(message, options = {}) { return providers[${jsonEncode('quickjs_ui.host.confirm')}](message, options); }',
    );
  }

  provider(QuickjsUiHostCapability.navigation, 'quickjs_ui.host.navigation', (
    args,
    _,
  ) {
    final intent = _mapArg(args, 0);
    return _requireHandler(
      handlers.onNavigationIntent,
      'navigation',
    ).call(intent);
  });
  if (options.isEnabled(QuickjsUiHostCapability.navigation)) {
    apiEntries.add(
      'navigationIntent(intent) { return providers[${jsonEncode('quickjs_ui.host.navigation')}](intent); }',
    );
  }

  provider(QuickjsUiHostCapability.dialog, 'quickjs_ui.host.dialog', (args, _) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onDialog, 'dialog').call(payload);
  });
  if (options.isEnabled(QuickjsUiHostCapability.dialog)) {
    apiEntries.add(
      'dialog(payload) { return providers[${jsonEncode('quickjs_ui.host.dialog')}](payload); }',
    );
  }

  provider(QuickjsUiHostCapability.snackbar, 'quickjs_ui.host.snackbar', (
    args,
    _,
  ) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onSnackbar, 'snackbar').call(payload);
  });
  if (options.isEnabled(QuickjsUiHostCapability.snackbar)) {
    apiEntries.add(
      'snackbar(payload) { return providers[${jsonEncode('quickjs_ui.host.snackbar')}](payload); }',
    );
  }

  provider(QuickjsUiHostCapability.bottomSheet, 'quickjs_ui.host.bottomSheet', (
    args,
    _,
  ) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onBottomSheet, 'bottomSheet').call(payload);
  });
  if (options.isEnabled(QuickjsUiHostCapability.bottomSheet)) {
    apiEntries.add(
      'bottomSheet(payload) { return providers[${jsonEncode('quickjs_ui.host.bottomSheet')}](payload); }',
    );
  }

  if (options.isEnabled(QuickjsUiHostCapability.clipboard)) {
    providers
      ..add(
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.host.clipboard.readText',
          debugName: 'quickjs_ui host clipboard readText',
          callback: (_, _) {
            return handlers.onClipboardReadText?.call();
          },
        ),
      )
      ..add(
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.host.clipboard.writeText',
          debugName: 'quickjs_ui host clipboard writeText',
          callback: (args, _) {
            final text = _stringArg(args, 0, 'clipboard text');
            return handlers.onClipboardWriteText?.call(text);
          },
        ),
      );
    apiEntries.add('''
clipboard: {
  readText() { return providers[${jsonEncode('quickjs_ui.host.clipboard.readText')}](); },
  writeText(text) { return providers[${jsonEncode('quickjs_ui.host.clipboard.writeText')}](text); }
}''');
  }

  if (options.isEnabled(QuickjsUiHostCapability.storage)) {
    providers
      ..add(
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.host.storage.getItem',
          debugName: 'quickjs_ui host storage getItem',
          callback: (args, _) {
            return storage[_stringArg(args, 0, 'storage key')];
          },
        ),
      )
      ..add(
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.host.storage.setItem',
          debugName: 'quickjs_ui host storage setItem',
          callback: (args, _) {
            storage[_stringArg(args, 0, 'storage key')] = args.length > 1
                ? args[1]
                : null;
            return true;
          },
        ),
      )
      ..add(
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.host.storage.removeItem',
          debugName: 'quickjs_ui host storage removeItem',
          callback: (args, _) {
            return storage.remove(_stringArg(args, 0, 'storage key'));
          },
        ),
      );
    apiEntries.add('''
storage: {
  getItem(key) { return providers[${jsonEncode('quickjs_ui.host.storage.getItem')}](key); },
  setItem(key, value) { return providers[${jsonEncode('quickjs_ui.host.storage.setItem')}](key, value); },
  removeItem(key) { return providers[${jsonEncode('quickjs_ui.host.storage.removeItem')}](key); }
}''');
  }

  provider(QuickjsUiHostCapability.network, 'quickjs_ui.host.network', (
    args,
    _,
  ) {
    final request = _mapArg(args, 0);
    return _requireHandler(handlers.onNetworkRequest, 'network').call(request);
  });
  if (options.isEnabled(QuickjsUiHostCapability.network)) {
    apiEntries.add(
      'network(request) { return providers[${jsonEncode('quickjs_ui.host.network')}](request); }',
    );
  }

  provider(QuickjsUiHostCapability.fileSystem, 'quickjs_ui.host.fileSystem', (
    args,
    _,
  ) {
    final operation = _mapArg(args, 0);
    return _requireHandler(
      handlers.onFileSystemOperation,
      'fileSystem',
    ).call(operation);
  });
  if (options.isEnabled(QuickjsUiHostCapability.fileSystem)) {
    apiEntries.add(
      'fileSystem(operation) { return providers[${jsonEncode('quickjs_ui.host.fileSystem')}](operation); }',
    );
  }

  provider(QuickjsUiHostCapability.nativeCall, 'quickjs_ui.host.nativeCall', (
    args,
    _,
  ) {
    final method = _stringArg(args, 0, 'native method');
    final payload = args.length > 1 ? args[1] : null;
    return _requireHandler(
      handlers.onNativeCall,
      'nativeCall',
    ).call(method, payload);
  });
  if (options.isEnabled(QuickjsUiHostCapability.nativeCall)) {
    apiEntries.add(
      'nativeCall(method, payload) { return providers[${jsonEncode('quickjs_ui.host.nativeCall')}](method, payload); }',
    );
  }

  return QuickjsHostMount(
    name: name,
    providers: providers,
    environmentPatches: <QuickjsHostScript>[
      QuickjsHostScript.js(
        name: '$name:globals.js',
        globals: const <String>['quickjsUiHost'],
        source:
            '''
(() => {
  const providers = globalThis.__quickjsHostProviders;
  globalThis.quickjsUiHost = Object.freeze({
    ${apiEntries.join(',\n    ')}
  });
})();
''',
      ),
    ],
  );
}

bool _mountsConflict(QuickjsHostMount left, QuickjsHostMount right) {
  return left.name == right.name ||
      _intersects(
        left.providers.map((provider) => provider.name),
        right.providers.map((provider) => provider.name),
      ) ||
      _intersects(
        left.environmentPatches.expand((script) => script.globals),
        right.environmentPatches.expand((script) => script.globals),
      ) ||
      _intersects(
        left.modules.map((module) => module.specifier),
        right.modules.map((module) => module.specifier),
      );
}

bool _intersects(Iterable<String> left, Iterable<String> right) {
  final seen = left.toSet();
  return right.any(seen.contains);
}

Map<String, Object?> _anySchema() {
  return const <String, Object?>{};
}

Map<String, Object?> _boolSchema() {
  return const <String, Object?>{'type': 'boolean'};
}

Map<String, Object?> _nullSchema() {
  return const <String, Object?>{'type': 'null'};
}

Map<String, Object?> _objectSchema([
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
]) {
  return <String, Object?>{
    'type': 'object',
    if (properties.isNotEmpty) 'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };
}

Map<String, Object?> _stringSchema() {
  return const <String, Object?>{'type': 'string'};
}

QuickjsHostMount _namespaceMount(
  QuickjsUiCapabilityGroup group,
  QuickjsHostMount mount,
  int index,
) {
  final namespace = group.namespace ?? group.name;
  return QuickjsHostMount(
    name: '$namespace:${mount.name}:$index',
    capabilities: mount.capabilities,
    environmentPatches: mount.environmentPatches,
    modules: mount.modules,
    providers: mount.providers,
  );
}

String _stringArg(List<Object?> args, int index, String label) {
  if (args.length <= index || args[index] is! String) {
    throw ArgumentError('quickjs_ui host $label must be a string');
  }
  return args[index]! as String;
}

Map<String, Object?> _mapArg(List<Object?> args, int index) {
  if (args.length <= index || args[index] == null) {
    return <String, Object?>{};
  }
  final value = args[index];
  if (value is! Map) {
    throw ArgumentError('quickjs_ui host argument must be an object');
  }
  return value.map((key, value) => MapEntry<String, Object?>('$key', value));
}

T _requireHandler<T extends Function>(T? handler, String capability) {
  if (handler == null) {
    throw StateError(
      'quickjs_ui host capability "$capability" is enabled without a handler',
    );
  }
  return handler;
}
