import 'package:flutter/material.dart';

/// Color de acento de la app: burdeos, a juego con las paredes del
/// centro (el logo en sí es monocromo negro, ver
/// brief_logo_sotto_studio.md, así que este color es libre de elegir
/// a nivel de UI).
const colorMarca = Color(0xFF8C1D40);

ThemeData get temaClaro => _construirTema(
      ColorScheme.fromSeed(seedColor: colorMarca, brightness: Brightness.light),
    );

ThemeData get temaOscuro => _construirTema(
      ColorScheme.fromSeed(seedColor: colorMarca, brightness: Brightness.dark),
    );

ThemeData _construirTema(ColorScheme esquema) {
  final formaCampo = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final formaTarjeta = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: esquema.outlineVariant),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: esquema.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
      elevation: 0,
      scrolledUnderElevation: 4,
      surfaceTintColor: esquema.primary,
      iconTheme: IconThemeData(color: esquema.onPrimary),
      actionsIconTheme: IconThemeData(color: esquema.onPrimary),
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: esquema.onPrimary),
    ),
    // Las TabBar de esta app siempre están en el `bottom:` de un
    // AppBar (fondo burdeos == colorScheme.primary). Sin esto, el
    // color por defecto de la pestaña seleccionada también es
    // `primary` — burdeos sobre burdeos, ilegible.
    tabBarTheme: TabBarThemeData(
      labelColor: esquema.onPrimary,
      unselectedLabelColor: esquema.onPrimary.withValues(alpha: 0.7),
      indicatorColor: esquema.onPrimary,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: formaTarjeta,
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: esquema.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: esquema.outlineVariant, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      shape: formaCampo,
      side: BorderSide(color: esquema.outlineVariant),
    ),
  );
}
