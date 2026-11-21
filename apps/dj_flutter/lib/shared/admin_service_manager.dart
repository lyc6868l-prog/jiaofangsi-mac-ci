import 'dart:io';

import 'package:path/path.dart' as p;

import 'platform_utils.dart' as platform_utils;

class AdminServiceManager {
  static const String _pipeName = 'DJAdminService';
  static bool _serviceStarted = false;
  static bool _startupAttempted = false;

  static Future<bool> isServiceRunning() async {
    try {
      return await _pingService();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startService() async {
    if (_serviceStarted) {
      return true;
    }

    try {
      final String? servicePath = _findServiceScript();
      if (servicePath == null) {
        stderr.writeln('AdminServiceManager: 服务脚本未找到');
        return false;
      }

      final String? pythonExe = _findPythonExecutable();
      if (pythonExe == null) {
        stderr.writeln('AdminServiceManager: Python 未找到');
        return false;
      }

      final String workingDirectory = File(servicePath).parent.path;
      final String psCommand =
          '''
Start-Process -FilePath '${_escapePowerShell(pythonExe)}' -ArgumentList @('${_escapePowerShell(servicePath)}') -WorkingDirectory '${_escapePowerShell(workingDirectory)}' -Verb RunAs -WindowStyle Hidden
''';

      final ProcessResult result = await Process.run('powershell', <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psCommand.trim(),
      ]);
      if (result.exitCode != 0) {
        stderr.writeln(
          'AdminServiceManager: PowerShell 启动失败: ${result.stderr}',
        );
        return false;
      }

      for (int i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final bool running = await isServiceRunning();
        if (running) {
          _serviceStarted = true;
          return true;
        }
      }

      stderr.writeln('AdminServiceManager: 服务启动超时');
      return false;
    } catch (e) {
      stderr.writeln('AdminServiceManager: 启动异常: $e');
      return false;
    }
  }

  static String? _findPythonExecutable() {
    final Directory projectRoot = platform_utils.resolveProjectRoot();
    final String candidate = platform_utils.resolvePythonExecutable(
      projectRoot,
    );
    if (File(candidate).existsSync()) {
      return candidate;
    }
    return null;
  }

  static String? _findServiceScript() {
    final Directory projectRoot = platform_utils.resolveProjectRoot();
    final List<String> candidates = <String>[
      p.join(
        projectRoot.path,
        'runtime',
        'dj_admin_service',
        'dj_admin_service.py',
      ),
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'runtime',
        'dj_admin_service',
        'dj_admin_service.py',
      ),
    ];

    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) {
        return File(candidate).absolute.path;
      }
    }
    return null;
  }

  static Future<void> ensureServiceRunning() async {
    if (_startupAttempted) {
      return;
    }
    _startupAttempted = true;

    final bool running = await isServiceRunning();
    if (!running) {
      await startService();
    }
  }

  static Future<bool> _pingService() async {
    final String escapedPipeName = _escapePowerShell(_pipeName);
    final String psCommand =
        """
\$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', '$escapedPipeName', [System.IO.Pipes.PipeDirection]::InOut)
try {
  \$pipe.Connect(1500)
  \$encoding = New-Object System.Text.UTF8Encoding(\$false)
  \$writer = New-Object System.IO.StreamWriter(\$pipe, \$encoding, 4096, \$true)
  \$writer.AutoFlush = \$true
  \$reader = New-Object System.IO.StreamReader(\$pipe, \$encoding, \$false, 4096, \$true)
  \$writer.Write('{"action":"ping"}')
  \$buffer = New-Object char[] 4096
  \$read = \$reader.Read(\$buffer, 0, \$buffer.Length)
  if (\$read -gt 0) {
    \$response = -join \$buffer[0..(\$read - 1)]
    if (\$response -match '"success"\s*:\s*true') { exit 0 }
  }
  exit 1
} catch {
  exit 1
} finally {
  \$pipe.Dispose()
}
""";

    final ProcessResult result = await Process.run('powershell', <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      psCommand,
    ]);
    return result.exitCode == 0;
  }

  static String _escapePowerShell(String value) {
    return value.replaceAll("'", "''");
  }
}
