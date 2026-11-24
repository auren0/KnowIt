import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/screens/home_screen.dart';
import 'package:knowit/services/settings_service.dart';

class Knowit extends StatelessWidget {
  const Knowit({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.notifier,
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KnowIt',
          theme: buildKnowItTheme(
            Brightness.light,
            accent: settings.accentColor,
            font: settings.fontFamily,
          ),
          darkTheme: buildKnowItTheme(
            Brightness.dark,
            accent: settings.accentColor,
            font: settings.fontFamily,
          ),
          themeMode: settings.theme.materialMode,
          locale: settings.language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final effectiveScale =
                (media.textScaler.scale(1) * settings.textScale).clamp(
                  0.8,
                  3.0,
                );
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(effectiveScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}

/// Builds the KnowIt design language: warm accent, soft rounded surfaces,
/// Fluent typography and an accessible, responsive type scale.
ThemeData buildKnowItTheme(
  Brightness brightness, {
  AccentColor accent = AccentColor.yellow,
  AppFontFamily font = AppFontFamily.nunito,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent.seed,
    brightness: brightness,
  );
  final radius = BorderRadius.circular(16);
  const fontFallback = ['AppleColorEmoji', 'TwemojiMozilla'];

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: font.family,
    fontFamilyFallback: fontFallback,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
  );

  final textTheme = base.textTheme
      .apply(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
      )
      .copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.15,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.2,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          height: 1.25,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 16,
          height: 1.4,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 14.5,
          height: 1.4,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 12.5,
          height: 1.4,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 66,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: textTheme.headlineMedium?.copyWith(
        color: scheme.onSurface,
        fontSize: 28,
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
      labelStyle: TextStyle(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        color: scheme.onSurfaceVariant,
      ),
      hintStyle: TextStyle(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: TextStyle(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        iconSize: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(
          TextStyle(
            fontFamily: font.family,
            fontFamilyFallback: fontFallback,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        side: WidgetStateProperty.all(BorderSide.none),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: TextStyle(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: font.family,
          fontFamilyFallback: fontFallback,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      labelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: scheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        color: scheme.onSurface,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 10,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: font.family,
        fontFamilyFallback: fontFallback,
        color: scheme.onInverseSurface,
        fontSize: 12,
      ),
    ),
  );
}
