import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dj_flutter/features/audio_transcode/presentation/audio_transcode_entry_page.dart';
import 'package:dj_flutter/features/audio_transcode/presentation/controllers/audio_transcode_controller.dart';
import 'package:dj_flutter/features/audio_transcode/presentation/models/audio_transcode_models.dart';

class _FakeAudioTranscodeTaskBridgeForDialog
    implements AudioTranscodeTaskBridge {
  @override
  Future<void> ensureStarted() async {}

  @override
  Future<List<String>> loadTargets(List<String> filePaths) async {
    return filePaths;
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) async {}

  @override
  Future<AudioTranscodeTaskSnapshot> startAudioTranscodeTask() async {
    return const AudioTranscodeTaskSnapshot(
      taskId: 'fake_task',
      status: AudioTranscodeStatus.running,
      progress: 0.1,
      hintText: '处理中',
      inputCount: 1,
      plannedCount: 1,
      successCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<AudioTranscodeTaskSnapshot> stopTask(String taskId) async {
    return const AudioTranscodeTaskSnapshot(
      taskId: 'fake_task',
      status: AudioTranscodeStatus.cancelled,
      progress: 1,
      hintText: '已取消',
      inputCount: 1,
      plannedCount: 1,
      successCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<List<AudioTranscodeTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
    return const <AudioTranscodeTaskEvent>[];
  }

  @override
  Future<AudioTranscodeResult> fetchTranscodeResult(String taskId) async {
    return const AudioTranscodeResult(
      taskId: 'fake_task',
      status: AudioTranscodeStatus.success,
      successCount: 1,
      failedCount: 0,
      results: <AudioTranscodeResultItem>[],
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('audio transcode completion dialog opens output folder', (
    WidgetTester tester,
  ) async {
    final List<String> openedDirectories = <String>[];
    final Directory outputDirectory = await Directory.systemTemp.createTemp(
      'audio_transcode_output_',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));

    final AudioTranscodeController controller = AudioTranscodeController(
      defaultOutputDirectory: outputDirectory.path,
      bridge: _FakeAudioTranscodeTaskBridgeForDialog(),
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: AudioTranscodeEntryPage(
              controller: controller,
              onOpenOutputDirectory: (String directory) async {
                openedDirectories.add(directory);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final dynamic state = tester.state(find.byType(AudioTranscodeEntryPage));
    await state.debugShowCompletionDialog(
      AudioTranscodeTaskSnapshot(
        taskId: 'task_001',
        status: AudioTranscodeStatus.success,
        progress: 1,
        hintText: '转码完成',
        inputCount: 1,
        plannedCount: 1,
        successCount: 1,
        failedCount: 0,
        outputDirectory: outputDirectory.path,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('转码已完成'), findsOneWidget);
    expect(find.text('打开文件所在文件夹'), findsOneWidget);
    expect(find.textContaining('输出目录：'), findsOneWidget);

    await tester.tap(find.text('打开文件所在文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(openedDirectories, hasLength(1));
    expect(openedDirectories.single, outputDirectory.path);
    expect(find.text('转码已完成'), findsNothing);
  });
}
