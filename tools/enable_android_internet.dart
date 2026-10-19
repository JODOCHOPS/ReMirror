import 'dart:io';

/// Adds the release Internet permission to a generated Flutter Android runner.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final source = manifest.readAsStringSync();
  const permission =
      '<uses-permission android:name="android.permission.INTERNET" />';
  if (source.contains(permission)) return;

  const marker =
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">';
  if (!source.contains(marker)) {
    stderr.writeln('Unexpected manifest format: ${manifest.path}');
    exitCode = 1;
    return;
  }
  manifest.writeAsStringSync(
    source.replaceFirst(marker, '$marker\n    $permission'),
  );
}
