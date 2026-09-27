import 'package:flutter/material.dart';

/// Color de acento de la app: burdeos, a juego con las paredes del
/// centro (el logo en sí es monocromo negro, ver
/// brief_logo_sotto_studio.md, así que este color es libre de elegir
/// a nivel de UI).
const colorMarca = Color(0xFF8C1D40);

/// Latón/bronce (herrajes de instrumento de cuerda, llaves de viento) —
/// rol `secondary` del ColorScheme. Sin usos previos de
/// `colorScheme.secondary` en el resto de la app (comprobado), así que
/// fijarlo a mano en vez de dejar que `ColorScheme.fromSeed` lo derive
/// algorítmicamente del burdeos no tiene efectos colaterales.
const _colorLaton = Color(0xFFB08D57);

/// Verde profundo (fieltro de piano, barniz de violonchelo) — rol
/// `tertiary`, mismo razonamiento que el latón.
const _colorFieltro = Color(0xFF3F5C4E);

ThemeData get temaClaro => _construirTema(
      ColorScheme.fromSeed(seedColor: colorMarca, brightness: Brightness.light),
    );

ThemeData get temaOscuro => _construirTema(
      ColorScheme.fromSeed(seedColor: colorMarca, brightness: Brightness.dark),
    );

ThemeData _construirTema(ColorScheme esquemaSemilla) {
  // El burdeos (real, paredes del centro) se conserva tal cual; el
  // resto de la identidad —latón/fieltro en vez de los tonos que
  // `fromSeed` habría derivado en solitario del burdeos— es una
  // elección deliberada, no la salida por defecto del algoritmo.
  final esquema = esquemaSemilla.copyWith(
    secondary: _colorLaton,
    onSecondary: Colors.white,
    secondaryContainer: _colorLaton.withValues(alpha: 0.16),
    onSecondaryContainer: esquemaSemilla.onSurface,
    tertiary: _colorFieltro,
    onTertiary: Colors.white,
    tertiaryContainer: _colorFieltro.withValues(alpha: 0.16),
    onTertiaryContainer: esquemaSemilla.onSurface,
  );

  // Radios más ajustados que el "todo-pastilla" por defecto de
  // Material — una app de conservatorio no necesita leer como un kit
  // de tarjetas SaaS; el grosor de los propios trazos (divisores,
  // bordes) hace más trabajo visual que el redondeo.
  const radioCampo = 8.0;
  const radioTarjeta = 6.0;
  const radioBoton = 8.0;
  const radioDialogo = 14.0;

  final formaCampo = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioCampo));
  final formaTarjeta = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radioTarjeta),
    side: BorderSide(color: esquema.outlineVariant),
  );

  // Misma base de Material 3 que antes (implícita al pasar solo
  // `colorScheme`), con pesos/tracking retocados a mano: titulares más
  // apretados (más "grabado", menos suelto-genérico) y las etiquetas
  // de botón con algo más de aire en vez de VERSALITAS.
  final tipoBase = ThemeData(useMaterial3: true, colorScheme: esquema).textTheme;
  final tipografia = tipoBase.copyWith(
    headlineMedium: tipoBase.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    headlineSmall: tipoBase.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: tipoBase.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: tipoBase.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: tipoBase.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: tipoBase.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    textTheme: tipografia,
    scaffoldBackgroundColor: esquema.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
      elevation: 0,
      scrolledUnderElevation: 4,
      surfaceTintColor: esquema.primary,
      iconTheme: IconThemeData(color: esquema.onPrimary),
      actionsIconTheme: IconThemeData(color: esquema.onPrimary),
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: esquema.onPrimary),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioBoton)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioBoton)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: esquema.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radioCampo), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radioCampo), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioCampo),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioCampo)),
    ),
    dividerTheme: DividerThemeData(color: esquema.outlineVariant, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioDialogo)),
    ),
    chipTheme: ChipThemeData(
      shape: formaCampo,
      side: BorderSide(color: esquema.outlineVariant),
    ),
  );
}
