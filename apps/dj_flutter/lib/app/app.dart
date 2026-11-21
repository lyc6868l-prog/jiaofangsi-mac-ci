import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'dj_app_scope.dart';
import 'router/app_router.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/controllers/python_auth_task_bridge.dart';
import '../features/auth/presentation/controllers/python_guest_task_bridge.dart';
import '../features/auth/presentation/models/auth_session_store.dart';
import '../shared/hardware_ui/hardware_ui.dart';
import '../shared/platform_utils.dart' as platform_utils;
import '../shared/task_runtime/task_running_notifier.dart';

class DjFlutterApp extends StatefulWidget {
  const DjFlutterApp({super.key});

  @override
  State<DjFlutterApp> createState() => _DjFlutterAppState();
}

ThemeData _buildAppTheme(String? fontFamily) {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFE11D48),
    brightness: Brightness.dark,
  );

  final ButtonStyle dialogButtonStyle = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(0, 42)),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    ),
    textStyle: WidgetStateProperty.all(
      const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return const Color(0xFF1E1E23).withValues(alpha: 0.35);
      }
      return const Color(0xFF151519);
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return kEmerald;
      }
      if (states.contains(WidgetState.disabled)) {
        return kTextGray.withValues(alpha: 0.55);
      }
      return kTextLightGray;
    }),
    side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
      final Color accent =
          states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.hovered)
          ? kEmerald.withValues(alpha: 0.55)
          : Colors.black.withValues(alpha: 0.92);
      return BorderSide(color: accent);
    }),
    elevation: WidgetStateProperty.all(0),
    shadowColor: WidgetStateProperty.all(Colors.black),
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: kDeepBlack,
    canvasColor: kPanelBg,
    cardColor: kPanelBg,
    dialogTheme: DialogThemeData(
      backgroundColor: kPanelBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      titleTextStyle: const TextStyle(
        color: Color(0xFFF3F4F6),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
      contentTextStyle: const TextStyle(
        color: kTextLightGray,
        fontSize: 13,
        height: 1.6,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kHardwareBlack,
      hintStyle: const TextStyle(color: kTextGray, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kCrimson.withValues(alpha: 0.45)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return kCrimson.withValues(alpha: 0.18);
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(kCrimson),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    textButtonTheme: TextButtonThemeData(style: dialogButtonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: dialogButtonStyle),
    filledButtonTheme: FilledButtonThemeData(style: dialogButtonStyle),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kPanelBg,
      contentTextStyle: const TextStyle(color: kTextLightGray),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _DjFlutterAppState extends State<DjFlutterApp> {
  AuthSessionStore? _sessionStore;
  AuthController? _authController;
  AuthTaskBridge? _authBridge;
  GuestTaskBridge? _guestBridge;
  TaskRunningNotifier? _taskRunningNotifier;
  bool _initialized = false;
  String? _initErrorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBridges();
  }

  Future<void> _initializeBridges() async {
    if (_initialized || _authBridge != null) {
      return;
    }
    try {
      final String pythonExecutable = _resolvePythonExecutable();
      final String workingDirectory = _resolvePythonRuntimeDirectory();
      const String scriptModule = 'dj_runtime_py';

      _authBridge = PythonAuthTaskBridge(
        pythonExecutable: pythonExecutable,
        workingDirectory: workingDirectory,
        scriptModule: scriptModule,
      );
      _guestBridge = PythonGuestTaskBridge(
        pythonExecutable: pythonExecutable,
        workingDirectory: workingDirectory,
        scriptModule: scriptModule,
      );

      await _authBridge!.ensureStarted();
      await _guestBridge!.ensureStarted();

      _authController = AuthController(
        authBridge: _authBridge!,
        guestBridge: _guestBridge!,
      );
      _sessionStore = AuthSessionStore();
      _taskRunningNotifier = TaskRunningNotifier();

      setState(() {
        _initialized = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _initErrorMessage = '初始化失败，请检查运行环境后重试。';
        });
      }
    }
  }

  String _resolvePythonExecutable() {
    final Directory projectRoot = _resolveProjectRoot();
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  String _resolvePythonRuntimeDirectory() {
    final Directory projectRoot = _resolveProjectRoot();
    return p.join(projectRoot.path, 'runtime', 'dj_runtime_py');
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  @override
  void dispose() {
    _sessionStore?.dispose();
    _taskRunningNotifier?.dispose();
    _authBridge?.close().ignore();
    _guestBridge?.close().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        title: '教坊司 DJ 便捷工具',
        theme: _buildAppTheme(Platform.isWindows ? 'Microsoft YaHei' : null),
        home: Scaffold(
          backgroundColor: const Color(0xFF1a1a2e),
          body: Center(
            child: _initErrorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFE11D48),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '初始化失败',
                          style: TextStyle(
                            color: Color(0xFFF3F4F6),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _initErrorMessage!,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _initErrorMessage = null;
                            });
                            _initializeBridges();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重试'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(color: Color(0xFF0F766E)),
          ),
        ),
      );
    }

    return DjAppScope(
      sessionStore: _sessionStore!,
      authController: _authController!,
      authBridge: _authBridge!,
      guestBridge: _guestBridge!,
      taskRunningNotifier: _taskRunningNotifier!,
      child: MaterialApp(
        title: '教坊司 DJ 便捷工具',
        theme: _buildAppTheme(Platform.isWindows ? 'Microsoft YaHei' : null),
        onGenerateRoute: AppRouter.onGenerateRoute,
        initialRoute: AppRouter.loginPath,
      ),
    );
  }
}
