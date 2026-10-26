import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  /// A pull-down menu, such as a photo import section's form menu.
  static const menu = 13.0;
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

  /// The tick inside a row's round check, such as a photo import row's.
  static const checkIcon = 14.0;

  /// A first-use coach's finger over the card it demonstrates on.
  static const coachFinger = 34.0;

  /// The blur of the shadow that lifts a coach's finger off the card.
  static const coachFingerBlur = 6.0;

  /// A coach's step dot, and its height when it is the current step's.
  static const coachDot = 6.0;

  /// The current step's dot, drawn long.
  static const coachDotCurrent = 16.0;

  /// How high a pull-down menu floats, which sets its shadow.
  static const menuElevation = 12.0;

  /// The horizontal lockup's height in the home screen's top bar.
  static const lockupHeight = 30.0;

  /// The stacked lockup's width on the sign-in screen.
  static const stackedLockupWidth = 200.0;

  /// The mascot's circle on the empty home screen.
  static const mascotLarge = 128.0;

  /// The mascot's circle on the study completion card.
  static const mascotMedium = 84.0;

  /// The mascot on the 오늘 tab's backlog card.
  static const mascotGuide = 64.0;

  /// The mascot in the account screen's footer.
  static const mascotSmall = 28.0;

  /// The symbol in the today card's corner.
  static const heroSymbol = 120.0;

  /// The study progress bar's thickness.
  static const progress = 8.0;
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

  /// A study card's front: 30/38, extra bold.
  static const front = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  /// A study card's back: 20/28, semibold.
  static const back = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );

  /// The smallest a card's front and back shrink to so they fit their
  /// half.
  static const frontFloor = 18.0;
  static const backFloor = 15.0;

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
    required this.dontKnow,
    required this.dontKnowText,
    required this.onDontKnowText,
    required this.shadow,
    required this.tintBlue,
    required this.tintAmber,
    required this.tintGreen,
    required this.tintRed,
    required this.knowCard,
    required this.knowLine,
    required this.onKnowTint,
    required this.dontKnowCard,
    required this.dontKnowLine,
    required this.onDontKnowTint,
    required this.streak,
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
    dontKnow: Color(0xFFE2574A),
    dontKnowText: Color(0xFFC2402F),
    onDontKnowText: Color(0xFFFFFFFF),
    shadow: Color(0xFF1F2A44),
    tintBlue: Color(0xFFE8ECF5),
    tintAmber: Color(0xFFFFF1D6),
    tintGreen: Color(0xFFE3F4EC),
    tintRed: Color(0xFFFCE8E6),
    knowCard: Color(0xFFEAF6EF),
    knowLine: Color(0xFF9ED3B6),
    onKnowTint: Color(0xFF1D6B47),
    dontKnowCard: Color(0xFFFCEEEC),
    dontKnowLine: Color(0xFFEBB3AA),
    onDontKnowTint: Color(0xFFB03A2B),
    streak: Color(0xFFC26A0A),
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
    dontKnow: Color(0xFFFF8577),
    dontKnowText: Color(0xFFFF8577),
    onDontKnowText: Color(0xFF0E1424),
    shadow: Color(0xFF000000),
    tintBlue: Color(0xFF2A3560),
    tintAmber: Color(0xFF4A3B1E),
    tintGreen: Color(0xFF1E3F33),
    tintRed: Color(0xFF4A2624),
    knowCard: Color(0xFF17302A),
    knowLine: Color(0xFF2E6B50),
    onKnowTint: Color(0xFF5ED39A),
    dontKnowCard: Color(0xFF3A1F24),
    dontKnowLine: Color(0xFF7A3A36),
    onDontKnowTint: Color(0xFFFF8577),
    streak: Color(0xFFF5A623),
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

  /// The study coach's fill and the study screen's notice.
  final Color hero;

  /// Text and the button fill on [hero].
  final Color onHero;

  /// The brand navy in both themes: the label of a button on [hero].
  final Color brand;

  /// "Know", as text and icons on [surface] or [ground], and as a fill under [onKnow].
  final Color know;
  final Color onKnow;

  /// "Don't know", as the tint over a dragged card; never as text.
  final Color dontKnow;

  /// "Don't know" and destruction, as text on [surface] and as a fill under [onDontKnowText].
  final Color dontKnowText;
  final Color onDontKnowText;

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

  /// A previous card answered "Know": its fill and its line.
  final Color knowCard;
  final Color knowLine;

  /// "Know" as text on [tintGreen], the tint behind a card dragged toward it.
  final Color onKnowTint;

  /// A previous card answered "Don't know": its fill and its line.
  final Color dontKnowCard;
  final Color dontKnowLine;

  /// "Don't know" as text on [tintRed], the tint behind a card dragged toward
  /// it.
  final Color onDontKnowTint;

  /// The streak flame's body, on the 오늘 tab and the completion card.
  final Color streak;

  /// The streak flame's line at its first stage, before it takes [streak].
  Color get flameOutline => muted;

  /// The streak flame's warm core, from its fourth stage: [streak] halfway
  /// toward [onHero], so the web's token set needs no flame of its own.
  Color get flameCore => Color.lerp(streak, onHero, 0.5)!;

  /// The streak flame's glow, from its fourth stage.
  Color get flameGlow => streak.withValues(alpha: 0.35);

  /// The four tints a deck's initial tile is drawn on, in order.
  List<Color> get deckTints => [tintBlue, tintAmber, tintGreen, tintRed];

  /// A chart's bar that is not the one it stresses: [color] a step back, ink's
  /// still 3:1 on the surface. Derived, so no token holds it.
  static Color quiet(Color color) => color.withValues(alpha: 0.55);

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
    Color? dontKnow,
    Color? dontKnowText,
    Color? onDontKnowText,
    Color? shadow,
    Color? tintBlue,
    Color? tintAmber,
    Color? tintGreen,
    Color? tintRed,
    Color? knowCard,
    Color? knowLine,
    Color? onKnowTint,
    Color? dontKnowCard,
    Color? dontKnowLine,
    Color? onDontKnowTint,
    Color? streak,
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
    dontKnow: dontKnow ?? this.dontKnow,
    dontKnowText: dontKnowText ?? this.dontKnowText,
    onDontKnowText: onDontKnowText ?? this.onDontKnowText,
    shadow: shadow ?? this.shadow,
    tintBlue: tintBlue ?? this.tintBlue,
    tintAmber: tintAmber ?? this.tintAmber,
    tintGreen: tintGreen ?? this.tintGreen,
    tintRed: tintRed ?? this.tintRed,
    knowCard: knowCard ?? this.knowCard,
    knowLine: knowLine ?? this.knowLine,
    onKnowTint: onKnowTint ?? this.onKnowTint,
    dontKnowCard: dontKnowCard ?? this.dontKnowCard,
    dontKnowLine: dontKnowLine ?? this.dontKnowLine,
    onDontKnowTint: onDontKnowTint ?? this.onDontKnowTint,
    streak: streak ?? this.streak,
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
      dontKnow: mix(dontKnow, other.dontKnow),
      dontKnowText: mix(dontKnowText, other.dontKnowText),
      onDontKnowText: mix(onDontKnowText, other.onDontKnowText),
      shadow: mix(shadow, other.shadow),
      tintBlue: mix(tintBlue, other.tintBlue),
      tintAmber: mix(tintAmber, other.tintAmber),
      tintGreen: mix(tintGreen, other.tintGreen),
      tintRed: mix(tintRed, other.tintRed),
      knowCard: mix(knowCard, other.knowCard),
      knowLine: mix(knowLine, other.knowLine),
      onKnowTint: mix(onKnowTint, other.onKnowTint),
      dontKnowCard: mix(dontKnowCard, other.dontKnowCard),
      dontKnowLine: mix(dontKnowLine, other.dontKnowLine),
      onDontKnowTint: mix(onDontKnowTint, other.onDontKnowTint),
      streak: mix(streak, other.streak),
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
    // On, the navy track; off, a muted thumb and outline, each at least 3:1
    // on the ground.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onPrimary
            : colors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colors.ink : colors.surface,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colors.ink : colors.muted,
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
    // A pull-down menu: rounded, softly shadowed, with items at least a tap
    // target high, unlike Material's dropdown.
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(colors.shadow),
        elevation: const WidgetStatePropertyAll(AppSize.menuElevation),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.menu)),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(colors.ink),
        iconColor: WidgetStatePropertyAll(colors.ink),
        textStyle: WidgetStatePropertyAll(AppType.body),
        minimumSize: const WidgetStatePropertyAll(Size(0, AppSize.tapTarget)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpace.s16),
        ),
      ),
    ),
  );
}

/// A field's rounded border in [color], [width] pixels wide.
OutlineInputBorder _fieldBorder(Color color, double width) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
