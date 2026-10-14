import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The family of the bundled IBM Plex Sans KR, declared in `pubspec.yaml`.
const appFontFamily = 'IBM Plex Sans KR';

/// The corner radii of the app's rounded surfaces.
abstract final class AppRadius {
  /// A card: a study card, a header, or a card preview.
  static const card = 24.0;

  /// A row in a list, a field or a button.
  static const row = 16.0;
}

/// The app's colour tokens. Every colour a screen draws comes from here or
/// from the [ColorScheme] built from it.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ground,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.know,
    required this.onKnow,
    required this.knowDot,
    required this.dontKnow,
    required this.dontKnowText,
    required this.onDontKnowText,
    required this.depth,
    required this.shadow,
  });

  /// Light tokens: ink on white surfaces over a pale grey ground.
  static const light = AppColors(
    ground: Color(0xFFEEF1F5),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF16191F),
    muted: Color(0xFF5A6170),
    hairline: Color(0xFFDDE1E7),
    know: Color(0xFF1B7F45),
    onKnow: Color(0xFFFFFFFF),
    knowDot: Color(0xFF1E9E4A),
    dontKnow: Color(0xFFE0352B),
    dontKnowText: Color(0xFFB71C1C),
    onDontKnowText: Color(0xFFFFFFFF),
    depth: Color(0xFFDADCE0),
    shadow: Color(0xFF000000),
  );

  /// Dark tokens: the greens and reds lightened to meet WCAG AA on [surface],
  /// and the depth of a previous card stepping darker toward [ground].
  static const dark = AppColors(
    ground: Color(0xFF0F1115),
    surface: Color(0xFF1A1D23),
    ink: Color(0xFFECEEF2),
    muted: Color(0xFFA3A9B4),
    hairline: Color(0xFF2E333B),
    know: Color(0xFF4CC27A),
    onKnow: Color(0xFF0F1115),
    knowDot: Color(0xFF5BD08A),
    dontKnow: Color(0xFFFF6B60),
    dontKnowText: Color(0xFFFF8A80),
    onDontKnowText: Color(0xFF0F1115),
    depth: Color(0xFF0F1115),
    shadow: Color(0xFF000000),
  );

  /// The screen's background, under every surface.
  final Color ground;

  /// Cards, rows, sheets and bars.
  final Color surface;

  /// Primary text and the dark primary button.
  final Color ink;

  /// Secondary text.
  final Color muted;

  /// Dividers and outlines.
  final Color hairline;

  /// "Know", as text on [surface] and as a fill under [onKnow].
  final Color know;
  final Color onKnow;

  /// A "Know" answer's dot.
  final Color knowDot;

  /// "Don't know", as a dot or a tint; never as text.
  final Color dontKnow;

  /// "Don't know", as text on [surface] and as a fill under [onDontKnowText].
  final Color dontKnowText;
  final Color onDontKnowText;

  /// The colour a previous card fades toward, a step per card of depth.
  final Color depth;

  /// The colour of every shadow, before its opacity.
  final Color shadow;

  /// The tokens of [context]'s theme.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (throw StateError('the app theme carries no AppColors'));

  @override
  AppColors copyWith({
    Color? ground,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? hairline,
    Color? know,
    Color? onKnow,
    Color? knowDot,
    Color? dontKnow,
    Color? dontKnowText,
    Color? onDontKnowText,
    Color? depth,
    Color? shadow,
  }) => AppColors(
    ground: ground ?? this.ground,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    hairline: hairline ?? this.hairline,
    know: know ?? this.know,
    onKnow: onKnow ?? this.onKnow,
    knowDot: knowDot ?? this.knowDot,
    dontKnow: dontKnow ?? this.dontKnow,
    dontKnowText: dontKnowText ?? this.dontKnowText,
    onDontKnowText: onDontKnowText ?? this.onDontKnowText,
    depth: depth ?? this.depth,
    shadow: shadow ?? this.shadow,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return AppColors(
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      hairline: mix(hairline, other.hairline),
      know: mix(know, other.know),
      onKnow: mix(onKnow, other.onKnow),
      knowDot: mix(knowDot, other.knowDot),
      dontKnow: mix(dontKnow, other.dontKnow),
      dontKnowText: mix(dontKnowText, other.dontKnowText),
      onDontKnowText: mix(onDontKnowText, other.onDontKnowText),
      depth: mix(depth, other.depth),
      shadow: mix(shadow, other.shadow),
    );
  }
}

/// The light theme.
final lightTheme = _theme(Brightness.light, AppColors.light);

/// The dark theme.
final darkTheme = _theme(Brightness.dark, AppColors.dark);

ThemeData _theme(Brightness brightness, AppColors colors) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.ink,
    onPrimary: colors.surface,
    secondary: colors.know,
    onSecondary: colors.onKnow,
    error: colors.dontKnowText,
    onError: colors.onDontKnowText,
    surface: colors.surface,
    onSurface: colors.ink,
    onSurfaceVariant: colors.muted,
    surfaceContainerLowest: colors.surface,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surface,
    surfaceContainerHigh: colors.surface,
    surfaceContainerHighest: colors.ground,
    outline: colors.muted,
    outlineVariant: colors.hairline,
    shadow: colors.shadow,
    inverseSurface: colors.ink,
    onInverseSurface: colors.surface,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.row),
  );
  const buttonSize = Size(64, 52);
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    scaffoldBackgroundColor: colors.ground,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ground,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(color: colors.hairline),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: buttonSize, shape: rounded),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: rounded,
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.hairline),
        backgroundColor: colors.surface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.row),
        borderSide: BorderSide.none,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.ground,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.surface),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// The device storage the theme choice is kept in. The composition site
/// overrides it with the storage it opens.
final themeStorageProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError(
    'themeStorageProvider is overridden at the composition site',
  ),
);

/// The keys [themeStorageProvider] must be opened to cache.
const themeStorageKeys = {_themeModeKey};

const _themeModeKey = 'themeMode';

/// The theme the user chose: following the system, light or dark.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Reads the stored choice, [ThemeMode.system] when none or an unknown one is
/// stored, and applies and stores a new one.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.watch(themeStorageProvider).getString(_themeModeKey);
    return ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system;
  }

  /// Applies [mode] at once, then stores it.
  Future<void> choose(ThemeMode mode) async {
    state = mode;
    await ref.read(themeStorageProvider).setString(_themeModeKey, mode.name);
  }
}
