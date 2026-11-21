import 'dart:ui';

enum AppShellBreakpoint { blocked, compact, standard, wide }

final class AppLayoutContract {
  static const Size defaultWindowSize = Size(1440, 1028);
  static const Size minWindowSize = Size(1280, 948);

  static const double topBarHeight = 52;
  static const double cardZoneHeight = 280; // 125 * 2 + 30 gap
  static const double bottomStatusBarHeight = 28;
  static const double workspaceInnerPadding = 16;

  static const double outerHorizontalMargin = 24;
  static const double outerVerticalMargin = 16;

  static const double gapTopBarToCards = 16;
  static const double gapCardsToWorkspace = 16;
  static const double gapWorkspaceToBottomBar = 12;

  static const Size defaultWorkspaceFrameSize = Size(1392, 652);
  static const Size defaultModuleSafeAreaSize = Size(1360, 620);

  static AppShellBreakpoint breakpointForWindowSize(Size windowSize) {
    if (windowSize.width < minWindowSize.width ||
        windowSize.height < minWindowSize.height) {
      return AppShellBreakpoint.blocked;
    }
    if (windowSize.width < defaultWindowSize.width) {
      return AppShellBreakpoint.compact;
    }
    if (windowSize.width < 1600) {
      return AppShellBreakpoint.standard;
    }
    return AppShellBreakpoint.wide;
  }

  static AppShellMetrics resolve(Size windowSize) {
    final double shellWidth = windowSize.width - (outerHorizontalMargin * 2);
    final double shellHeight = windowSize.height - (outerVerticalMargin * 2);
    final double workspaceHeight =
        shellHeight -
        topBarHeight -
        gapTopBarToCards -
        cardZoneHeight -
        gapCardsToWorkspace -
        gapWorkspaceToBottomBar -
        bottomStatusBarHeight;

    final Size workspaceFrameSize = Size(shellWidth, workspaceHeight);
    final Size moduleSafeAreaSize = Size(
      shellWidth - (workspaceInnerPadding * 2),
      workspaceHeight - (workspaceInnerPadding * 2),
    );

    return AppShellMetrics(
      windowSize: windowSize,
      shellSize: Size(shellWidth, shellHeight),
      workspaceFrameSize: workspaceFrameSize,
      moduleSafeAreaSize: moduleSafeAreaSize,
      breakpoint: breakpointForWindowSize(windowSize),
    );
  }
}

final class AppShellMetrics {
  const AppShellMetrics({
    required this.windowSize,
    required this.shellSize,
    required this.workspaceFrameSize,
    required this.moduleSafeAreaSize,
    required this.breakpoint,
  });

  final Size windowSize;
  final Size shellSize;
  final Size workspaceFrameSize;
  final Size moduleSafeAreaSize;
  final AppShellBreakpoint breakpoint;

  bool get isBlocked => breakpoint == AppShellBreakpoint.blocked;
}
