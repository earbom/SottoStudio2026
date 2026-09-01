import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/matricula.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
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
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: Text('Notas · ${asignatura.nombre}')),
      body: StreamBuilder<List<CriterioEvaluacion>>(
        stream: db.criteriosDeAsignatura(asignatura.id!),
        builder: (context, snapCriterios) {
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
            stream: db.matriculasDeAsignatura(asignatura.id!, cursoEscolar: cursoEscolar),
            builder: (context, snapMatriculas) {
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
                future: Future.wait(matriculas.map((m) => db.obtenerUsuario(m.alumnoId))),
                builder: (context, snapAlumnos) {
                  if (!snapAlumnos.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final alumnos = snapAlumnos.data!.whereType<Usuario>().toList()
                    ..sort((a, b) => a.nombre.compareTo(b.nombre));
                  return StreamBuilder<List<Nota>>(
                    stream: db.notasDeAsignatura(asignatura.id!),
                    builder: (context, snapNotas) {
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
      ),
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

  Future<void> _tocarCelda(BuildContext context, Usuario alumno, CriterioEvaluacion criterio) async {
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
    final crear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${alumno.nombre} · ${criterio.nombre} (${criterio.peso.toStringAsFixed(0)}%)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valorCtrl,
              decoration: const InputDecoration(labelText: 'Valor (0-10)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            TextField(
              controller: comentarioCtrl,
              decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (crear != true) return;

    final valor = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
    await db.crearNota(Nota(
      alumnoId: alumno.uid,
      profesorId: perfil.uid,
      asignaturaId: asignatura.id!,
      criterioId: criterio.id!,
      valor: valor,
      comentario: comentarioCtrl.text.trim(),
      fecha: DateTime.now(),
    ));
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Alumno')),
            for (final criterio in criterios)
              DataColumn(label: Text('${criterio.nombre}\n${criterio.peso.toStringAsFixed(0)}%')),
          ],
          rows: [
            for (final alumno in alumnos)
              DataRow(cells: [
                DataCell(Text(alumno.nombre)),
                for (final criterio in criterios)
                  DataCell(
                    Builder(builder: (context) {
                      final nota = ultimaNotaPorCelda['${alumno.uid}_${criterio.id}'];
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
    );
  }
}
