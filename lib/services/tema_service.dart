import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla el modo de tema (claro/oscuro) y lo persiste localmente
/// para que se recuerde entre sesiones.
///
/// Deliberadamente NO ofrece "según el sistema": si el interruptor del
/// menú solo distingue claro/oscuro, dejar el modo en "sistema" podía
/// mostrar la app en oscuro (porque el navegador lo prefiere así)
/// mientras el interruptor seguía marcando "claro" — confuso. Por
/// defecto arranca en claro, siempre explícito.
class TemaService extends ChangeNotifier {
  static const _clavePreferencia = 'modo_tema';

  ThemeMode _modo = ThemeMode.light;
  ThemeMode get modo => _modo;

  TemaService() {
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_clavePreferencia);
    _modo = guardado == 'oscuro' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> cambiarModo(ThemeMode nuevo) async {
    _modo = nuevo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePreferencia, nuevo == ThemeMode.dark ? 'oscuro' : 'claro');
  }
}
