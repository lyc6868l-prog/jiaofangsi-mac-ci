import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';

void main() async {
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const Size loginWindowSize = Size(980, 700);
  const WindowOptions windowOptions = WindowOptions(
    size: loginWindowSize,
    minimumSize: loginWindowSize,
    maximumSize: loginWindowSize,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMinimumSize(loginWindowSize);
    await windowManager.setMaximumSize(loginWindowSize);
    await windowManager.setSize(loginWindowSize);
    await windowManager.setResizable(false);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const DjFlutterApp());
}
