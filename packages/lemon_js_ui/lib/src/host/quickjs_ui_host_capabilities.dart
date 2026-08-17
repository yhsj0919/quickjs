import 'dart:async';
import 'dart:convert';

import 'package:lemon_js/lemon_js.dart';

/// A system service that may be exposed to a QuickJS UI page.
enum JsUiHostCapability {
  /// Displays a short, non-interactive message.
  toast,

  /// Asks the user to confirm an action.
  confirm,

  /// Presents a host-defined dialog.
  dialog,

  /// Presents a transient snackbar message.
  snackbar,

  /// Presents content in a host-defined bottom sheet.
  bottomSheet,

  /// Sends a navigation intent to the host application.
  navigation,

  /// Reads or writes text through the platform clipboard.
  clipboard,

  /// Accesses the in-memory key-value store supplied to the capability group.
  storage,

  /// Delegates a network request to the host application.
  network,

  /// Delegates a file-system operation to the host application.
  fileSystem,

  /// Invokes an application-specific native method.
  nativeCall,
}

/// Determines how [JsUiHostFeatures] resolves conflicting feature groups.
enum JsUiCapabilityConflictPolicy {
  /// Throws a [StateError] when two groups expose the same feature surface.
  reject,

  /// Removes previously resolved conflicts and keeps the later group.
  replace,

  /// Keeps both groups and assigns the later feature a distinct feature name.
  namespace,
}

/// Handles `jsUiHost.toast(message, options)`.
typedef JsUiToastHandler =
    FutureOr<Object?> Function(String message, Map<String, Object?> options);

/// Handles `jsUiHost.confirm(message, options)` and returns the user's choice.
typedef JsUiConfirmHandler =
    FutureOr<bool> Function(String message, Map<String, Object?> options);

/// Handles `jsUiHost.dialog(payload)` with an application-defined payload.
typedef JsUiDialogHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

/// Handles `jsUiHost.snackbar(payload)` with an application-defined payload.
typedef JsUiSnackbarHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

/// Handles `jsUiHost.bottomSheet(payload)`.
typedef JsUiBottomSheetHandler =
    FutureOr<Object?> Function(Map<String, Object?> payload);

/// Handles a host-specific navigation [intent].
typedef JsUiNavigationHandler =
    FutureOr<Object?> Function(Map<String, Object?> intent);

/// Reads text from the platform clipboard, or returns `null` when unavailable.
typedef JsUiClipboardReadHandler = FutureOr<String?> Function();

/// Writes [text] to the platform clipboard.
typedef JsUiClipboardWriteHandler = FutureOr<Object?> Function(String text);

/// Handles a host-mediated network [request].
typedef JsUiNetworkHandler =
    FutureOr<Object?> Function(Map<String, Object?> request);

/// Handles a host-mediated file-system [operation].
typedef JsUiFileSystemHandler =
    FutureOr<Object?> Function(Map<String, Object?> operation);

/// Invokes the application-defined native [method] with an optional [payload].
typedef JsUiNativeCallHandler =
    FutureOr<Object?> Function(String method, Object? payload);

/// Describes an application host method exposed to a QuickJS UI page.
final class JsUiHostMethod {
  /// Creates a host method with its callback, schemas, and permission metadata.
  const JsUiHostMethod({
    required this.name,
    required this.callback,
    this.permission,
    this.inputSchema = const <String, Object?>{},
    this.outputSchema = const <String, Object?>{},
    this.isAsync = true,
    this.debugName,
  });

  /// The method name local to the generated JavaScript global.
  final String name;

  /// The callback invoked by the Lemon JS host-method bridge.
  final JsHostMethodCallback callback;

  /// The required permission, or the generated host method name when omitted.
  final String? permission;

  /// A structured schema describing the method arguments.
  final Map<String, Object?> inputSchema;

  /// A structured schema describing the method result.
  final Map<String, Object?> outputSchema;

  /// Whether callers should treat the method result as asynchronous.
  final bool isAsync;

