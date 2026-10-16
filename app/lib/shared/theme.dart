import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The family of the bundled Pretendard, declared in `pubspec.yaml`.
const appFontFamily = 'Pretendard';

/// The spacing scale, on a 4 px base. Every padding, margin and gap in the
/// app is one of these.
abstract final class AppSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s28 = 28.0;
  static const s32 = 32.0;
  static const s40 = 40.0;

  /// Space between the screen's left and right edges and its content.
  static const gutter = s20;

  /// Space between two rows of a list.
  static const rowGap = s8;

  /// Space between two sections of a screen.
  static const sectionGap = s28;
}

/// The corner radii of the app's rounded surfaces. A chip is fully rounded.
abstract final class AppRadius {
  /// The bottom corners of the sign-in screen's brand panel.
  static const panel = 40.0;

  /// A sheet's top corners.
  static const sheet = 28.0;

  /// A card: a study card, the today card, or a card preview.
  static const card = 24.0;

  /// A previous card in the study stack.
  static const previous = 20.0;

  /// A row in a list, and a group of rows.
  static const row = 18.0;

  /// A button.
  static const button = 16.0;

  /// A field.
  static const field = 14.0;
}

/// The heights and sizes of the app's controls and brand marks.
abstract final class AppSize {
  /// The screen's or the sheet's primary action, at the bottom.
  static const cta = 56.0;

  /// Every other button.
  static const button = 52.0;

  /// A one-line field.
  static const field = 52.0;

  /// The search field over a list.
  static const search = 48.0;

  /// The least width and height of anything tapped.
  static const tapTarget = 44.0;

  /// A sheet's drag handle.
  static const handle = Size(40, 5);

  /// The account screen's initial avatar.
  static const avatar = 56.0;

  /// The home screen's initial avatar, in its top bar.
  static const smallAvatar = 32.0;

  /// A deck row's initial tile.
  static const deckTile = 44.0;

  /// A small icon, inside a button or a line of text.
  static const smallIcon = 18.0;

  /// The horizontal lockup's height in the home screen's top bar.
  static const lockupHeight = 30.0;

  /// The stacked lockup's width on the sign-in screen.
  static const stackedLockupWidth = 200.0;

  /// The mascot's circle on the empty home screen.
  static const mascotLarge = 128.0;

  /// The mascot's circle on the study completion card.
  static const mascotMedium = 112.0;

  /// The mascot in the account screen's footer.
  static const mascotSmall = 28.0;

  /// The symbol in the today card's corner.
  static const heroSymbol = 120.0;

  /// The study progress bar's thickness.
  static const progress = 8.0;

  /// An answer's dot on a previous card.
  static const dot = 8.0;
}

/// The app's type scale, all Pretendard, with explicit line heights.
/// A style without a colour takes the text colour of where it is drawn.
abstract final class AppType {
  /// A home screen's title: 28/36, extra bold.
  static const display = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
  );

  /// A pushed screen's title: 22/30, extra bold.
  static const title = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  /// The deck name over its cards: 26/34, extra bold.
  static const deckTitle = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 26,
    height: 34 / 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  /// The today card's count: 36/44, extra bold.
  static const figure = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
  );

  /// A sheet's title: 18/26, bold.
  static const headline = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w700,
  );

  /// Running text: 16/24, medium.
  static const body = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );

  /// A row's title: 16/24, bold.
  static const bodyStrong = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w700,
  );

  /// A button's label: 15/20, bold.
  static const label = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
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

  /// A section label and a hint: 13/18, semibold.
  static const section = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  /// Chips and notes: 12/16.
  static const micro = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// A study card's question: 30/38, extra bold.
  static const question = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  /// A study card's answer: 20/28, semibold.
  static const answer = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );

  /// The smallest a card's question, answer and previous-card text shrink to
  /// so their widest word fits its half.
  static const questionFloor = 18.0;
  static const answerFloor = 15.0;
  static const compactFloor = 12.0;

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

/// The brand's marks, drawn from the files under `assets/brand/`, each in a
/// light-ground and a dark-ground version.
abstract final class AppBrand {
  /// The symbol and the wordmark side by side.
  static String lockup(Brightness brightness) =>
      'assets/brand/smartman-lockup-${brightness.name}.png';

  /// The symbol over the wordmark.
  static String stacked(Brightness brightness) =>
      'assets/brand/smartman-stacked-${brightness.name}.png';

