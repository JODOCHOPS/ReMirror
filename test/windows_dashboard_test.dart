import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/industrial_hud.dart';
import 'package:remirror/industrial_theme.dart';
import 'package:remirror/windows_dashboard.dart';
import 'package:remirror/translation.dart';

void main() {
  for (final size in [
    const Size(1440, 900),
    const Size(780, 700),
    const Size(800, 500),
    const Size(390, 844),
    const Size(390, 600),
  ]) {
    testWidgets('dashboard sections fit ${size.width.toInt()} x ${size.height.toInt()}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = TextEditingController();
      addTearDown(original.dispose);
      var translated = false;
      var practiced = 0;

      Widget app({List<TranslatedParagraph> result = const [], Widget? hud}) =>
          MaterialApp(
            theme: industrialTheme(),
            home: WindowsDashboard(
              hud: hud,
              original: original,
              result: result,
              source: TranslationSource.offline,
              sessions: const [],
              activeSessionId: null,
              busy: false,
              importing: false,
              loadingHistory: false,
              readingPreview: false,
              completed: 0,
              total: 0,
              error: null,
              historyError: null,
              onSettings: () {},
              onSourceChanged: (_) {},
              onTranslate: () => translated = true,
              onCancel: () {},
              onPractice: () => practiced++,
              onImport: () {},
              onImportArticle: () {},
              onOpenSession: (_) {},
              onDeleteSession: (_) {},
              onEditReference: (_) {},
              onReadingPreviewChanged: (_) {},
              onNewArticle: () {},
              onSample: () {},
            ),
          );

      await tester.pumpWidget(app());
      expect(find.byKey(const ValueKey('open-article')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-reference')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-practice')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-article')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello world.');
      await tester.pump();
      await tester.ensureVisible(find.text('查看参考译文'));
      await tester.tap(find.text('查看参考译文'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('生成参考译文'));
      await tester.tap(find.text('生成参考译文'));
      expect(translated, isTrue);

      await tester.tap(find.byKey(const ValueKey('back-to-dashboard')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('open-practice')));
      await tester.tap(find.byKey(const ValueKey('open-practice')));
      await tester.pumpAndSettle();
      expect(find.text('进入逐句回译'), findsOneWidget);

      await tester.pumpWidget(app(result: const [
        TranslatedParagraph('Hello world.', '你好，世界。'),
      ]));
      await tester.pump();
      await tester.ensureVisible(find.text('进入逐句回译'));
      await tester.tap(find.text('进入逐句回译'));
      expect(practiced, 1);
      await tester.tap(find.byKey(const ValueKey('back-to-dashboard')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('open-practice')));
      await tester.tap(find.byKey(const ValueKey('open-practice')));
      expect(practiced, 2);
    });
  }

  testWidgets('translation HUD does not move dashboard content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = TextEditingController();
    addTearDown(original.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: industrialTheme(),
      home: WindowsDashboard(
        hud: const IndustrialHud(
          eyebrow: '/// RE MIRROR / TRANSLATION',
          title: '译文已就绪',
          detail: '参考译文已生成',
        ),
        original: original,
        result: const [],
        source: TranslationSource.offline,
        sessions: const [],
        activeSessionId: null,
        busy: false,
        importing: false,
        loadingHistory: false,
        readingPreview: false,
        completed: 0,
        total: 0,
        error: null,
        historyError: null,
        onSettings: () {},
        onSourceChanged: (_) {},
        onTranslate: () {},
        onCancel: () {},
        onPractice: () {},
        onImport: () {},
        onImportArticle: () {},
        onOpenSession: (_) {},
        onDeleteSession: (_) {},
        onEditReference: (_) {},
        onReadingPreviewChanged: (_) {},
        onNewArticle: () {},
        onSample: () {},
      ),
    ));
    final before = tester.getTopLeft(find.text('从阅读到表达'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getTopLeft(find.text('从阅读到表达')), before);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('从阅读到表达')), before);
    expect(tester.takeException(), isNull);
  });
}
