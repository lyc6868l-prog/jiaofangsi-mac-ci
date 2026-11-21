import 'package:flutter/material.dart';

import '../layout/app_layout_contract.dart';
import '../router/app_router.dart';
import '../../features/auth/presentation/models/auth_session_snapshot.dart';
import '../../features/audio_transcode/presentation/audio_transcode_entry_page.dart';
import '../../shared/hardware_ui/hardware_ui.dart';
import '../../features/cleanup_dup/presentation/cleanup_dup_entry_page.dart';
import '../../features/metadata_edit/presentation/metadata_edit_entry_page.dart';
import '../../features/pinyin_generator/presentation/pinyin_generator_entry_page.dart';
import '../../features/usb_backup/presentation/usb_backup_entry_page.dart';
import '../../features/unlock_music/presentation/unlock_music_entry_page.dart';

class WorkspaceFrame extends StatelessWidget {
  const WorkspaceFrame({
    super.key,
    required this.metrics,
    required this.section,
    required this.sessionSnapshot,
  });

  final AppShellMetrics metrics;
  final AppShellSection section;
  final AuthSessionSnapshot sessionSnapshot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: metrics.workspaceFrameSize.width,
      height: metrics.workspaceFrameSize.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(
            AppLayoutContract.workspaceInnerPadding,
          ),
          child: SizedBox.expand(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: WorkspaceModule(
                section: section,
                sessionSnapshot: sessionSnapshot,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const Map<AppShellSection, ({String title, IconData icon})>
_lockedWorkspaceMeta = <AppShellSection, ({String title, IconData icon})>{
  AppShellSection.audioTranscode: (
    title: '音频转码',
    icon: Icons.multitrack_audio_rounded,
  ),
  AppShellSection.pinyinGenerator: (
    title: '首拼生成',
    icon: Icons.sort_by_alpha_rounded,
  ),
  AppShellSection.cleanupDup: (
    title: '曲库整理',
    icon: Icons.cleaning_services_rounded,
  ),
  AppShellSection.metadataEdit: (title: '信息修改', icon: Icons.edit_note_rounded),
  AppShellSection.usbBackup: (title: 'U盘备份', icon: Icons.usb_rounded),
};

Future<void> showVipFeatureDialog(
  BuildContext context,
  AppShellSection section,
) async {
  await showHardwareDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _VipFeatureDialogContent(
        section: section,
        onClose: () => Navigator.of(dialogContext).pop(),
      );
    },
  );
}

class WorkspaceModule extends StatelessWidget {
  const WorkspaceModule({
    super.key,
    required this.section,
    required this.sessionSnapshot,
  });

  final AppShellSection section;
  final AuthSessionSnapshot sessionSnapshot;

  static const Set<AppShellSection> _vipOnlySections = <AppShellSection>{
    AppShellSection.audioTranscode,
    AppShellSection.pinyinGenerator,
    AppShellSection.cleanupDup,
    AppShellSection.metadataEdit,
    AppShellSection.usbBackup,
  };

  bool get _hasFeatureAccess =>
      sessionSnapshot.isVip || sessionSnapshot.isGuest;

  bool get _isVipOnlySection => _vipOnlySections.contains(section);

  bool get _isLockedFeatureUser => _isVipOnlySection && !_hasFeatureAccess;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onLockedStartPressed = _isLockedFeatureUser
        ? () => showVipFeatureDialog(context, section)
        : null;

    return switch (section) {
      AppShellSection.audioTranscode => AudioTranscodeEntryPage(
        isFeatureLocked: _isLockedFeatureUser,
        onLockedStartPressed: onLockedStartPressed,
      ),
      AppShellSection.cleanupDup => CleanupDupEntryPage(
        isFeatureLocked: _isLockedFeatureUser,
        onLockedStartPressed: onLockedStartPressed,
      ),
      AppShellSection.unlockTool => const UnlockMusicEntryPage(),
      AppShellSection.pinyinGenerator => PinyinGeneratorEntryPage(
        isFeatureLocked: _isLockedFeatureUser,
        onLockedStartPressed: onLockedStartPressed,
      ),
      AppShellSection.usbBackup => UsbBackupEntryPage(
        isFeatureLocked: _isLockedFeatureUser,
        onLockedStartPressed: onLockedStartPressed,
      ),
      AppShellSection.metadataEdit => MetadataEditEntryPage(
        isFeatureLocked: _isLockedFeatureUser,
        onLockedStartPressed: onLockedStartPressed,
      ),
      AppShellSection.overview => const _WorkspaceOverviewView(),
    };
  }
}

class _WorkspaceOverviewView extends StatelessWidget {
  const _WorkspaceOverviewView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 420,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Image.asset(
                    'assets/brand/hud_template.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VipFeatureDialogContent extends StatelessWidget {
  const _VipFeatureDialogContent({
    required this.section,
    required this.onClose,
  });

  final AppShellSection section;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ({String title, IconData icon}) meta =
        _lockedWorkspaceMeta[section] ??
        (title: '当前功能', icon: Icons.lock_rounded);

    return HardwareDialog(
      width: kHardwareDialogStandardWidth,
      title: '${meta.title}暂未解锁',
      titleIcon: Icon(meta.icon),
      onClose: onClose,
      hudTitle: 'Feature Access / 功能权限',
      hudText: const Text(
        '当前账号可查看本版面，但功能暂不可使用。\n请开通会员后使用。',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: kTextLightGray,
          height: 1.6,
        ),
      ),
      body: const SizedBox.shrink(),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      footer: HardwareDialogFooter(
        actions: <Widget>[
          HardwareDialogAction(
            label: '知道了',
            variant: HardwareDialogActionVariant.confirm,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
