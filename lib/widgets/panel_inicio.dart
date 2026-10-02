import 'package:flutter/material.dart';
import '../models/asignatura.dart';
import '../models/matricula.dart';
import '../models/usuario.dart';
import '../screens/comunes/asistencias_asignatura_screen.dart' show FilaAsistenciaHoy;
import '../screens/direccion/asistencia_pendiente_screen.dart';
import '../screens/direccion/notas_pendientes_screen.dart';
import '../screens/direccion/registro_horario_screen.dart';
import '../services/db_service.dart';

/// Abre una sección dentro de HomeShell (con su título en la barra),
/// igual que si se eligiera desde el menú lateral.
typedef IrASeccion = void Function(String titulo, Widget pantalla);

/// Panel de avisos de dirección en Inicio: lo que tiene pendiente hoy,
/// con un toque para ir directamente. Pensado para que dirección no
/// tenga que recorrer el menú para saber si hay algo que hacer.
class PanelAvisosDireccion extends StatefulWidget {
  final IrASeccion irA;

  const PanelAvisosDireccion({super.key, required this.irA});

  @override
  State<PanelAvisosDireccion> createState() => _PanelAvisosDireccionState();
}

class _PanelAvisosDireccionState extends State<PanelAvisosDireccion> {
  final _db = DbService();
  late final Future<int> _notas = _db.notasFinalesPorValidar().then((r) => r.listas.length);
  late final Future<int> _asistencias = _db.asistenciasSinMarcar().then((r) => r.length);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pendiente de revisar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FutureBuilder<int>(
          future: _notas,
          builder: (context, s) => _TarjetaAviso(
            icono: Icons.rate_review_outlined,
            numero: s.data,
            error: s.hasError,
            texto: (n) => n == 1 ? 'nota final por validar' : 'notas finales por validar',
            onTap: () => widget.irA('Notas pendientes', const NotasPendientesScreen()),
          ),
        ),
        FutureBuilder<int>(
          future: _asistencias,
          builder: (context, s) => _TarjetaAviso(
            icono: Icons.event_busy_outlined,
            numero: s.data,
            error: s.hasError,
            texto: (n) => n == 1
                ? 'clase sin pasar lista (últimos 7 días)'
                : 'clases sin pasar lista (últimos 7 días)',
            onTap: () => widget.irA('Asistencia sin marcar', const AsistenciaPendienteScreen()),
          ),
        ),
        StreamBuilder<int>(
          stream: _db.numeroMarcajesPendientesValidacion(),
          builder: (context, s) => _TarjetaAviso(
            icono: Icons.punch_clock_outlined,
            numero: s.data,
            error: s.hasError,
            texto: (n) => n == 1 ? 'fichaje olvidado por validar' : 'fichajes olvidados por validar',
            onTap: () => widget.irA('Registro horario', const RegistroHorarioScreen()),
          ),
        ),
      ],
    );
  }
}

class _TarjetaAviso extends StatelessWidget {
  final IconData icono;
  final int? numero;
  final bool error;
  final String Function(int n) texto;
  final VoidCallback onTap;

  const _TarjetaAviso({
    required this.icono,
    required this.numero,
    required this.error,
    required this.texto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final hayAlgo = (numero ?? 0) > 0;
    return Card(
      color: hayAlgo ? esquema.tertiaryContainer : null,
      child: ListTile(
        leading: Icon(icono, color: hayAlgo ? esquema.onTertiaryContainer : null),
        title: error
            ? const Text('No se pudo comprobar')
            : numero == null
                ? const Text('Comprobando…')
                : Text(
                    numero == 0 ? 'Nada pendiente: ${texto(2)}' : '$numero ${texto(numero!)}',
                    style: TextStyle(fontWeight: hayAlgo ? FontWeight.bold : FontWeight.normal),
                  ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// "Mis clases de hoy" para profesor: los alumnos con clase HOY según
/// su matrícula (incluidas las asignaturas que cubre hoy como
/// sustituto), ordenados por hora, con los botones de asistencia a la
/// vista — sin tener que entrar asignatura por asignatura.
class ClasesDeHoyProfesor extends StatefulWidget {
  final Usuario perfil;

  const ClasesDeHoyProfesor({super.key, required this.perfil});

  @override
  State<ClasesDeHoyProfesor> createState() => _ClasesDeHoyProfesorState();
}

class _ClasesDeHoyProfesorState extends State<ClasesDeHoyProfesor> {
  final _db = DbService();
  late final Future<List<({Matricula matricula, Asignatura asignatura, String curso})>> _clases = _cargar();

  Future<List<({Matricula matricula, Asignatura asignatura, String curso})>> _cargar() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final asignaturas = await _db.asignaturasVisiblesParaProfesor(widget.perfil.uid).first;
    final hoy = DateTime.now().weekday;
    final resultado = <({Matricula matricula, Asignatura asignatura, String curso})>[];
    for (final asignatura in asignaturas) {
      final matriculas = await _db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar).first;
      final deHoy = matriculas.where((m) => m.diasSemana.contains(hoy)).toList();
      if (deHoy.isEmpty) continue;
      final curso = (await _db.curso(asignatura.cursoId))?.nombre ?? '';
      for (final m in deHoy) {
        resultado.add((matricula: m, asignatura: asignatura, curso: curso));
      }
    }
    resultado.sort((a, b) {
      final ha = a.matricula.horaInicio.isEmpty ? '99:99' : a.matricula.horaInicio;
      final hb = b.matricula.horaInicio.isEmpty ? '99:99' : b.matricula.horaInicio;
      return ha.compareTo(hb);
    });
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mis clases de hoy', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FutureBuilder(
          future: _clases,
          builder: (context, snap) {
            if (snap.hasError) return const Text('No se pudieron cargar las clases de hoy.');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final clases = snap.data!;
            if (clases.isEmpty) {
              return const Card(child: ListTile(title: Text('Hoy no tienes clases programadas.')));
            }
            return Card(
              child: Column(
                children: [
                  for (final c in clases)
                    FilaAsistenciaHoy(
                      key: ValueKey(c.matricula.id),
                      matricula: c.matricula,
                      asignatura: c.asignatura,
                      perfil: widget.perfil,
                      db: _db,
                      detalle: [
                        if (c.matricula.horaInicio.isNotEmpty) '${c.matricula.horaInicio}-${c.matricula.horaFin}',
                        c.asignatura.nombre,
                        if (c.curso.isNotEmpty) c.curso,
                      ].join(' · '),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
