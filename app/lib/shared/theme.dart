import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The family of the bundled IBM Plex Sans KR, declared in `pubspec.yaml`.
const appFontFamily = 'IBM Plex Sans KR';

/// The spacing scale, on a 4 px base. Every padding, margin and gap in the
/// app is one of these.
abstract final class AppSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;

  /// Space between the screen's left and right edges and its content.
  static const gutter = s20;

  /// Space between two rows of a list.
  static const rowGap = s8;
}

/// The corner radii of the app's rounded surfaces. A chip is fully rounded.
abstract final class AppRadius {
  /// A sheet's top corners.
  static const sheet = 28.0;

  /// A card: a study card, a header, or a card preview.
  static const card = 24.0;

  /// A row in a list.
  static const row = 18.0;

  /// A button or a field.
  static const control = 16.0;
}

/// The heights of the app's controls.
abstract final class AppSize {
  /// The screen's or the sheet's primary action, at the bottom.
  static const cta = 56.0;

  /// Every other button.
  static const button = 52.0;

  /// A one-line field.
  static const field = 48.0;

  /// The least width and height of anything tapped.
  static const tapTarget = 44.0;

  /// A sheet's drag handle.
  static const handle = Size(40, 5);

  /// The account screen's initial avatar.
  static const avatar = 48.0;
}

/// The app's type scale, all IBM Plex Sans KR, with explicit line heights.
/// A style without a colour takes the text colour of where it is drawn.
abstract final class AppType {
  /// A home screen's title: 28/36, bold.
  static const display = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// A pushed screen's title and the deck name: 22/30, bold.
  static const title = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  /// A sheet's title: 20/28, bold.
  static const headline = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w700,
  );

  /// Running text: 16/24.
  static const body = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// A row's title: 16/24, semibold.
  static const bodyStrong = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );

  /// A button's label: 15/20, semibold.
  static const label = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );

  /// Secondary text, such as a sheet's body or a row's second line: 14/20.
  static const secondary = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Small supporting text: 13/18.
  static const caption = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  /// A section label: 13/18, semibold.
  static const section = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  /// Chips and hints: 12/16.
  static const micro = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// The scale as Material's text theme, so Material widgets draw in it.
  static const textTheme = TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: display,
    headlineMedium: title,
    headlineSmall: headline,
    titleLarge: title,
    titleMedium: bodyStrong,
    titleSmall: section,
    bodyLarge: body,
    bodyMedium: secondary,
    bodySmall: caption,
    labelLarge: label,
    labelMedium: section,
    labelSmall: micro,
  );
}

/// Google's "Sign in with Google" button as its branding guidelines specify
/// (developers.google.com/identity/branding-guidelines): each theme's fill,
/// one-pixel stroke, label colour and "G" mark, the label's size, and the
/// space around the mark per platform.
final class GoogleButtonStyle {
  const GoogleButtonStyle._({
    required this.fill,
    required this.stroke,
    required this.label,
    required this.mark,
  });

  /// The light button, drawn in the light theme.
  static const light = GoogleButtonStyle._(
    fill: Color(0xFFFFFFFF),
    stroke: Color(0xFF747775),
    label: Color(0xFF1F1F1F),
    mark: 'assets/google/g_mark_light.png',
  );

  /// The dark button, drawn in the dark theme.
  static const dark = GoogleButtonStyle._(
    fill: Color(0xFF131314),
    stroke: Color(0xFF8E918F),
    label: Color(0xFFE3E3E3),
    mark: 'assets/google/g_mark_dark.png',
  );

  /// The button of the theme [context] is drawn in.
  static GoogleButtonStyle of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final Color fill;
  final Color stroke;
  final Color label;

  /// The "G" mark's asset, taken from Google's button for this theme.
  final String mark;

  /// The mark's width and height.
  static const markSize = 20.0;

  /// The label: medium weight, 14 on 20.
  static const labelStyle = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  /// The space before the mark, between the mark and the label, and after
  /// the label: 16, 12 and 16 on iOS, 12, 10 and 12 elsewhere.
  static ({double start, double gap, double end}) spacing(
    TargetPlatform platform,
  ) => switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => (start: 16, gap: 12, end: 16),
    _ => (start: 12, gap: 10, end: 12),
  };
}

/// The two shadows the app draws, in the theme's [AppColors.shadow].
abstract final class AppShadow {
  /// A card resting on the ground: a header, a card preview, a previous card.
  static List<BoxShadow> card(AppColors colors) => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.12),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  /// A surface raised over others: the current study card, a sheet.
  static List<BoxShadow> raised(AppColors colors) => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.2),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
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
  final control = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
  const buttonSize = Size(AppSize.tapTarget, AppSize.button);
  final textTheme = AppType.textTheme.apply(
    bodyColor: colors.ink,
    displayColor: colors.ink,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: colors.ground,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ground,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppType.title.copyWith(color: colors.ink),
    ),
    dividerTheme: DividerThemeData(color: colors.hairline),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        shape: control,
        textStyle: AppType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: control,
        textStyle: AppType.label,
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.hairline),
        backgroundColor: colors.surface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppSize.tapTarget, AppSize.tapTarget),
        shape: control,
        textStyle: AppType.label,
        foregroundColor: colors.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      hintStyle: AppType.body.copyWith(color: colors.muted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s16,
        vertical: AppSpace.s12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colors.ink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colors.dontKnowText),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colors.dontKnowText, width: 1.5),
      ),
      errorStyle: AppType.caption.copyWith(color: colors.dontKnowText),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(AppSize.tapTarget, AppSize.button),
        textStyle: AppType.label,
        foregroundColor: colors.ink,
        selectedForegroundColor: colors.surface,
        selectedBackgroundColor: colors.ink,
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.hairline),
        shape: control,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: control,
      contentTextStyle: AppType.secondary.copyWith(color: colors.surface),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      textStyle: AppType.body.copyWith(color: colors.ink),
      shape: control,
    ),
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
