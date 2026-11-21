import 'dart:io';

import 'package:path/path.dart' as p;

const String _appName = 'JiaoFangSiDJ';

Directory resolveProjectRoot({
  Directory? currentDirectory,
  String? resolvedExecutablePath,
}) {
  final Directory fallback = currentDirectory ?? Directory.current;
  final List<Directory> seeds = <Directory>[
    fallback,
    File(resolvedExecutablePath ?? Platform.resolvedExecutable).parent,
  ];
  final Set<String> visited = <String>{};
  Directory? repositoryCandidate;
  Directory? runtimeCandidate;

  for (final Directory seed in seeds) {
    if (!seed.existsSync()) {
      continue;
    }
    Directory current = seed.absolute;
    while (true) {
      final String normalizedPath = p.normalize(current.path);
      if (!visited.add(normalizedPath)) {
        break;
      }
      if (_hasPackagedRuntimeLayout(current)) {
        return current;
      }
      if (_hasRepositoryLayout(current)) {
        repositoryCandidate ??= current;
      } else if (_hasRuntimeLayout(current)) {
        runtimeCandidate ??= current;
      }
      final Directory parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
  }

  return repositoryCandidate ?? runtimeCandidate ?? fallback;
}

bool _hasRepositoryLayout(Directory directory) {
  return File(
        p.join(directory.path, 'apps', 'dj_flutter', 'pubspec.yaml'),
      ).existsSync() &&
      _hasRuntimeLayout(directory);
}

bool _hasRuntimeLayout(Directory directory) {
  return File(
    p.join(
      directory.path,
      'runtime',
      'dj_runtime_py',
      'dj_runtime_py',
      '__main__.py',
    ),
  ).existsSync();
}

bool _hasPackagedRuntimeLayout(Directory directory) {
  return File(
        p.join(directory.path, 'runtime', 'python_embed', 'python.exe'),
      ).existsSync() ||
      File(
        p.join(directory.path, 'runtime', 'nodejs', 'node.exe'),
      ).existsSync() ||
      File(
        p.join(directory.path, 'runtime', 'updater', 'windows_updater.ps1'),
      ).existsSync();
}

Directory resolveAppDataDirectory({String appName = _appName}) {
  if (Platform.isWindows) {
    final String? localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return Directory(p.join(localAppData, appName));
    }
  }
  if (Platform.isMacOS) {
    final String? home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, 'Library', 'Application Support', appName));
    }
  }
  final String? xdgDataHome = Platform.environment['XDG_DATA_HOME'];
  if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
    return Directory(p.join(xdgDataHome, appName));
  }
  final String? home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return Directory(p.join(home, '.local', 'share', appName));
  }
  return Directory(p.join(Directory.current.path, appName));
}

String resolvePythonExecutable(Directory projectRoot) {
  final String executableDirectory = File(
    Platform.resolvedExecutable,
  ).parent.path;
  if (Platform.isWindows) {
    final List<String> candidates = <String>[
      p.join(projectRoot.path, 'runtime', 'python_embed', 'python.exe'),
      p.join(executableDirectory, 'runtime', 'python_embed', 'python.exe'),
      p.join(projectRoot.path, '.venv', 'Scripts', 'python.exe'),
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return p.join(projectRoot.path, 'runtime', 'python_embed', 'python.exe');
  }

  final List<String> unixCandidates = <String>[
    p.join(projectRoot.path, '.venv', 'bin', 'python'),
    p.join(projectRoot.path, 'runtime', 'python_embed', 'bin', 'python3'),
  ];
  for (final String candidate in unixCandidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'python3';
}

String resolveNodeExecutable(Directory projectRoot) {
  final String executableDirectory = File(
    Platform.resolvedExecutable,
  ).parent.path;
  if (Platform.isWindows) {
    final List<String> candidates = <String>[
      p.join(projectRoot.path, 'runtime', 'nodejs', 'node.exe'),
      p.join(executableDirectory, 'runtime', 'nodejs', 'node.exe'),
      p.join(
        projectRoot.path,
        '.venv',
        'Lib',
        'site-packages',
        'nodejs_wheel',
        'node.exe',
      ),
      p.join(projectRoot.path, '.venv', 'Scripts', 'node.exe'),
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return p.join(projectRoot.path, 'runtime', 'nodejs', 'node.exe');
  }
  return 'node';
}

Future<void> openUrl(String url) async {
  final Uri uri = Uri.parse(url);
  if (Platform.isWindows) {
    await Process.run('rundll32', <String>[
      'url.dll,FileProtocolHandler',
      uri.toString(),
    ]);
  } else if (Platform.isMacOS) {
    await Process.run('open', <String>[uri.toString()]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', <String>[uri.toString()]);
  } else {
    throw UnsupportedError('不支持的平台');
  }
}

Future<void> openDirectory(String directory) async {
  final String command;
  final List<String> args;
  if (Platform.isWindows) {
    command = 'explorer';
    args = <String>[directory];
  } else if (Platform.isMacOS) {
    command = 'open';
    args = <String>[directory];
  } else if (Platform.isLinux) {
    command = 'xdg-open';
    args = <String>[directory];
  } else {
    throw UnsupportedError('不支持的平台');
  }
  final ProcessResult result = await Process.run(command, args);
  if (result.exitCode != 0) {
    throw Exception('打开目录失败，请检查目录是否存在后重试。');
  }
}

Directory resolveDesktopDirectory() {
  final List<String> candidates = <String>[];
  if (Platform.isWindows) {
    final String? userProfile = Platform.environment['USERPROFILE'];
    final String? oneDrive = Platform.environment['OneDrive'];
    if (userProfile != null && userProfile.isNotEmpty) {
      candidates.add(p.join(userProfile, 'Desktop'));
    }
    if (oneDrive != null && oneDrive.isNotEmpty) {
      candidates.add(p.join(oneDrive, 'Desktop'));
    }
  }
  final String? home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    candidates.add(p.join(home, 'Desktop'));
  }
  for (final String candidate in candidates) {
    final Directory directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }
  return Directory.current;
}

String sanitizeWindowsFileName(String value, {String fallback = '未命名'}) {
  final String sanitized = value
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}

String? resolveFfBinaryPath(Directory projectRoot, String executableName) {
  final String binaryName = Platform.isWindows
      ? '$executableName.exe'
      : executableName;
  final String executableDirectory = File(
    Platform.resolvedExecutable,
  ).parent.path;
  final List<String> candidates = <String>[
    p.join(projectRoot.path, 'ff', binaryName),
    p.join(executableDirectory, 'ff', binaryName),
  ];
  if (Platform.isMacOS) {
    candidates.addAll(<String>[
      p.join(
        projectRoot.path,
        'build',
        'macos',
        'Build',
        'Products',
        'Debug',
        'dj_flutter.app',
        'Contents',
        'Resources',
        'ff',
        executableName,
      ),
      p.join(
        projectRoot.path,
        'build',
        'macos',
        'Build',
        'Products',
        'Release',
        'dj_flutter.app',
        'Contents',
        'Resources',
        'ff',
        executableName,
      ),
      p.join(
        File(Platform.resolvedExecutable).parent.parent.path,
        'Resources',
        'ff',
        executableName,
      ),
    ]);
  } else if (Platform.isWindows) {
    candidates.addAll(<String>[
      p.join(
        projectRoot.path,
        'apps',
        'dj_flutter',
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
        'ff',
        binaryName,
      ),
      p.join(
        projectRoot.path,
        'apps',
        'dj_flutter',
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        'ff',
        binaryName,
      ),
    ]);
  }
  for (final String candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}
