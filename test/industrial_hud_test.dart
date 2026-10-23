import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/industrial_hud.dart';
import 'package:remirror/industrial_theme.dart';

void main() {
  testWidgets('transient HUD leaves controls usable and retracts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: industrialTheme(),
      home: Scaffold(
        body: Column(children: [
          const IndustrialHud(
            eyebrow: '/// RE MIRROR / PRACTICE',
            title: '进入回译模式',
            detail: '从中文重新写出英文',
          ),
          TextButton(onPressed: () => taps++, child: const Text('继续操作')),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('继续操作'));
    expect(taps, 1);
    expect(tester.getSize(find.byType(IndustrialHud)).height, greaterThan(50));

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(IndustrialHud)).height, 0);
  });

  testWidgets('progress HUD remains as a compact capsule', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: industrialTheme(),
      home: const Scaffold(
        body: IndustrialHud(
          eyebrow: '/// RE MIRROR / TRANSLATION',
          title: '译文生成中',
          detail: '已完成 1 / 3 个片段',
          persistent: true,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.byType(IndustrialStatusPill), findsOneWidget);
    expect(find.text('已完成 1 / 3 个片段'), findsOneWidget);
  });

  testWidgets('reduced motion shows the cue without animation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: industrialTheme(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: IndustrialHud(
            eyebrow: '/// RE MIRROR / PRACTICE',
            title: '进入回译模式',
            detail: '从中文重新写出英文',
          ),
        ),
      ),
    ));
    expect(find.byType(IndustrialStatusPill), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.getSize(find.byType(IndustrialHud)).height, 0);
  });
}
