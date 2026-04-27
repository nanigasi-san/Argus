import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const _fontFamily = 'Noto Sans JP';
  static const _fontFallback = <String>[
    'Noto Sans CJK JP',
    'Yu Gothic',
    'Meiryo',
    'Hiragino Sans',
    'Roboto',
  ];

  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    );
  }
}
