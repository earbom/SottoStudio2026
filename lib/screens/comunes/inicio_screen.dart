import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

/// Pantalla de bienvenida tras el login. No depende del permiso del
/// usuario: el acceso a cada sección (informe, cursos, mi estudio...)
/// sigue estando en el menú lateral (ver home_shell.dart).
///
/// Para alumnos, muestra avisos in-app (no son notificaciones push del
/// sistema — eso requiere una Cloud Function server-side y sigue
/// bloqueado por el plan Blaze, ver CLAUDE.md): notas nuevas desde la
/// última visita y aviso si llevan varios días sin estudiar.
class InicioScreen extends StatefulWidget {
  final Usuario perfil;

  const InicioScreen({super.key, required this.perfil});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  final _db = DbService();
  static const _diasSinEstudiarAviso = 3;
  int? _notasNuevas;
  int? _diasSinEstudiar;

  @override
  void initState() {
    super.initState();
    _cargarAvisos();
  }

  Future<void> _cargarAvisos() async {
    if (!widget.perfil.esAlumno) return;

    final anterior = await _db.registrarVisitaYObtenerAnterior(widget.perfil.uid);
    int? notasNuevas;
    int? diasSinEstudiar;

    if (anterior != null) {
      final notas = await _db.notasDeAlumno(widget.perfil.uid).first;
      final n = notas.where((n) => n.fecha.isAfter(anterior)).length;
      if (n > 0) notasNuevas = n;
    }

    final historial = await _db.historialAlumno(widget.perfil.uid).first;
    if (historial.isNotEmpty) {
      final dias = DateTime.now().difference(historial.first.fechaInicio).inDays;
      if (dias >= _diasSinEstudiarAviso) diasSinEstudiar = dias;
    }

    if (!mounted) return;
    setState(() {
      _notasNuevas = notasNuevas;
      _diasSinEstudiar = diasSinEstudiar;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final esquema = Theme.of(context).colorScheme;
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final avisos = [
      if (_notasNuevas != null) l10n.inicioNotasNuevas(_notasNuevas!),
      if (_diasSinEstudiar != null) l10n.inicioDiasSinEstudiar(_diasSinEstudiar!),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [esquema.surface, esquema.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: esOscuro
                      // El logo es monocromo negro sobre fondo
                      // transparente: para que se vea en modo oscuro
                      // se tiñe de blanco (no es un "invertir" real de
                      // la imagen, solo recolorea los píxeles opacos).
                      ? ColorFiltered(
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          child: Image.asset('assets/images/cropped-Haro-sin-fondo-logo-1-e1680519499133-2048x891.png'),
                        )
                      : Image.asset('assets/images/cropped-Haro-sin-fondo-logo-1-e1680519499133-2048x891.png'),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.inicioSaludo(widget.perfil.nombre),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: esquema.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.inicioElegirSeccion,
                  style: TextStyle(color: esquema.onSurfaceVariant),
                ),
                if (avisos.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      children: avisos
                          .map((aviso) => Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: esquema.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.notifications_outlined, size: 20, color: esquema.onTertiaryContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(aviso, style: TextStyle(color: esquema.onTertiaryContainer)),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