  /// An optional diagnostic name used by the host-method bridge.
  final String? debugName;
}

/// Selects which built-in `jsUiHost` services are installed.
final class JsUiHostCapabilityOptions {
  /// Creates options that enable toast and confirmation services by default.
  const JsUiHostCapabilityOptions({
    this.enabled = const <JsUiHostCapability>{
      JsUiHostCapability.toast,
      JsUiHostCapability.confirm,
    },
  });

  /// Creates options with no built-in host services enabled.
  const JsUiHostCapabilityOptions.none()
    : enabled = const <JsUiHostCapability>{};

  /// Creates options with every built-in host service enabled.
  const JsUiHostCapabilityOptions.all()
    : enabled = const <JsUiHostCapability>{
        JsUiHostCapability.toast,
        JsUiHostCapability.confirm,
        JsUiHostCapability.dialog,
        JsUiHostCapability.snackbar,
        JsUiHostCapability.bottomSheet,
        JsUiHostCapability.navigation,
        JsUiHostCapability.clipboard,
        JsUiHostCapability.storage,
        JsUiHostCapability.network,
        JsUiHostCapability.fileSystem,
        JsUiHostCapability.nativeCall,
      };

  /// The built-in services to install in the JavaScript runtime.
  final Set<JsUiHostCapability> enabled;

  /// Whether [capability] is enabled.
  bool isEnabled(JsUiHostCapability capability) {
    return enabled.contains(capability);
  }
}

/// Supplies application callbacks for the built-in `jsUiHost` services.
///
/// Enabling a service does not install a default privileged implementation.
/// Services that require a handler throw [StateError] when invoked without one;
/// missing clipboard handlers instead produce a `null` bridge result.
final class JsUiHostApiHandlers {
  /// Creates a set of optional host-service callbacks.
  const JsUiHostApiHandlers({
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

  /// Callback for toast messages.
  final JsUiToastHandler? onToast;

  /// Callback for confirmation prompts.
  final JsUiConfirmHandler? onConfirm;

  /// Callback for dialogs.
  final JsUiDialogHandler? onDialog;

  /// Callback for snackbar messages.
  final JsUiSnackbarHandler? onSnackbar;

  /// Callback for bottom sheets.
  final JsUiBottomSheetHandler? onBottomSheet;

  /// Callback for navigation intents.
  final JsUiNavigationHandler? onNavigationIntent;

  /// Callback for clipboard reads.
  final JsUiClipboardReadHandler? onClipboardReadText;

  /// Callback for clipboard writes.
  final JsUiClipboardWriteHandler? onClipboardWriteText;

  /// Callback for network requests.
  final JsUiNetworkHandler? onNetworkRequest;

  /// Callback for file-system operations.
  final JsUiFileSystemHandler? onFileSystemOperation;

  /// Callback for application-specific native calls.
  final JsUiNativeCallHandler? onNativeCall;
}

/// Metadata describing a JavaScript method exposed by a capability group.
final class JsUiHostMethodDeclaration {
  /// Creates a declaration used by tooling and permission inspection.
  const JsUiHostMethodDeclaration({
    required this.name,
    this.hostMethodName,
    this.inputSchema = const <String, Object?>{},
    this.outputSchema = const <String, Object?>{},
    this.isAsync = true,
  });

  /// The fully qualified method name visible to JavaScript.
  final String name;

  /// The backing Lemon JS host method, if the declaration has one.
  final String? hostMethodName;

  /// A structured schema describing the method arguments.
  final Map<String, Object?> inputSchema;

  /// A structured schema describing the method result.
  final Map<String, Object?> outputSchema;

  /// Whether callers should treat the result as asynchronous.
  final bool isAsync;

  /// Serializes this declaration to structured manifest metadata.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      if (hostMethodName != null) 'hostMethodName': hostMethodName,
      'async': isAsync,
      if (inputSchema.isNotEmpty) 'inputSchema': inputSchema,
      if (outputSchema.isNotEmpty) 'outputSchema': outputSchema,
    };
  }
}

