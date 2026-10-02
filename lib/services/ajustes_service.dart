import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de accesibilidad/visualización persistidas localmente:
/// tamaño de letra (afecta a toda la app vía TextScaler en main.dart),
/// tamaño de los iconos de asignatura (cuadrícula tipo escritorio) y
/// si se pide confirmación antes de cerrar sesión.
class AjustesService extends ChangeNotifier {
  static const _claveEscalaFuente = 'ajustes_escala_fuente';
  static const _claveEscalaIconos = 'ajustes_escala_iconos';
  static const _claveConfirmarCierreSesion = 'ajustes_confirmar_cierre_sesion';
  static const _claveCarpetaExportacionMarcajes = 'ajustes_carpeta_exportacion_marcajes';
  static const _claveUltimaExportacionMarcajesMes = 'ajustes_ultima_exportacion_marcajes_mes';
  static const _claveIdioma = 'ajustes_idioma';
  static const _claveAsistenteUrl = 'ajustes_asistente_url';
  static const _claveBienvenidaVista = 'ajustes_bienvenida_vista';

  static const double escalaFuenteMinima = 0.85;
  static const double escalaFuenteMaxima = 1.6;
  static const double escalaIconosMinima = 0.8;
  static const double escalaIconosMaxima = 1.4;

  double _escalaFuente = 1.0;
  double _escalaIconos = 1.0;
  bool _confirmarCierreSesion = true;
  // Carpeta local (dart:io) donde se guarda automáticamente el Excel
  // de fichajes del mes anterior al abrir la app — ver
  // ExportacionAutomaticaMarcajesService. '' = no configurada, la
  // exportación automática no hace nada. Solo tiene sentido en
  // escritorio (macOS/Windows/Linux), nunca en web.
  String _carpetaExportacionMarcajes = '';
  // 'yyyy-MM' del último mes ya exportado, para no repetir la
  // comprobación/escritura en cada apertura de la app.
  String _ultimaExportacionMarcajesMes = '';
  // Solo 'es'/'ca' (ver CLAUDE.md: infraestructura completa, pero solo
  // login/menú/inicio/fichar/grabar/ajustes están traducidos — el
  // resto de la app se ve siempre en castellano sea cual sea este
  // valor).
  Locale _idioma = const Locale('es');
  // URL del backend propio del asistente de Claude (ver CLAUDE.md): NO
  // es la clave de la API de Anthropic (esa vive solo en ese servidor,
  // nunca en la app) — es el endpoint HTTP al que la app envía el
  // mensaje del usuario y del que espera de vuelta una respuesta. '' =
  // sin configurar, el botón del asistente avisa de que falta montar
  // el servidor. Dirección-only, configurable desde Ajustes.
  String _asistenteUrl = '';
  // Tarjeta de bienvenida de Inicio ya cerrada en este dispositivo.
  // Hasta que se cargan las preferencias se considera vista, para que
  // la tarjeta no aparezca un instante y desaparezca.
  bool _bienvenidaVista = true;

  bool get bienvenidaVista => _bienvenidaVista;
  double get escalaFuente => _escalaFuente;
  double get escalaIconos => _escalaIconos;
  bool get confirmarCierreSesion => _confirmarCierreSesion;
  String get carpetaExportacionMarcajes => _carpetaExportacionMarcajes;
  String get ultimaExportacionMarcajesMes => _ultimaExportacionMarcajesMes;
  Locale get idioma => _idioma;
  String get asistenteUrl => _asistenteUrl;

  AjustesService() {
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _escalaFuente = prefs.getDouble(_claveEscalaFuente) ?? 1.0;
    _escalaIconos = prefs.getDouble(_claveEscalaIconos) ?? 1.0;
    _confirmarCierreSesion = prefs.getBool(_claveConfirmarCierreSesion) ?? true;
    _carpetaExportacionMarcajes = prefs.getString(_claveCarpetaExportacionMarcajes) ?? '';
    _ultimaExportacionMarcajesMes = prefs.getString(_claveUltimaExportacionMarcajesMes) ?? '';
    _idioma = Locale(prefs.getString(_claveIdioma) ?? 'es');
    _asistenteUrl = prefs.getString(_claveAsistenteUrl) ?? '';
    _bienvenidaVista = prefs.getBool(_claveBienvenidaVista) ?? false;
    notifyListeners();
  }

  Future<void> cambiarBienvenidaVista(bool vista) async {
    _bienvenidaVista = vista;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveBienvenidaVista, vista);
  }

  Future<void> cambiarAsistenteUrl(String url) async {
    _asistenteUrl = url.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveAsistenteUrl, _asistenteUrl);
  }

  Future<void> cambiarIdioma(Locale idioma) async {
    _idioma = idioma;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveIdioma, idioma.languageCode);
  }

  Future<void> cambiarEscalaFuente(double valor) async {
    _escalaFuente = valor.clamp(escalaFuenteMinima, escalaFuenteMaxima);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_claveEscalaFuente, _escalaFuente);
  }

  Future<void> cambiarEscalaIconos(double valor) async {
    _escalaIconos = valor.clamp(escalaIconosMinima, escalaIconosMaxima);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_claveEscalaIconos, _escalaIconos);
  }

  Future<void> cambiarConfirmarCierreSesion(bool valor) async {
    _confirmarCierreSesion = valor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveConfirmarCierreSesion, valor);
  }

  Future<void> cambiarCarpetaExportacionMarcajes(String ruta) async {
    _carpetaExportacionMarcajes = ruta;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveCarpetaExportacionMarcajes, ruta);
  }

  Future<void> registrarExportacionMarcajesRealizada(String mesIso) async {
    _ultimaExportacionMarcajesMes = mesIso;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUltimaExportacionMarcajesMes, mesIso);
  }

  Future<void> restablecer() async {
    await cambiarEscalaFuente(1.0);
    await cambiarEscalaIconos(1.0);
    await cambiarConfirmarCierreSesion(true);
    await cambiarIdioma(const Locale('es'));
  }
}
