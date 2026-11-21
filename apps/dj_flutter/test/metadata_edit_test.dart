import 'dart:io';

import 'package:dj_flutter/features/metadata_edit/presentation/controllers/metadata_edit_controller.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/metadata_edit_entry_page.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/models/metadata_edit_models.dart';
import 'package:dj_flutter/shared/platform_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeMetadataEditBridge implements MetadataEditTaskBridge {
  Map<String, Object?>? lastLockedConfig;

  @override
  Future<void> close() async {}

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<List<String>> loadTargets(List<String> filePaths) async => filePaths;

  @override
  Future<void> lockConfig(Map<String, Object?> config) async {
    lastLockedConfig = Map<String, Object?>.from(config);
  }

  @override
  Future<MetadataEditTaskSnapshot> startCoverInjectionTask() async {
    return const MetadataEditTaskSnapshot(
      taskId: 'cover_001',
      taskType: MetadataEditTaskType.coverInjection,
      status: MetadataEditStatus.running,
      progress: 0.1,
      hintText: 'running',
      fileCount: 1,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<MetadataEditTaskSnapshot> startFilenameInjectionTask() async {
    return const MetadataEditTaskSnapshot(
      taskId: 'filename_001',
      taskType: MetadataEditTaskType.filenameInjection,
      status: MetadataEditStatus.running,
      progress: 0.1,
      hintText: 'running',
      fileCount: 1,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<MetadataEditTaskSnapshot> stopTask(String taskId) async {
    return MetadataEditTaskSnapshot(
      taskId: taskId,
      taskType: MetadataEditTaskType.filenameInjection,
      status: MetadataEditStatus.cancelled,
      progress: 0.3,
      hintText: 'stopped',
      fileCount: 1,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<List<MetadataEditTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
    return <MetadataEditTaskEvent>[];
  }

  @override
  Future<MetadataEditResult> fetchMetadataEditResult(String taskId) async {
    return MetadataEditResult(
      taskId: taskId,
      status: MetadataEditStatus.success,
      results: const <MetadataEditResultItem>[],
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
      logLines: const <String>[],
    );
  }

  @override
  Future<List<String>> loadTemplates() async => <String>['remix版', '私改版'];

  @override
  Future<List<String>> saveTemplate(String template) async => <String>[
    'remix版',
    template,
  ];

  @override
  Future<List<String>> deleteTemplate(String template) async => <String>[
    'remix版',
  ];
}

void main() {
  test('开发态路径解析优先命中项目内 ff 目录', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'metadata_dev_paths_',
    );
    addTearDown(() => root.delete(recursive: true));
    Directory(
      p.join(root.path, 'runtime', 'dj_runtime_py'),
    ).createSync(recursive: true);
    final String ffmpegExt = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final String ffprobeExt = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    File(p.join(root.path, 'ff', ffmpegExt)).createSync(recursive: true);
    File(p.join(root.path, 'ff', ffprobeExt)).createSync(recursive: true);

    final Directory resolved = MetadataEditEnvironmentPaths.resolveProjectRoot(
      currentDirectory: root,
      resolvedExecutablePath: p.join(
        root.path,
        'apps',
        'dj_flutter',
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        'dj_flutter.exe',
      ),
    );
    expect(resolved.path, root.path);
    expect(
      MetadataEditEnvironmentPaths.resolveFfBinaryPath(
        root,
        'ffmpeg',
        resolvedExecutablePath: p.join(root.path, 'bin', 'dj_flutter'),
      ),
      p.join(root.path, 'ff', ffmpegExt),
    );
  });

  test('macOS 打包态路径解析命中 app Resources/ff', () async {
    if (Platform.isWindows) {
      markTestSkipped('此测试仅适用于 macOS');
      return;
    }
    final Directory root = await Directory.systemTemp.createTemp(
      'metadata_app_paths_',
    );
    addTearDown(() => root.delete(recursive: true));
    Directory('${root.path}/runtime/dj_runtime_py').createSync(recursive: true);
    File(
      '${root.path}/build/macos/Build/Products/Debug/dj_flutter.app/Contents/Resources/ff/ffprobe',
    ).createSync(recursive: true);

    final String resolved =
        MetadataEditEnvironmentPaths.resolveFfBinaryPath(
          root,
          'ffprobe',
          resolvedExecutablePath:
              '${root.path}/build/macos/Build/Products/Debug/dj_flutter.app/Contents/MacOS/dj_flutter',
        ) ??
        '';
    expect(resolved, contains('.app/Contents/Resources/ff/ffprobe'));
  });

  test('cover 配置锁定时会下发 ffmpeg_path 与 ffprobe_path', () async {
    final _FakeMetadataEditBridge bridge = _FakeMetadataEditBridge();
    final MetadataEditController controller = MetadataEditController(
      bridge: bridge,
      ffmpegPath: '/repo/ff/ffmpeg',
      ffprobePath: '/repo/ff/ffprobe',
    );
    addTearDown(controller.close);
    await controller.initialize();
    controller.updateCoverImagePath('/tmp/cover.png');
    await controller.loadTargets(MetadataEditPanelKind.cover, <String>[
      '/tmp/a.mp3',
    ]);

    await controller.lockPanelConfig(MetadataEditPanelKind.cover);

    expect(bridge.lastLockedConfig?['operation'], 'cover_injection');
    expect(bridge.lastLockedConfig?['ffmpeg_path'], '/repo/ff/ffmpeg');
    expect(bridge.lastLockedConfig?['ffprobe_path'], '/repo/ff/ffprobe');
    expect(bridge.lastLockedConfig?['cover_image_path'], '/tmp/cover.png');
  });

  test('filename 配置锁定时会下发 ffprobe_path', () async {
    final _FakeMetadataEditBridge bridge = _FakeMetadataEditBridge();
    final MetadataEditController controller = MetadataEditController(
      bridge: bridge,
      ffmpegPath: '/repo/ff/ffmpeg',
      ffprobePath: '/repo/ff/ffprobe',
    );
    addTearDown(controller.close);
    await controller.initialize();
    controller.updateAppendText('remix版');
    await controller.loadTargets(MetadataEditPanelKind.filename, <String>[
      '/tmp/a.mp3',
    ]);

    await controller.lockPanelConfig(MetadataEditPanelKind.filename);

    expect(bridge.lastLockedConfig?['operation'], 'filename_injection');
    expect(bridge.lastLockedConfig?['append_text'], 'remix版');
    expect(bridge.lastLockedConfig?['ffmpeg_path'], '/repo/ff/ffmpeg');
    expect(bridge.lastLockedConfig?['ffprobe_path'], '/repo/ff/ffprobe');
  });

  group('Windows FFmpeg 路径解析', () {
    test('Windows 开发态路径解析命中项目 ff 目录', () async {
      if (!Platform.isWindows) {
        markTestSkipped('此测试仅适用于 Windows');
        return;
      }
      final Directory root = await Directory.systemTemp.createTemp(
        'metadata_win_dev_',
      );
      addTearDown(() => root.delete(recursive: true));
      Directory(
        p.join(root.path, 'runtime', 'dj_runtime_py'),
      ).createSync(recursive: true);
      File(p.join(root.path, 'ff', 'ffmpeg.exe')).createSync(recursive: true);
      File(p.join(root.path, 'ff', 'ffprobe.exe')).createSync(recursive: true);

      final String? ffmpegPath = resolveFfBinaryPath(root, 'ffmpeg');
      expect(ffmpegPath, p.join(root.path, 'ff', 'ffmpeg.exe'));
    });

    test('Windows 发布态路径解析命中 app 目录内 ff', () async {
      if (!Platform.isWindows) {
        markTestSkipped('此测试仅适用于 Windows');
        return;
      }
      final Directory root = await Directory.systemTemp.createTemp(
        'metadata_win_release_',
      );
      addTearDown(() => root.delete(recursive: true));
      Directory(
        p.join(root.path, 'runtime', 'dj_runtime_py'),
      ).createSync(recursive: true);

      final Directory releaseDir = Directory(
        p.join(
          root.path,
          'apps',
          'dj_flutter',
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
        ),
      );
      releaseDir.createSync(recursive: true);
      File(p.join(releaseDir.path, 'dj_flutter.exe')).createSync();
      File(
        p.join(releaseDir.path, 'ff', 'ffprobe.exe'),
      ).createSync(recursive: true);

      final String? ffprobePath = resolveFfBinaryPath(root, 'ffprobe');
      expect(ffprobePath, isNotNull);
      expect(ffprobePath!, contains('ff'));
      expect(ffprobePath, contains('ffprobe.exe'));
    });

    test('Windows 发布态路径解析优先命中发布目录 ff', () async {
      if (!Platform.isWindows) {
        markTestSkipped('此测试仅适用于 Windows');
        return;
      }
      final Directory root = await Directory.systemTemp.createTemp(
        'metadata_win_release_priority_',
      );
      addTearDown(() => root.delete(recursive: true));

      final Directory releaseDir = Directory(
        p.join(
          root.path,
          'apps',
          'dj_flutter',
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
        ),
      );
      releaseDir.createSync(recursive: true);
      File(p.join(releaseDir.path, 'dj_flutter.exe')).createSync();
      File(
        p.join(releaseDir.path, 'ff', 'ffmpeg.exe'),
      ).createSync(recursive: true);
      File(
        p.join(releaseDir.path, 'ff', 'ffprobe.exe'),
      ).createSync(recursive: true);

      final String? ffmpegPath = resolveFfBinaryPath(root, 'ffmpeg');
      expect(ffmpegPath, p.join(releaseDir.path, 'ff', 'ffmpeg.exe'));
    });
  });
}
