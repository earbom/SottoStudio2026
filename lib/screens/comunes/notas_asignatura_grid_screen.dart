import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/matricula.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/validacion_nota.dart';
import '../../widgets/error_carga.dart';
import 'alumno_en_asignatura_screen.dart';

/// Cuadrícula de notas de una asignatura: filas = alumnos
/// matriculados, columnas = criterios de evaluación configurados por
/// dirección, celdas = la nota MÁS RECIENTE de ese alumno en ese
/// criterio (el modelo permite varias notas por alumno+criterio a lo
/// largo del tiempo — no hay un valor único garantizado, así que se
/// muestra la última y se ofrece ver el histórico completo si hay más
/// de una). Pensada para comparar de un vistazo entre todos los
/// alumnos de la asignatura, en vez de entrar uno a uno.
class NotasAsignaturaGridScreen extends StatelessWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;

  const NotasAsignaturaGridScreen({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notas · ${asignatura.nombre}'),
        actions: [
          if (perfil.esProfesor || perfil.esDireccion)
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Cuándo ve el alumno sus notas',
              onPressed: () => _configurarRetraso(context),
            ),
        ],
      ),
      body: CuerpoNotasAsignatura(
        asignatura: asignatura,
        perfil: perfil,
        cursoEscolar: cursoEscolar,
      ),
    );
  }

  Future<void> _configurarRetraso(BuildContext context) async {
    final ctrl = TextEditingController(
      text: asignatura.diasRetrasoVisibilidadNotas > 0
          ? '${asignatura.diasRetrasoVisibilidadNotas}'
          : '',
    );
    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retraso de visibilidad de notas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Días que tardará una nota nueva en verla el alumno, desde que se pone. '
              '0 = visible al momento. Tú y dirección siempre la veis al momento.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Días de retraso'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    final dias = int.tryParse(ctrl.text.trim()) ?? 0;
    await DbService().actualizarAsignatura(
        asignatura.id!, {'diasRetrasoVisibilidadNotas': dias});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retraso de visibilidad guardado.')));
    }
  }
}

/// Cuerpo reutilizable (sin Scaffold/AppBar propios) — ver el mismo
/// patrón en `CuerpoAsistenciasAsignatura`. Reutilizable tal cual
/// dentro de `VistaGlobalAsignaturaScreen`: ya está montado sobre
/// `SingleChildScrollView` anidados, no un `ListView`/`Expanded`, así
/// que no necesita ningún flag especial para vivir dentro de otro
/// scroll vertical.
class CuerpoNotasAsignatura extends StatelessWidget {
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;

