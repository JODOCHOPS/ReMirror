import 'package:flutter/material.dart';

import 'industrial_theme.dart';
import 'windows_study_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReMirrorApp());
}

class ReMirrorApp extends StatelessWidget {
  const ReMirrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ReMirror',
        debugShowCheckedModeBanner: false,
        theme: industrialTheme(),
        scrollBehavior:
            const MaterialScrollBehavior().copyWith(scrollbars: false),
        home: const WindowsStudyPage(),
      );
}
