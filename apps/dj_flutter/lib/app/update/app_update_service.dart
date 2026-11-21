import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_runtime_config.dart';
import '../../shared/platform_utils.dart' as platform_utils;

enum AppUpdateStatus {
  idle,
  checking,
  updateAvailable,
  downloading,
  downloadComplete,
  installing,
  error,
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.fileSize,
  });

  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final int fileSize;
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateStatus _status = AppUpdateStatus.idle;
  AppUpdateInfo? _updateInfo;
  double _downloadProgress = 0;
  String? _errorMessage;

  AppUpdateStatus get status => _status;
  AppUpdateInfo? get updateInfo => _updateInfo;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  bool get hasUpdate =>
      _status == AppUpdateStatus.updateAvailable ||
      _status == AppUpdateStatus.downloading ||
      _status == AppUpdateStatus.downloadComplete;

  static const String _checkUrl = 'https://www.jiaofangsi.top/api/update/check';

  Future<void> checkForUpdate() async {
    if (_status == AppUpdateStatus.checking ||
        _status == AppUpdateStatus.downloading ||
        _status == AppUpdateStatus.installing) {
      return;
    }

    _status = AppUpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final String platform = Platform.isWindows ? 'windows' : 'macos';
      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final HttpClientRequest request = await client.getUrl(
        Uri.parse(
          '$_checkUrl?platform=$platform&version=${Uri.encodeComponent(appVersionLabel)}',
        ),
      );
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        _status = AppUpdateStatus.error;
        _errorMessage = '检查更新失败 (${response.statusCode})';
        notifyListeners();
        return;
      }

      final Map<String, Object?> data =
          jsonDecode(body) as Map<String, Object?>;
      final bool hasUpdate = data['has_update'] as bool? ?? false;

      if (hasUpdate) {
        _updateInfo = AppUpdateInfo(
          version: data['version'] as String? ?? '',
          downloadUrl: data['download_url'] as String? ?? '',
          releaseNotes: data['release_notes'] as String? ?? '',
          fileSize: data['file_size'] as int? ?? 0,
        );
        _status = AppUpdateStatus.updateAvailable;
      } else {
        _status = AppUpdateStatus.idle;
      }
    } catch (e) {
      _status = AppUpdateStatus.error;
      _errorMessage = '检查更新失败，请稍后重试。';
    }
    notifyListeners();
  }

  Future<void> downloadUpdate() async {
    if (_updateInfo == null) return;

    _status = AppUpdateStatus.downloading;
    _downloadProgress = 0;
    notifyListeners();

    try {
      final Directory tempDir = Directory.systemTemp;
      final String archivePath = p.join(tempDir.path, 'dj_flutter_update.zip');
      final File archiveFile = File(archivePath);

      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final HttpClientRequest request = await client.getUrl(
        Uri.parse(_updateInfo!.downloadUrl),
      );
      final HttpClientResponse response = await request.close();

      final int totalBytes = response.contentLength > 0
          ? response.contentLength
          : _updateInfo!.fileSize;
      int receivedBytes = 0;

      final IOSink sink = archiveFile.openWrite();
      await for (final List<int> chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = receivedBytes / totalBytes;
          notifyListeners();
        }
      }
      await sink.close();
      client.close();

      _status = AppUpdateStatus.downloadComplete;
      _downloadProgress = 1.0;
    } catch (e) {
      _status = AppUpdateStatus.error;
      _errorMessage = '下载更新失败，请检查网络后重试。';
    }
    notifyListeners();
  }

  Future<void> installAndRestart() async {
    _status = AppUpdateStatus.installing;
    notifyListeners();

    try {
      final String appPath = Platform.resolvedExecutable;
      final String archivePath = p.join(
        Directory.systemTemp.path,
        'dj_flutter_update.zip',
      );

      if (Platform.isWindows) {
        final String appDir = File(appPath).parent.path;
        final String updaterScript = _resolveUpdaterScript(appPath);
        final int currentPid = pid;

        if (!File(updaterScript).existsSync()) {
          _status = AppUpdateStatus.error;
          _errorMessage = '更新安装失败: 未找到更新脚本';
          notifyListeners();
          return;
        }
        if (!File(archivePath).existsSync()) {
          _status = AppUpdateStatus.error;
          _errorMessage = '更新安装失败: 更新包不存在';
          notifyListeners();
          return;
        }

        final ProcessResult result = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          updaterScript,
          '-ArchivePath',
          archivePath,
          '-TargetDir',
          appDir,
          '-AppExe',
          appPath,
          '-WaitPid',
          currentPid.toString(),
        ]);

        if (result.exitCode != 0) {
          _status = AppUpdateStatus.error;
          _errorMessage = '更新安装失败，请关闭占用程序后重试。';
          notifyListeners();
          return;
        }
      } else {
        final String appDir = File(appPath).parent.parent.parent.parent.path;
        final String backupDir =
            '$appDir.backup_${DateTime.now().millisecondsSinceEpoch}';

        await Process.run('mv', [appDir, backupDir], runInShell: true);
        await Process.run('unzip', [
          '-o',
          archivePath,
          '-d',
          p.dirname(appDir),
        ], runInShell: true);

        await Process.run('rm', ['-rf', backupDir], runInShell: true);

        await Process.run(appPath, [], runInShell: true);
      }
    } catch (e) {
      _status = AppUpdateStatus.error;
      _errorMessage = '安装更新失败，请稍后重试。';
      notifyListeners();
    }
  }

  static String _resolveUpdaterScript(String appPath) {
    final String appDir = File(appPath).parent.path;

    final File releaseUpdater = File(
      p.join(appDir, 'runtime', 'updater', 'windows_updater.ps1'),
    );
    if (releaseUpdater.existsSync()) {
      return releaseUpdater.path;
    }

    final String projectRoot = _resolveProjectRoot(appPath);
    final File devUpdater = File(
      p.join(projectRoot, 'runtime', 'updater', 'windows_updater.ps1'),
    );
    if (devUpdater.existsSync()) {
      return devUpdater.path;
    }

    return p.join(appDir, 'runtime', 'updater', 'windows_updater.ps1');
  }

  static String _resolveProjectRoot(String appPath) {
    return platform_utils
        .resolveProjectRoot(resolvedExecutablePath: appPath)
        .path;
  }
}