  /// The mascot alone, navy for a light ground and white for a dark one.
  static String symbol(Brightness brightness) =>
      'assets/brand/smartman-symbol-${brightness.name}.png';
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

/// The shadows the app draws, in the theme's [AppColors.shadow].
abstract final class AppShadow {
  /// A card resting on the ground: the today card, a card preview.
  static List<BoxShadow> card(AppColors colors) => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  /// The current study card and the completion card: a close, tight layer
  /// under a wide, soft one.
  static List<BoxShadow> raised(AppColors colors) => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.06),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: colors.shadow.withValues(alpha: 0.12),
      blurRadius: 32,
      offset: const Offset(0, 12),
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
    required this.raised,
    required this.ink,
    required this.onPrimary,
    required this.ink2,
    required this.muted,
    required this.hairline,
    required this.outline,
    required this.brandTint,
    required this.hero,
    required this.onHero,
    required this.brand,
    required this.know,
    required this.onKnow,
    required this.knowDot,
    required this.dontKnow,
    required this.dontKnowText,
    required this.onDontKnowText,
    required this.depth,
    required this.shadow,
    required this.tintBlue,
    required this.tintAmber,
    required this.tintGreen,
    required this.tintRed,
  });

  /// Light tokens: navy ink on white surfaces over a pale blue-grey ground.
  static const light = AppColors(
    ground: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    ink: Color(0xFF1F2A44),
    onPrimary: Color(0xFFFFFFFF),
    ink2: Color(0xFF4A5470),
    muted: Color(0xFF687187),
    hairline: Color(0xFFE3E7EF),
    outline: Color(0xFFD5DBE7),
    brandTint: Color(0xFFE8ECF5),
    hero: Color(0xFF1F2A44),
    onHero: Color(0xFFFFFFFF),
    brand: Color(0xFF1F2A44),
    know: Color(0xFF1D8054),
    onKnow: Color(0xFFFFFFFF),
    knowDot: Color(0xFF2BA16A),
    dontKnow: Color(0xFFE2574A),
    dontKnowText: Color(0xFFC2402F),
    onDontKnowText: Color(0xFFFFFFFF),
    depth: Color(0xFFF4F6FA),
    shadow: Color(0xFF1F2A44),
    tintBlue: Color(0xFFE8ECF5),
    tintAmber: Color(0xFFFFF1D6),
    tintGreen: Color(0xFFE3F4EC),
    tintRed: Color(0xFFFCE8E6),
  );

  /// Dark tokens: pale ink on navy surfaces, the primary fill inverted, and
  /// the greens and reds lightened to meet WCAG AA on [surface].
  static const dark = AppColors(
    ground: Color(0xFF0E1424),
    surface: Color(0xFF18203A),
    raised: Color(0xFF232D4D),
    ink: Color(0xFFEEF1F7),
    onPrimary: Color(0xFF1F2A44),
    ink2: Color(0xFFB5BED3),
    muted: Color(0xFF9AA3BA),
    hairline: Color(0xFF2A3352),
    outline: Color(0xFF2E3858),
    brandTint: Color(0xFF2A3560),
    hero: Color(0xFF232D4D),
    onHero: Color(0xFFFFFFFF),
    brand: Color(0xFF1F2A44),
    know: Color(0xFF5ED39A),
    onKnow: Color(0xFF0E1424),
    knowDot: Color(0xFF5ED39A),
    dontKnow: Color(0xFFFF8577),
    dontKnowText: Color(0xFFFF8577),
    onDontKnowText: Color(0xFF0E1424),
    depth: Color(0xFF0E1424),
    shadow: Color(0xFF000000),
    tintBlue: Color(0xFF2A3560),
    tintAmber: Color(0xFF4A3B1E),
    tintGreen: Color(0xFF1E3F33),
    tintRed: Color(0xFF4A2624),
  );

  /// The screen's background, under every surface.
  final Color ground;

  /// Cards, rows, sheets and bars.
  final Color surface;

  /// A surface raised over [surface], such as a study card in the dark theme.
  final Color raised;

  /// Primary text, and the primary fill.
  final Color ink;

  /// Text and icons on the primary fill, [ink].
  final Color onPrimary;

  /// Text one step quieter than [ink], such as a card's back in a list.
  final Color ink2;

  /// Secondary text.
  final Color muted;

  /// Dividers and the line around a card.
  final Color hairline;

  /// The outline of a secondary button and a field.
  final Color outline;

  /// A quiet brand fill: a chip, an avatar's circle, a mascot's circle.
  final Color brandTint;

  /// The today card's fill.
  final Color hero;

  /// Text and the button fill on [hero].
  final Color onHero;

  /// The brand navy in both themes: the label of a button on [hero].
  final Color brand;

  /// "Know", as text and icons on [surface] or [ground], and as a fill under [onKnow].
  final Color know;
  final Color onKnow;

  /// A "Know" answer's dot.
  final Color knowDot;

  /// "Don't know", as a dot or a tint; never as text.
  final Color dontKnow;

  /// "Don't know" and destruction, as text on [surface] and as a fill under [onDontKnowText].
  final Color dontKnowText;
  final Color onDontKnowText;

  /// The colour a previous card fades toward, a step per card of depth.
  final Color depth;

  /// The colour of every shadow, before its opacity.
  final Color shadow;

  /// The first of the four deck tile tints.
  final Color tintBlue;

  /// The second deck tile tint.
  final Color tintAmber;

  /// The third deck tile tint.
  final Color tintGreen;

  /// The fourth deck tile tint.
  final Color tintRed;

  /// The four tints a deck's initial tile is drawn on, in order.
  List<Color> get deckTints => [tintBlue, tintAmber, tintGreen, tintRed];

  /// The tokens of [context]'s theme.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (throw StateError('the app theme carries no AppColors'));

  @override
  AppColors copyWith({
    Color? ground,
    Color? surface,
    Color? raised,
    Color? ink,
    Color? onPrimary,
    Color? ink2,
    Color? muted,
    Color? hairline,
    Color? outline,
    Color? brandTint,
    Color? hero,
    Color? onHero,
    Color? brand,
    Color? know,
    Color? onKnow,
    Color? knowDot,
    Color? dontKnow,
    Color? dontKnowText,
    Color? onDontKnowText,
    Color? depth,
    Color? shadow,
    Color? tintBlue,
    Color? tintAmber,
    Color? tintGreen,
    Color? tintRed,
  }) => AppColors(
    ground: ground ?? this.ground,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    ink: ink ?? this.ink,
    onPrimary: onPrimary ?? this.onPrimary,
    ink2: ink2 ?? this.ink2,
    muted: muted ?? this.muted,
    hairline: hairline ?? this.hairline,
    outline: outline ?? this.outline,
    brandTint: brandTint ?? this.brandTint,
    hero: hero ?? this.hero,
    onHero: onHero ?? this.onHero,
    brand: brand ?? this.brand,
    know: know ?? this.know,
    onKnow: onKnow ?? this.onKnow,
    knowDot: knowDot ?? this.knowDot,
    dontKnow: dontKnow ?? this.dontKnow,
    dontKnowText: dontKnowText ?? this.dontKnowText,
    onDontKnowText: onDontKnowText ?? this.onDontKnowText,
    depth: depth ?? this.depth,
    shadow: shadow ?? this.shadow,
    tintBlue: tintBlue ?? this.tintBlue,
    tintAmber: tintAmber ?? this.tintAmber,
    tintGreen: tintGreen ?? this.tintGreen,
    tintRed: tintRed ?? this.tintRed,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return AppColors(
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      ink: mix(ink, other.ink),
      onPrimary: mix(onPrimary, other.onPrimary),
      ink2: mix(ink2, other.ink2),
      muted: mix(muted, other.muted),
      hairline: mix(hairline, other.hairline),
      outline: mix(outline, other.outline),
      brandTint: mix(brandTint, other.brandTint),
      hero: mix(hero, other.hero),
      onHero: mix(onHero, other.onHero),
      brand: mix(brand, other.brand),
      know: mix(know, other.know),
      onKnow: mix(onKnow, other.onKnow),
      knowDot: mix(knowDot, other.knowDot),
      dontKnow: mix(dontKnow, other.dontKnow),
      dontKnowText: mix(dontKnowText, other.dontKnowText),
      onDontKnowText: mix(onDontKnowText, other.onDontKnowText),
      depth: mix(depth, other.depth),
      shadow: mix(shadow, other.shadow),
      tintBlue: mix(tintBlue, other.tintBlue),
      tintAmber: mix(tintAmber, other.tintAmber),
      tintGreen: mix(tintGreen, other.tintGreen),
      tintRed: mix(tintRed, other.tintRed),
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
    onPrimary: colors.onPrimary,
    secondary: colors.ink2,
    onSecondary: colors.surface,
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
    outline: colors.outline,
    outlineVariant: colors.hairline,
    shadow: colors.shadow,
    inverseSurface: colors.ink,
    onInverseSurface: colors.onPrimary,
  );
  final control = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
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
    // Stroke icons in place of Material's back and close glyphs.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(LucideIcons.chevronLeft),
      closeButtonIconBuilder: (_) => const Icon(LucideIcons.x),
    ),
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
        side: BorderSide(color: colors.outline),
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
      prefixIconColor: colors.muted,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s16,
        vertical: AppSpace.s12,
      ),
      border: _fieldBorder(colors.outline, 1),
      enabledBorder: _fieldBorder(colors.outline, 1),
      focusedBorder: _fieldBorder(colors.ink, 2),
      errorBorder: _fieldBorder(colors.dontKnowText, 1),
      focusedErrorBorder: _fieldBorder(colors.dontKnowText, 2),
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
        selectedForegroundColor: colors.onPrimary,
        selectedBackgroundColor: colors.ink,
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.outline),
        shape: control,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: control,
      contentTextStyle: AppType.secondary.copyWith(color: colors.onPrimary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      textStyle: AppType.body.copyWith(color: colors.ink),
      shape: control,
    ),
  );
}

/// A field's rounded border in [color], [width] pixels wide.
OutlineInputBorder _fieldBorder(Color color, double width) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );

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
