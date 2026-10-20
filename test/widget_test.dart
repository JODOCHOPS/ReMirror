import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/main.dart';
import 'package:remirror/dictionary_reader.dart';

void main() {
  testWidgets('the first translation screen works in a narrow viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ReMirrorApp());
    await tester.pumpAndSettle();

    expect(find.text('从理解原文开始。'), findsOneWidget);
    expect(find.text('生成中文参考译文'), findsOneWidget);
    expect(find.text('Google 翻译'), findsOneWidget);

    await tester.tap(find.byTooltip('翻译源设置'));
    await tester.pumpAndSettle();
    expect(find.text('翻译源设置'), findsOneWidget);
    expect(find.text('Google Cloud Translation'), findsOneWidget);
  });

  testWidgets('a tapped English word opens the dictionary dialog',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DictionaryReader(text: 'Learning a language.')),
    ));
    await tester.tapAt(tester.getTopLeft(find.byType(DictionaryReader)) +
        const Offset(25, 12));
    await tester.pump();
    expect(find.text('Learning'), findsOneWidget);
  });
}