/// A named collection of runtime features, permissions, and method metadata.
final class JsUiCapabilityGroup {
  /// Creates a capability group from already constructed Lemon JS [features].
  const JsUiCapabilityGroup({
    required this.name,
    required this.features,
    this.namespace,
    this.permissions = const <String>{},
    this.methods = const <JsUiHostMethodDeclaration>[],
  });

  /// Creates the built-in `jsUiHost` capability group.
  ///
  /// [storage] is copied into a private, per-group in-memory store. Privileged
  /// capabilities such as network, file-system, and native calls are only
  /// delegated through the corresponding callback in [handlers].
  factory JsUiCapabilityGroup.system({
    String name = 'quickjs_ui:host:system',
    JsUiHostCapabilityOptions options = const JsUiHostCapabilityOptions(),
    JsUiHostApiHandlers handlers = const JsUiHostApiHandlers(),
    Map<String, Object?> storage = const <String, Object?>{},
  }) {
    return JsUiCapabilityGroup(
      name: name,
      namespace: 'system',
      features: <JsFeatures>[
        _buildSystemFeatures(
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

  /// Creates an application method group exposed below [globalName].
  ///
  /// Each method receives the host name `<namespace>.<method>` and requires its
  /// explicit permission, or that generated host name when none is supplied.
  factory JsUiCapabilityGroup.methods({
    required String name,
    required List<JsUiHostMethod> methods,
    String namespace = 'app',
    String globalName = 'jsUiApp',
    Set<String> permissions = const <String>{},
  }) {
    final hostMethods = <JsHostMethod>[];
    final declarations = <JsUiHostMethodDeclaration>[];
    final apiEntries = <String>[];
    final resolvedPermissions = <String>{...permissions};

    for (final method in methods) {
      final methodName = _validateMethodName(method.name);
      final hostMethodName = '$namespace.$methodName';
      hostMethods.add(
        JsHostMethod(
          name: hostMethodName,
          debugName: method.debugName ?? '$name.$methodName',
          callback: method.callback,
        ),
      );
      declarations.add(
        JsUiHostMethodDeclaration(
          name: '$globalName.$methodName',
          hostMethodName: hostMethodName,
          inputSchema: method.inputSchema,
          outputSchema: method.outputSchema,
          isAsync: method.isAsync,
        ),
      );
      resolvedPermissions.add(method.permission ?? hostMethodName);
      apiEntries.add(
        '[${jsonEncode(methodName)}](...args) { return methods[${jsonEncode(hostMethodName)}](...args); }',
      );
    }

    return JsUiCapabilityGroup(
      name: name,
      namespace: namespace,
      permissions: Set<String>.unmodifiable(resolvedPermissions),
      methods: List<JsUiHostMethodDeclaration>.unmodifiable(declarations),
      features: <JsFeatures>[
        JsFeatures(
          name: name,
          methods: List<JsHostMethod>.unmodifiable(hostMethods),
          scripts: <JsScript>[
            JsScript(
              name: '$name:globals.js',
              globals: <String>[globalName],
              source:
                  '''
(() => {
  const methods = globalThis.__jsHostMethods;
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

  /// The diagnostic and Lemon JS feature name for this group.
  final String name;

  /// The namespace used for generated host methods and conflict resolution.
  final String? namespace;

  /// The Lemon JS runtime features installed by this group.
  final List<JsFeatures> features;

  /// Permissions declared or inferred for the group.
  final Set<String> permissions;

  /// JavaScript method declarations exposed for inspection and tooling.
  final List<JsUiHostMethodDeclaration> methods;
}

/// Resolves capability groups into installable Lemon JS runtime features.
final class JsUiHostFeatures {
  /// Creates a feature collection with the specified conflict policy.
  const JsUiHostFeatures({
    this.groups = const <JsUiCapabilityGroup>[],
    this.conflictPolicy = JsUiCapabilityConflictPolicy.reject,
  });

  /// Creates a feature collection containing the built-in system group.
  factory JsUiHostFeatures.system({
    JsUiHostCapabilityOptions options = const JsUiHostCapabilityOptions(),
    JsUiHostApiHandlers handlers = const JsUiHostApiHandlers(),
    Map<String, Object?> storage = const <String, Object?>{},
    JsUiCapabilityConflictPolicy conflictPolicy =
        JsUiCapabilityConflictPolicy.reject,
  }) {
    return JsUiHostFeatures(
      groups: <JsUiCapabilityGroup>[
        JsUiCapabilityGroup.system(
          options: options,
          handlers: handlers,
          storage: storage,
        ),
      ],
      conflictPolicy: conflictPolicy,
    );
  }

  /// Capability groups in resolution order.
  final List<JsUiCapabilityGroup> groups;

  /// The policy applied when groups expose overlapping runtime surfaces.
  final JsUiCapabilityConflictPolicy conflictPolicy;

  /// Resolved Lemon JS features ready to install in a runtime.
  List<JsFeatures> get features => _resolveFeatures();

  /// The union of permissions declared by all [groups].
  Set<String> get permissions {
    return <String>{for (final group in groups) ...group.permissions};
  }

  /// All method declarations in [groups], in group order.
  List<JsUiHostMethodDeclaration> get methods {
    return List<JsUiHostMethodDeclaration>.unmodifiable(
      groups.expand((group) => group.methods),
    );
  }

  List<JsFeatures> _resolveFeatures() {
    final resolved = <JsFeatures>[];
    for (final group in groups) {
      _validateMethodDeclarations(group);
      for (final features in group.features) {
        _appendFeatures(resolved, group, features);
      }
    }
    return List<JsFeatures>.unmodifiable(resolved);
  }

  void _appendFeatures(
    List<JsFeatures> resolved,
    JsUiCapabilityGroup group,
    JsFeatures features,
  ) {
    final conflicts = <int>{
      for (var i = 0; i < resolved.length; i++)
        if (_featuresConflict(resolved[i], features)) i,
    };
    if (conflicts.isEmpty) {
      resolved.add(features);
      return;
    }
    switch (conflictPolicy) {
      case JsUiCapabilityConflictPolicy.reject:
        throw StateError(
          'quickjs_ui host capability conflict for features "${features.name}"',
        );
      case JsUiCapabilityConflictPolicy.replace:
        for (final index in conflicts.toList().reversed) {
          resolved.removeAt(index);
        }
        resolved.add(features);
      case JsUiCapabilityConflictPolicy.namespace:
        resolved.add(_namespaceFeatures(group, features, resolved.length));
    }
  }
}

void _validateMethodDeclarations(JsUiCapabilityGroup group) {
  final hostMethodNames = <String>{
    for (final features in group.features)
      for (final method in features.methods) method.name,
  };
  final declaredHostMethodNames = <String>{};

  for (final method in group.methods) {
    if (method.name.trim().isEmpty) {
      throw StateError(
        'quickjs_ui capability group "${group.name}" declares an empty method name',
      );
    }
    _validateStructuredValue(method.inputSchema, 'inputSchema', method.name);
    _validateStructuredValue(method.outputSchema, 'outputSchema', method.name);

    final hostMethodName = method.hostMethodName;
    if (hostMethodName == null) {
      continue;
    }
    if (hostMethodName.trim().isEmpty) {
      throw StateError(
        'quickjs_ui capability method "${method.name}" declares an empty hostMethodName',
      );
    }
    if (!hostMethodNames.contains(hostMethodName)) {
      throw StateError(
        'quickjs_ui capability method "${method.name}" references unknown host method "$hostMethodName"',
      );
    }
    declaredHostMethodNames.add(hostMethodName);
  }

  final missing = hostMethodNames.difference(declaredHostMethodNames);
  if (missing.isNotEmpty) {
    throw StateError(
      'quickjs_ui capability group "${group.name}" exposes host methods without declarations: ${missing.join(', ')}',
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

List<JsUiHostMethodDeclaration> _systemMethodDeclarations(
  JsUiHostCapabilityOptions options,
) {
  final methods = <JsUiHostMethodDeclaration>[];

  void method(
    JsUiHostCapability capability,
    String name, {
    String? hostMethodName,
    Map<String, Object?> inputSchema = const <String, Object?>{},
    Map<String, Object?> outputSchema = const <String, Object?>{},
  }) {
    if (!options.isEnabled(capability)) {
      return;
    }
    methods.add(
      JsUiHostMethodDeclaration(
        name: name,
        hostMethodName: hostMethodName,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
      ),
    );
  }

  method(
    JsUiHostCapability.toast,
    'jsUiHost.toast',
    hostMethodName: 'quickjs_ui.host.toast',
    inputSchema: _objectSchema(
      <String, Object?>{'message': _stringSchema(), 'options': _objectSchema()},
      const <String>['message'],
    ),
    outputSchema: _objectSchema(),
  );
  method(
    JsUiHostCapability.confirm,
    'jsUiHost.confirm',
    hostMethodName: 'quickjs_ui.host.confirm',
    inputSchema: _objectSchema(
      <String, Object?>{'message': _stringSchema(), 'options': _objectSchema()},
      const <String>['message'],
    ),
    outputSchema: _boolSchema(),
  );
  method(
    JsUiHostCapability.navigation,
    'jsUiHost.navigationIntent',
    hostMethodName: 'quickjs_ui.host.navigation',
    inputSchema: _objectSchema(<String, Object?>{'intent': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.dialog,
    'jsUiHost.dialog',
    hostMethodName: 'quickjs_ui.host.dialog',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.snackbar,
    'jsUiHost.snackbar',
    hostMethodName: 'quickjs_ui.host.snackbar',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.bottomSheet,
    'jsUiHost.bottomSheet',
    hostMethodName: 'quickjs_ui.host.bottomSheet',
    inputSchema: _objectSchema(<String, Object?>{'payload': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.clipboard,
    'jsUiHost.clipboard.readText',
    hostMethodName: 'quickjs_ui.host.clipboard.readText',
    outputSchema: <String, Object?>{
      'oneOf': <Object?>[_stringSchema(), _nullSchema()],
    },
  );
  method(
    JsUiHostCapability.clipboard,
    'jsUiHost.clipboard.writeText',
    hostMethodName: 'quickjs_ui.host.clipboard.writeText',
    inputSchema: _objectSchema(<String, Object?>{'text': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.storage,
    'jsUiHost.storage.getItem',
    hostMethodName: 'quickjs_ui.host.storage.getItem',
    inputSchema: _objectSchema(<String, Object?>{'key': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.storage,
    'jsUiHost.storage.setItem',
    hostMethodName: 'quickjs_ui.host.storage.setItem',
    inputSchema: _objectSchema(
      <String, Object?>{'key': _stringSchema(), 'value': _anySchema()},
      const <String>['key'],
    ),
    outputSchema: _boolSchema(),
  );
  method(
    JsUiHostCapability.storage,
    'jsUiHost.storage.removeItem',
    hostMethodName: 'quickjs_ui.host.storage.removeItem',
    inputSchema: _objectSchema(<String, Object?>{'key': _stringSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.network,
    'jsUiHost.network',
    hostMethodName: 'quickjs_ui.host.network',
    inputSchema: _objectSchema(<String, Object?>{'request': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.fileSystem,
    'jsUiHost.fileSystem',
    hostMethodName: 'quickjs_ui.host.fileSystem',
    inputSchema: _objectSchema(<String, Object?>{'operation': _objectSchema()}),
    outputSchema: _anySchema(),
  );
  method(
    JsUiHostCapability.nativeCall,
    'jsUiHost.nativeCall',
    hostMethodName: 'quickjs_ui.host.nativeCall',
    inputSchema: _objectSchema(
      <String, Object?>{'method': _stringSchema(), 'payload': _anySchema()},
      const <String>['method'],
    ),
    outputSchema: _anySchema(),
  );
  return List<JsUiHostMethodDeclaration>.unmodifiable(methods);
}

JsFeatures _buildSystemFeatures({
  required String name,
  required JsUiHostCapabilityOptions options,
  required JsUiHostApiHandlers handlers,
  required Map<String, Object?> storage,
}) {
  final methods = <JsHostMethod>[];
  final apiEntries = <String>[];

  void method(
    JsUiHostCapability capability,
    String name,
    JsHostMethodCallback callback,
  ) {
    if (!options.isEnabled(capability)) {
      return;
    }
    methods.add(
      JsHostMethod(
        name: name,
        debugName: 'quickjs_ui host ${capability.name}',
        callback: callback,
      ),
    );
  }

  method(JsUiHostCapability.toast, 'quickjs_ui.host.toast', (args, _) {
    final message = _stringArg(args, 0, 'toast message');
    final options = _mapArg(args, 1);
    return handlers.onToast?.call(message, options) ??
        <String, Object?>{'shown': true, 'message': message};
  });
  if (options.isEnabled(JsUiHostCapability.toast)) {
    apiEntries.add(
      'toast(message, options = {}) { return methods[${jsonEncode('quickjs_ui.host.toast')}](message, options); }',
    );
  }

  method(JsUiHostCapability.confirm, 'quickjs_ui.host.confirm', (args, _) {
    final message = _stringArg(args, 0, 'confirm message');
    final options = _mapArg(args, 1);
    return handlers.onConfirm?.call(message, options) ?? false;
  });
  if (options.isEnabled(JsUiHostCapability.confirm)) {
    apiEntries.add(
      'confirm(message, options = {}) { return methods[${jsonEncode('quickjs_ui.host.confirm')}](message, options); }',
    );
  }

  method(JsUiHostCapability.navigation, 'quickjs_ui.host.navigation', (
    args,
    _,
  ) {
    final intent = _mapArg(args, 0);
    return _requireHandler(
      handlers.onNavigationIntent,
      'navigation',
    ).call(intent);
  });
  if (options.isEnabled(JsUiHostCapability.navigation)) {
    apiEntries.add(
      'navigationIntent(intent) { return methods[${jsonEncode('quickjs_ui.host.navigation')}](intent); }',
    );
  }

  method(JsUiHostCapability.dialog, 'quickjs_ui.host.dialog', (args, _) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onDialog, 'dialog').call(payload);
  });
  if (options.isEnabled(JsUiHostCapability.dialog)) {
    apiEntries.add(
      'dialog(payload) { return methods[${jsonEncode('quickjs_ui.host.dialog')}](payload); }',
    );
  }

  method(JsUiHostCapability.snackbar, 'quickjs_ui.host.snackbar', (args, _) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onSnackbar, 'snackbar').call(payload);
  });
  if (options.isEnabled(JsUiHostCapability.snackbar)) {
    apiEntries.add(
      'snackbar(payload) { return methods[${jsonEncode('quickjs_ui.host.snackbar')}](payload); }',
    );
  }

  method(JsUiHostCapability.bottomSheet, 'quickjs_ui.host.bottomSheet', (
    args,
    _,
  ) {
    final payload = _mapArg(args, 0);
    return _requireHandler(handlers.onBottomSheet, 'bottomSheet').call(payload);
  });
  if (options.isEnabled(JsUiHostCapability.bottomSheet)) {
    apiEntries.add(
      'bottomSheet(payload) { return methods[${jsonEncode('quickjs_ui.host.bottomSheet')}](payload); }',
    );
  }

  if (options.isEnabled(JsUiHostCapability.clipboard)) {
    methods
      ..add(
        JsHostMethod(
          name: 'quickjs_ui.host.clipboard.readText',
          debugName: 'quickjs_ui host clipboard readText',
          callback: (_, _) {
            return handlers.onClipboardReadText?.call();
          },
        ),
      )
      ..add(
        JsHostMethod(
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
  readText() { return methods[${jsonEncode('quickjs_ui.host.clipboard.readText')}](); },
  writeText(text) { return methods[${jsonEncode('quickjs_ui.host.clipboard.writeText')}](text); }
}''');
  }

  if (options.isEnabled(JsUiHostCapability.storage)) {
    methods
      ..add(
        JsHostMethod(
          name: 'quickjs_ui.host.storage.getItem',
          debugName: 'quickjs_ui host storage getItem',
          callback: (args, _) {
            return storage[_stringArg(args, 0, 'storage key')];
          },
        ),
      )
      ..add(
        JsHostMethod(
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
        JsHostMethod(
          name: 'quickjs_ui.host.storage.removeItem',
          debugName: 'quickjs_ui host storage removeItem',
          callback: (args, _) {
            return storage.remove(_stringArg(args, 0, 'storage key'));
          },
        ),
      );
    apiEntries.add('''
storage: {
  getItem(key) { return methods[${jsonEncode('quickjs_ui.host.storage.getItem')}](key); },
  setItem(key, value) { return methods[${jsonEncode('quickjs_ui.host.storage.setItem')}](key, value); },
  removeItem(key) { return methods[${jsonEncode('quickjs_ui.host.storage.removeItem')}](key); }
}''');
  }

  method(JsUiHostCapability.network, 'quickjs_ui.host.network', (args, _) {
    final request = _mapArg(args, 0);
    return _requireHandler(handlers.onNetworkRequest, 'network').call(request);
  });
  if (options.isEnabled(JsUiHostCapability.network)) {
    apiEntries.add(
      'network(request) { return methods[${jsonEncode('quickjs_ui.host.network')}](request); }',
    );
  }

  method(JsUiHostCapability.fileSystem, 'quickjs_ui.host.fileSystem', (
    args,
    _,
  ) {
    final operation = _mapArg(args, 0);
    return _requireHandler(
      handlers.onFileSystemOperation,
      'fileSystem',
    ).call(operation);
  });
  if (options.isEnabled(JsUiHostCapability.fileSystem)) {
    apiEntries.add(
      'fileSystem(operation) { return methods[${jsonEncode('quickjs_ui.host.fileSystem')}](operation); }',
    );
  }

  method(JsUiHostCapability.nativeCall, 'quickjs_ui.host.nativeCall', (
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
  if (options.isEnabled(JsUiHostCapability.nativeCall)) {
    apiEntries.add(
      'nativeCall(method, payload) { return methods[${jsonEncode('quickjs_ui.host.nativeCall')}](method, payload); }',
    );
  }

  return JsFeatures(
    name: name,
    methods: methods,
    scripts: <JsScript>[
      JsScript(
        name: '$name:globals.js',
        globals: const <String>['jsUiHost'],
        source:
            '''
(() => {
  const methods = globalThis.__jsHostMethods;
  globalThis.jsUiHost = Object.freeze({
    ${apiEntries.join(',\n    ')}
  });
})();
''',
      ),
    ],
  );
}

bool _featuresConflict(JsFeatures left, JsFeatures right) {
  return left.name == right.name ||
      _intersects(
        left.methods.map((method) => method.name),
        right.methods.map((method) => method.name),
      ) ||
      _intersects(
        left.scripts.expand((script) => script.globals),
        right.scripts.expand((script) => script.globals),
      ) ||
      _intersects(
        left.modules.map((module) => module.name),
        right.modules.map((module) => module.name),
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

JsFeatures _namespaceFeatures(
  JsUiCapabilityGroup group,
  JsFeatures features,
  int index,
) {
  final namespace = group.namespace ?? group.name;
  return JsFeatures(
    name: '$namespace:${features.name}:$index',
    browserGlobals: features.browserGlobals,
    scripts: features.scripts,
    modules: features.modules,
    methods: features.methods,
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
