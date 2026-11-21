import 'package:flutter/material.dart';

import '../dj_app_scope.dart';
import '../shell/app_shell_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';

enum AppShellSection {
  overview,
  unlockTool,
  audioTranscode,
  pinyinGenerator,
  cleanupDup,
  metadataEdit,
  usbBackup,
}

final class AppRouter {
  static const String homePath = '/';
  static const String shellPath = '/shell';
  static const String loginPath = '/login';
  static const String unlockToolPath = '/unlock-tool';
  static const String audioTranscodePath = '/audio-transcode';
  static const String pinyinGeneratorPath = '/pinyin-generator';
  static const String cleanupDupPath = '/cleanup-dup';
  static const String metadataEditPath = '/metadata-edit';
  static const String usbBackupPath = '/usb-backup';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case homePath:
      case loginPath:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case shellPath:
        return _guardedShellRoute(settings);
      default:
        return _guardedShellRoute(settings);
    }
  }

  static MaterialPageRoute<void> _guardedShellRoute(RouteSettings settings) {
    final AppShellSection section = switch (settings.name) {
      unlockToolPath => AppShellSection.unlockTool,
      audioTranscodePath => AppShellSection.audioTranscode,
      pinyinGeneratorPath => AppShellSection.pinyinGenerator,
      cleanupDupPath => AppShellSection.cleanupDup,
      metadataEditPath => AppShellSection.metadataEdit,
      usbBackupPath => AppShellSection.usbBackup,
      _ => settings.arguments as AppShellSection? ?? AppShellSection.overview,
    };
    return MaterialPageRoute<void>(
      builder: (BuildContext context) {
        final DjAppScope? scope = DjAppScope.maybeOf(context);
        // Fail closed: a shell must never be reachable without an explicit
        // authenticated user session.  Guests were removed with the free-trial
        // flow, so only a real user session is allowed here.
        if (scope == null || !scope.sessionStore.snapshot.isUser) {
          return const LoginPage();
        }
        return AppShellPage(initialSection: section);
      },
      settings: settings,
    );
  }
}
