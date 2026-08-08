import 'package:flutter/material.dart';

/// Trackea la profundidad de navegación de TODA la app (un único
/// Navigator raíz, sin Navigators anidados) para poder mostrar un
/// botón flotante "volver al menú" superpuesto en cualquier pantalla,
/// sin tener que tocar el AppBar de cada una una por una (ver
/// CLAUDE.md). `previousRoute == null` identifica el push inicial de
/// la ruta "home" al arrancar la app — no cuenta como profundidad.
class NavegacionObserver extends NavigatorObserver {
  final ValueNotifier<int> profundidad;

  NavegacionObserver(this.profundidad);

  @override
  void didPush(Route route, Route? previousRoute) {
    if (previousRoute != null) profundidad.value++;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (profundidad.value > 0) profundidad.value--;
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (profundidad.value > 0) profundidad.value--;
  }
}
