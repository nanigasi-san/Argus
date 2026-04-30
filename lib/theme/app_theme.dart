import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._(); // coverage:ignore-line

  static const _fontFamily = 'BIZ UDPGothic';
  static const _fontFallback = <String>[
    'BIZ UDGothic',
    'Yu Gothic UI',
    'Yu Gothic',
    'Meiryo',
    'Hiragino Sans',
    'Noto Sans CJK JP',
    'Roboto',
  ];

  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
    );
    final textTheme = _readableTextTheme(
      base.textTheme.apply(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    );
    final primaryTextTheme = _readableTextTheme(
      base.primaryTextTheme.apply(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: textTheme.headlineSmall,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        floatingLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        helperStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        hintStyle: const TextStyle(fontWeight: FontWeight.w700),
        helperMaxLines: 3,
      ),
    );
  }

  static TextTheme _readableTextTheme(TextTheme source) {
    return source.copyWith(
      displayLarge: _readableStyle(source.displayLarge, FontWeight.w700),
      displayMedium: _readableStyle(source.displayMedium, FontWeight.w700),
      displaySmall: _readableStyle(source.displaySmall, FontWeight.w700),
      headlineLarge: _readableStyle(source.headlineLarge, FontWeight.w700),
      headlineMedium: _readableStyle(source.headlineMedium, FontWeight.w700),
      headlineSmall: _readableStyle(source.headlineSmall, FontWeight.w700),
      titleLarge: _readableStyle(source.titleLarge, FontWeight.w700),
      titleMedium: _readableStyle(source.titleMedium, FontWeight.w700),
      titleSmall: _readableStyle(source.titleSmall, FontWeight.w700),
      bodyLarge: _readableStyle(source.bodyLarge, FontWeight.w700),
      bodyMedium: _readableStyle(source.bodyMedium, FontWeight.w700),
      bodySmall: _readableStyle(source.bodySmall, FontWeight.w700),
      labelLarge: _readableStyle(source.labelLarge, FontWeight.w700),
      labelMedium: _readableStyle(source.labelMedium, FontWeight.w700),
      labelSmall: _readableStyle(source.labelSmall, FontWeight.w700),
    );
  }

  static TextStyle? _readableStyle(TextStyle? style, FontWeight fontWeight) {
    return style?.copyWith(
      fontWeight: fontWeight,
      letterSpacing: 0,
    );
  }
}
