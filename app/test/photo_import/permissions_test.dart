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
  const usageKeys = [
    'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSMicrophoneUsageDescription',
  ];

  test('Info.plist describes camera, photo library and microphone use', () {
    final plist = _plistStrings('ios/Runner/Info.plist');
    // Control: the reader finds a key the plist has always held.
    expect(plist['CFBundleDisplayName'], 'Smartman');

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

  test('the Android manifest asks for the camera and drops the microphone', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.CAMERA" />'),
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />',
      ),
    );
  });
}
