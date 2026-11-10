import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Override path to `liboffice_oxide` (`.dylib` / `.so` / `.dll`).
const String officeOxideLibEnv = 'OFFICE_OXIDE_LIB';

/// Opens the Office Oxide shared library for the current platform.
///
/// Resolution order:
/// 1. [officeOxideLibEnv]
/// 2. iOS: `OfficeOxide.framework/OfficeOxide`, then [DynamicLibrary.process]
/// 3. Android: `liboffice_oxide.so` from jniLibs
/// 4. Bundled package `native/<os>/<arch>/lib/…` (desktop)
DynamicLibrary openOfficeOxideLibrary() {
  final override = Platform.environment[officeOxideLibEnv];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }

  if (Platform.isIOS) {
    for (final name in const [
      'OfficeOxide.framework/OfficeOxide',
      'office_oxide',
    ]) {
      try {
        final lib = DynamicLibrary.open(name);
        if (lib.providesSymbol('office_oxide_version')) return lib;
      } on Object {
        // try next
      }
    }
    final process = DynamicLibrary.process();
    if (process.providesSymbol('office_oxide_version')) return process;
    throw StateError(
      'office_oxide symbols not found on iOS. '
      'Rebuild after running tool/build_ios_oxide.sh and pod install '
      '(OfficeOxide.xcframework must be embedded).',
    );
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('liboffice_oxide.so');
  }

  final path = resolveBundledLibraryPath();
  if (!File(path).existsSync()) {
    throw StateError(
      'office_oxide native library not found at:\n  $path\n'
      'Set $officeOxideLibEnv or ship the matching prebuild under native/.',
    );
  }
  return DynamicLibrary.open(path);
}

/// Absolute path to the checked-in desktop prebuild (macOS/Linux/Windows).
String resolveBundledLibraryPath() {
  final root = _packageRoot();
  if (Platform.isMacOS) {
    return p.join(
      root,
      'native',
      'macos',
      _macosArch(),
      'lib',
      'liboffice_oxide.dylib',
    );
  }
  if (Platform.isLinux) {
    return p.join(
      root,
      'native',
      'linux',
      _linuxArch(),
      'lib',
      'liboffice_oxide.so',
    );
  }
  if (Platform.isWindows) {
    return p.join(
      root,
      'native',
      'windows',
      _windowsArch(),
      'lib',
      'office_oxide.dll',
    );
  }
  throw UnsupportedError(
    'office_viewer_engine_convert: unsupported OS ${Platform.operatingSystem}',
  );
}

String _packageRoot() {
  // Prefer package_config resolution so tests/worktrees resolve correctly.
  final fromConfig = _rootFromPackageConfig();
  if (fromConfig != null) return fromConfig;

  var dir = Directory.current;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: office_viewer_engine_convert')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'office_viewer_engine_convert: cannot locate package root',
  );
}

String? _rootFromPackageConfig() {
  try {
    final configPath = Platform.packageConfig;
    final candidates = <File>[
      if (configPath != null) File(Uri.parse(configPath).toFilePath()),
      File(p.join(Directory.current.path, '.dart_tool', 'package_config.json')),
    ];
    for (final config in candidates) {
      if (!config.existsSync()) continue;
      final text = config.readAsStringSync();
      const marker = '"name":"office_viewer_engine_convert"';
      const alt = '"name": "office_viewer_engine_convert"';
      final idx = text.contains(marker)
          ? text.indexOf(marker)
          : text.indexOf(alt);
      if (idx < 0) continue;
      const rootKey = '"rootUri"';
      final slice = text.substring(idx, (idx + 400).clamp(0, text.length));
      final rootIdx = slice.indexOf(rootKey);
      if (rootIdx < 0) continue;
      final start = slice.indexOf('"', rootIdx + rootKey.length + 1) + 1;
      final end = slice.indexOf('"', start);
      if (start <= 0 || end <= start) continue;
      final rootUri = slice.substring(start, end);
      final configDir = p.dirname(config.path);
      final root = rootUri.startsWith('file:')
          ? p.fromUri(Uri.parse(rootUri))
          : p.normalize(p.join(configDir, rootUri));
      return root;
    }
  } on Object {
    return null;
  }
  return null;
}

String _macosArch() =>
    Platform.version.contains('arm64') ? 'arm64' : 'x64';

String _linuxArch() {
  if (Platform.version.contains('arm64') ||
      Platform.version.contains('aarch64')) {
    return 'arm64';
  }
  return 'x64';
}

String _windowsArch() =>
    Platform.version.contains('arm64') ? 'arm64' : 'x64';
