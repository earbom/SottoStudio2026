import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';

/// Modo desarrollador: qué permiso simular en la UI (solo tiene efecto
/// para la cuenta con `esDesarrollador`, ver CLAUDE.md). `null` = "sin
/// simular", ver la app con todos los permisos reales. Persistido
/// localmente (no por cuenta remota): si Edgar prueba en dos
/// dispositivos, cada uno recuerda su propia vista simulada.
class VistaPruebaService extends ChangeNotifier {
  static const _claveVistaSimulada = 'vista_prueba_permiso_simulado';

  Permiso? _vistaSimulada;
  Permiso? get vistaSimulada => _vistaSimulada;

  VistaPruebaService() {
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_claveVistaSimulada);
    _vistaSimulada = guardado == null ? null : permisoDesdeTexto(guardado);
    notifyListeners();
  }

  Future<void> cambiarVista(Permiso? nueva) async {
    _vistaSimulada = nueva;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (nueva == null) {
      await prefs.remove(_claveVistaSimulada);
    } else {
      await prefs.setString(_claveVistaSimulada, nueva.name);
    }
  }
}
