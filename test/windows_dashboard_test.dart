import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/windows_dashboard.dart';
import 'package:remirror/translation.dart';

void main() {
  for (final width in [1440.0, 780.0]) {
    testWidgets('Windows dashboard works at ${width.toInt()} pixels',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = TextEditingController();
      addTearDown(original.dispose);
      var translated = false;

      await tester.pumpWidget(MaterialApp(
        home: WindowsDashboard(
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
          onTranslate: () => translated = true,
          onCancel: () {},
          onPractice: () {},
          onImport: () {},
          onOpenSession: (_) {},
          onDeleteSession: (_) {},
          onEditReference: (_) {},
          onReadingPreviewChanged: (_) {},
          onNewArticle: () {},
          onSample: () {},
        ),
      ));

      expect(find.text('粘贴文章'), findsOneWidget);
      expect(find.text('还没有练习记录'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello world.');
      await tester.pump();
      await tester.ensureVisible(find.text('生成参考译文'));
      await tester.tap(find.text('生成参考译文'));
      expect(translated, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