  const CuerpoNotasAsignatura({
    super.key,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
  });

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return StreamBuilder<List<CriterioEvaluacion>>(
      stream: db.criteriosDeAsignatura(asignatura.id!),
      builder: (context, snapCriterios) {
        if (snapCriterios.hasError) {
          return const ErrorCarga();
        }
        if (!snapCriterios.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final criterios = snapCriterios.data!;
        if (criterios.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Dirección aún no ha definido criterios de evaluación para esta asignatura.'),
            ),
          );
        }
        return StreamBuilder<List<Matricula>>(
          stream: db.matriculasDeAsignatura(asignatura.id!,
              cursoEscolar: cursoEscolar),
          builder: (context, snapMatriculas) {
            if (snapMatriculas.hasError) {
              return const ErrorCarga();
            }
            if (!snapMatriculas.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Mismo criterio de alcance que _FilaMatricula en
            // asignatura_detalle_screen.dart: con el permiso cruzado
            // entre cursos (ver CLAUDE.md), cualquier profesor de esta
            // asignatura ve a TODOS los matriculados, no solo a los que
            // matriculas.profesorId le fija (informativo desde ahora).
            final matriculas = snapMatriculas.data!;
            if (matriculas.isEmpty) {
              return const Center(
                child: Text('Aún no hay alumnos matriculados.'),
              );
            }
            return FutureBuilder<List<Usuario?>>(
              future: Future.wait(
                  matriculas.map((m) => db.obtenerUsuario(m.alumnoId))),
              builder: (context, snapAlumnos) {
                if (snapAlumnos.hasError) {
                  return const ErrorCarga();
                }
                if (!snapAlumnos.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final alumnos = snapAlumnos.data!.whereType<Usuario>().toList()
                  ..sort((a, b) => a.nombre.compareTo(b.nombre));
                return StreamBuilder<List<Nota>>(
                  stream: db.notasDeAsignatura(asignatura.id!),
                  builder: (context, snapNotas) {
                    if (snapNotas.hasError) {
                      return const ErrorCarga();
                    }
                    if (!snapNotas.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _Cuadricula(
                      db: db,
                      asignatura: asignatura,
                      perfil: perfil,
                      cursoEscolar: cursoEscolar,
                      alumnos: alumnos,
                      criterios: criterios,
                      notas: snapNotas.data!,
                      puedeGestionar: perfil.esProfesor || perfil.esDireccion,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Cuadricula extends StatelessWidget {
  final DbService db;
  final Asignatura asignatura;
  final Usuario perfil;
  final String cursoEscolar;
  final List<Usuario> alumnos;
  final List<CriterioEvaluacion> criterios;
  final List<Nota> notas;
  final bool puedeGestionar;

  const _Cuadricula({
    required this.db,
    required this.asignatura,
    required this.perfil,
    required this.cursoEscolar,
    required this.alumnos,
    required this.criterios,
    required this.notas,
    required this.puedeGestionar,
  });

  Future<void> _tocarCelda(
      BuildContext context, Usuario alumno, CriterioEvaluacion criterio) async {
    final delAlumnoYCriterio = notas
        .where((n) => n.alumnoId == alumno.uid && n.criterioId == criterio.id)
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

    if (delAlumnoYCriterio.length > 1) {
      // Hay histórico: dejar elegir entre añadir una nueva o ver el
      // historial completo en vez de asumir cuál quiere el profesor.
      final accion = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('${alumno.nombre} · ${criterio.nombre}'),
          children: [
            if (puedeGestionar)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'nueva'),
                child: const Text('Añadir una nota nueva'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'historial'),
              child: const Text('Ver histórico completo'),
            ),
          ],
        ),
      );
      if (accion == 'historial') {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlumnoEnAsignaturaScreen(
              alumno: alumno,
              asignatura: asignatura,
              perfil: perfil,
              cursoEscolar: cursoEscolar,
              pestanaInicial: 2,
            ),
          ),
        );
        return;
      }
      if (accion != 'nueva') return;
      if (!context.mounted) return;
    }

    if (!puedeGestionar) {
      if (delAlumnoYCriterio.isEmpty) return;
      // Dirección sin permiso de creación: si ya hay una única nota,
      // llevar directo al histórico en modo lectura.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlumnoEnAsignaturaScreen(
            alumno: alumno,
            asignatura: asignatura,
            perfil: perfil,
            cursoEscolar: cursoEscolar,
            pestanaInicial: 2,
          ),
        ),
      );
      return;
    }

    final valorCtrl = TextEditingController();
    final comentarioCtrl = TextEditingController();
    String? error;
    final valor = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          void guardar() {
            final v = parsearValorNota(valorCtrl.text);
            if (v == null) {
              setStateDialog(() => error = mensajeErrorValorNota);
              return;
            }
            Navigator.pop(context, v);
          }

          return AlertDialog(
            title: Text(
                '${alumno.nombre} · ${criterio.nombre} (${criterio.peso.toStringAsFixed(0)}%)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: valorCtrl,
                  decoration: InputDecoration(
                      labelText: 'Nota (0-10)', errorText: error),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onSubmitted: (_) => guardar(),
                ),
                TextField(
                  controller: comentarioCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Comentario (opcional)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              FilledButton(onPressed: guardar, child: const Text('Guardar')),
            ],
          );
        },
      ),
    );
    if (valor == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await db.crearNota(Nota(
        alumnoId: alumno.uid,
        profesorId: perfil.uid,
        asignaturaId: asignatura.id!,
        criterioId: criterio.id!,
        valor: valor,
        comentario: comentarioCtrl.text.trim(),
        fecha: DateTime.now(),
      ));
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Nota guardada: ${alumno.nombre} · ${valor.toStringAsFixed(1)}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'No se pudo guardar la nota. Comprueba la conexión o que tengas permiso en esta asignatura.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Última nota de cada alumno+criterio, para pintar la celda.
    final ultimaNotaPorCelda = <String, Nota>{};
    for (final n in notas) {
      final clave = '${n.alumnoId}_${n.criterioId}';
      final actual = ultimaNotaPorCelda[clave];
      if (actual == null || n.fecha.isAfter(actual.fecha)) {
        ultimaNotaPorCelda[clave] = n;
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (puedeGestionar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                  'Toca una casilla para poner una nota. «—» = todavía sin nota.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Alumno')),
                for (final criterio in criterios)
                  DataColumn(
                      label: Text(
                          '${criterio.nombre}\n${criterio.peso.toStringAsFixed(0)}%')),
              ],
              rows: [
                for (final alumno in alumnos)
                  DataRow(cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(alumno.nombre),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                      // Abre la ficha del alumno en la pestaña Notas:
                      // ahí se ven todas sus notas y se corrigen/borran.
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AlumnoEnAsignaturaScreen(
                            alumno: alumno,
                            asignatura: asignatura,
                            perfil: perfil,
                            cursoEscolar: cursoEscolar,
                            pestanaInicial: 2,
                          ),
                        ),
                      ),
                    ),
                    for (final criterio in criterios)
                      DataCell(
                        Builder(builder: (context) {
                          final nota = ultimaNotaPorCelda[
                              '${alumno.uid}_${criterio.id}'];
                          return Text(
                            nota == null ? '—' : nota.valor.toStringAsFixed(1),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: nota == null ? Colors.grey : null,
                            ),
                          );
                        }),
                        onTap: () => _tocarCelda(context, alumno, criterio),
                      ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
