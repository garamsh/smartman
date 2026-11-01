import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The value of each `"key" = "value";` line of an `.strings` file.
Map<String, String> _strings(String path) => {
  for (final match in RegExp(
    r'^"(\w+)" = "([^"]*)";$',
    multiLine: true,
  ).allMatches(File(path).readAsStringSync()))
    match.group(1)!: match.group(2)!,
};

/// The string after each `<key>` of the top-level dictionary of a plist.
Map<String, String> _plistStrings(String path) => {
  for (final match in RegExp(
    r'<key>(\w+)</key>\s*<string>([^<]*)</string>',
  ).allMatches(File(path).readAsStringSync()))
    match.group(1)!: match.group(2)!,
};

void main() {
  /// The camera and the library for photos, and the microphone for a sound
  /// block's recording (ADR 0112).
  const usageKeys = [
    'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSMicrophoneUsageDescription',
  ];

  test('Info.plist describes camera, photo library and microphone use', () {
    final plist = _plistStrings('ios/Runner/Info.plist');
    // Control: the reader finds a key the plist has always held.
    expect(plist['CFBundleDisplayName'], 'knowno');

    for (final key in usageKeys) {
      expect(plist[key], isNotNull, reason: key);
      expect(plist[key]!.trim(), isNotEmpty, reason: key);
    }
  });

  test('the usage descriptions are in Korean and English, and the project ships both', () {
    final korean = _strings('ios/Runner/ko.lproj/InfoPlist.strings');
    final english = _strings('ios/Runner/en.lproj/InfoPlist.strings');
    final hangul = RegExp(r'[가-힣]');

    for (final key in usageKeys) {
      expect(korean[key], matches(hangul), reason: key);
      expect(english[key], isNot(matches(hangul)), reason: key);
      expect(english[key], isNotEmpty, reason: key);
    }
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('path = ko.lproj/InfoPlist.strings;'));
    expect(project, contains('path = en.lproj/InfoPlist.strings;'));
    expect(project, contains('/* InfoPlist.strings in Resources */,'));
  });

  test('the Android manifest declares the microphone, for a sound block, and not the camera, so the camera intent asks for no permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    // Control: the reader sees the manifest's own declarations.
    expect(manifest, contains('android.intent.action.PROCESS_TEXT'));

    // image_picker asks for the camera permission when the manifest declares
    // it, and its camera intent fails without it.
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
  });
}
