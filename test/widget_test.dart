import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/dictionary_reader.dart';
import 'package:remirror/main.dart';
import 'package:remirror/windows_study_page.dart';

void main() {
  testWidgets('Android opens the article study workflow', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(const ReMirrorApp());
      expect(find.byType(WindowsStudyPage), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
