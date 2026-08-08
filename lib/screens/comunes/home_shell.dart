import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';
import '../../services/tema_service.dart';
import '../../services/ajustes_service.dart';
import '../../services/exportacion_automatica_marcajes_service.dart';
import '../../widgets/logo_oh.dart';
import '../direccion/cursos_screen.dart';
import '../direccion/alumnos_screen.dart';
import '../direccion/profesorado_screen.dart';
import '../direccion/notas_pendientes_screen.dart';
import '../direccion/asistencia_pendiente_screen.dart';
import '../direccion/informe_direccion_screen.dart';
import '../direccion/registro_horario_screen.dart';
import '../direccion/curso_escolar_screen.dart';
import '../comunes/cuadro_de_honor_screen.dart';
import '../profesor/dashboard_profesor_screen.dart';
import '../alumno/dashboard_alumno_screen.dart';
import 'inicio_screen.dart';
import 'cambiar_password_screen.dart';
import 'afinador_screen.dart';
import 'metronomo_screen.dart';
import 'fichajes_screen.dart';
import 'ajustes_screen.dart';

/// Punto de entrada tras el login: menú lateral construido según los
/// permisos del usuario (pueden combinarse, p.ej. dirección + profesor).
class HomeShell extends StatefulWidget {
  final Usuario perfil;

  const HomeShell({super.key, required this.perfil});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final AuthService _authService = AuthService();
  late Widget _cuerpo;
  late String _tituloActual;

  @override
  void initState() {
    super.initState();
    _cuerpo = InicioScreen(perfil: widget.perfil);
    _tituloActual = 'Haro Estudis Musicals';
    if (widget.perfil.esDireccion) {
      // Best-effort: si falla (carpeta no configurada, sin permisos de
      // escritura...) no debe interrumpir el arranque de la app.
      ExportacionAutomaticaMarcajesService(DbService(), context.read<AjustesService>())
          .comprobarYExportarSiToca()
          .catchError((_) {});
    }
  }

  void _navegarA(String titulo, Widget pantalla) {
    Navigator.pop(context); // cierra el drawer
    setState(() {
      _tituloActual = titulo;
      _cuerpo = pantalla;
    });
  }


  @override
  Widget build(BuildContext context) {
    final perfil = widget.perfil;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const LogoOh(size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(_tituloActual, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const LogoOh(size: 44),
                    const SizedBox(height: 8),
                    Text(
                      perfil.nombre,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    Text(perfil.email, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                  ],
                ),
              ),
              if (perfil.esDireccion) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.menuGestionCentro, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(l10n.menuCursosAsignaturas),
                  onTap: () => _navegarA(l10n.menuCursosAsignaturas, CursosScreen(perfil: perfil)),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(l10n.menuAlumnos),
                  onTap: () => _navegarA(l10n.menuAlumnos, const AlumnosScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.co_present_outlined),
                  title: Text(l10n.menuProfesorado),
                  onTap: () => _navegarA(l10n.menuProfesorado, const ProfesoradoScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: Text(l10n.menuNotasPendientes),
                  onTap: () => _navegarA(l10n.menuNotasPendientes, const NotasPendientesScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(l10n.menuAsistenciaSinMarcar),
                  onTap: () => _navegarA(l10n.menuAsistenciaSinMarcar, const AsistenciaPendienteScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: Text(l10n.menuInformeHoras),
                  onTap: () => _navegarA(l10n.menuInformeHorasTitulo, InformeDireccionScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.punch_clock_outlined),
                  title: Text(l10n.menuRegistroHorario),
                  onTap: () => _navegarA(l10n.menuRegistroHorario, const RegistroHorarioScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: Text(l10n.menuCursoEscolar),
                  onTap: () => _navegarA(l10n.menuCursoEscolar, const CursoEscolarScreen()),
                ),
                const Divider(),
              ],
              if (perfil.esProfesor) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.menuDocencia, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(l10n.menuMisAsignaturas),
                  onTap: () => _navegarA(l10n.menuMisAsignaturas, DashboardProfesorScreen(perfil: perfil)),
                ),
                const Divider(),
              ],
              if (perfil.esAlumno) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.menuMiEstudio, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: Text(l10n.menuMiEstudio),
                  onTap: () => _navegarA(l10n.menuMiEstudio, DashboardAlumnoScreen(perfil: perfil)),
                ),
                const Divider(),
              ],
              if (perfil.esProfesor || perfil.esDireccion) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.menuMiJornadaLaboral, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.punch_clock_outlined),
                  title: Text(l10n.menuFicharEntradaSalida),
                  onTap: () => _navegarA(l10n.menuFicharEntradaSalida, FichajesScreen(perfil: perfil)),
                ),
                const Divider(),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(l10n.menuHerramientas, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l10n.menuAfinador),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AfinadorScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: Text(l10n.menuMetronomo),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MetronomoScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_events_outlined),
                title: Text(l10n.menuCuadroHonor),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CuadroDeHonorScreen(perfil: perfil)));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.menuCambiarContrasena),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CambiarPasswordScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.menuAjustes),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AjustesScreen(perfil: perfil)));
                },
              ),
              Consumer<TemaService>(
                builder: (context, tema, _) => SwitchListTile(
                  secondary: Icon(tema.modo == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
                  title: Text(l10n.menuModoOscuro),
                  value: tema.modo == ThemeMode.dark,
                  onChanged: (activado) => tema.cambiarModo(activado ? ThemeMode.dark : ThemeMode.light),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.menuCerrarSesion),
                onTap: () async {
                  final ajustes = context.read<AjustesService>();
                  if (ajustes.confirmarCierreSesion) {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.menuCerrarSesion),
                        content: Text(l10n.menuCerrarSesionConfirmacion),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(l10n.comunCancelar)),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(l10n.menuCerrarSesion)),
                        ],
                      ),
                    );
                    if (confirmar != true) return;
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await _authService.cerrarSesion();
                },
              ),
            ],
          ),
        ),
      ),
      body: _cuerpo,
    );
  }
}
