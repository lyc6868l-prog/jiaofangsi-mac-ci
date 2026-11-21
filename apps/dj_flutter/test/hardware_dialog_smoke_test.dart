import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dj_flutter/features/auth/presentation/widgets/login_card.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart';

class _DialogHarness extends StatelessWidget {
  const _DialogHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext innerContext) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  showHardwareMessageDialog(
                    context: innerContext,
                    title: '测试提示',
                    message: '这是一条用于验收的弹窗消息。',
                  );
                },
                child: const Text('打开弹窗'),
              ),
            );
          },
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hardware message dialog opens and closes normally', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _DialogHarness());
    await tester.tap(find.text('打开弹窗'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(HardwareDialog), findsOneWidget);
    expect(find.text('测试提示'), findsOneWidget);
    expect(find.text('这是一条用于验收的弹窗消息。'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(HardwareDialog), findsNothing);
  });

  testWidgets('login disclaimer dialog uses hardware dialog layout', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginCard())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('登 录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(HardwareDialog), findsOneWidget);
    expect(find.text('用户免责协议'), findsOneWidget);
    expect(find.text('下次不再弹出'), findsOneWidget);
    expect(find.text('我已阅读并同意'), findsOneWidget);
  });
}
