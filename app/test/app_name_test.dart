import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `appTitle` of an ARB file.
String _appTitle(String path) =>
    (jsonDecode(File(path).readAsStringSync())
            as Map<String, Object?>)['appTitle']!
        as String;

/// The value of `key` in an `.strings` file.
String? _stringsValue(String path, String key) => RegExp(
  '^"$key" = "([^"]*)";\$',
  multiLine: true,
).firstMatch(File(path).readAsStringSync())?.group(1);

/// The value of `<string name="name">` in an Android resource file.
String? _androidString(String path, String name) =>
    RegExp('<string name="$name">([^<]*)</string>')
        .firstMatch(File(path).readAsStringSync())
        ?.group(1);

void main() {
  final english = _appTitle('lib/l10n/app_en.arb');
  final korean = _appTitle('lib/l10n/app_ko.arb');

  test('the app is named knowno in English and 알아몰라 in Korean', () {
    expect(english, 'knowno');
    expect(korean, '알아몰라');
  });

  test('iOS shows the app title of each language under the icon', () {
    expect(
      _stringsValue(
        'ios/Runner/en.lproj/InfoPlist.strings',
        'CFBundleDisplayName',
      ),
      english,
    );
    expect(
      _stringsValue(
        'ios/Runner/ko.lproj/InfoPlist.strings',
        'CFBundleDisplayName',
      ),
      korean,
    );
    // A language with no strings file of its own falls back to Info.plist.
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<key>CFBundleDisplayName</key>\n\t<string>$english</string>'),
    );
  });

  test('Android labels the app with the app title of each language', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="@string/app_name"'),
    );
    expect(
      _androidString('android/app/src/main/res/values/strings.xml', 'app_name'),
      english,
    );
    expect(
      _androidString(
        'android/app/src/main/res/values-ko/strings.xml',
        'app_name',
      ),
      korean,
    );
  });

  test('both platforms identify the app as app.knowno', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "app.knowno"'));
    expect(gradle, contains('applicationId = "app.knowno"'));
    // The manifest's ".MainActivity" resolves against the namespace, so the
    // activity must be declared in that package or the app cannot start.
    expect(
      File('android/app/src/main/kotlin/app/knowno/MainActivity.kt')
          .readAsStringSync(),
      startsWith('package app.knowno\n'),
    );

    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final identifiers = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(project)
        .map((match) => match.group(1))
        .toSet();
    expect(identifiers, {'app.knowno', 'app.knowno.RunnerTests'});
  });
}
