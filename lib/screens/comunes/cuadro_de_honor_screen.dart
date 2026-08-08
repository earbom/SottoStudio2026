import 'package:flutter/material.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

typedef _FilaHonor = ({String alumnoId, String alumnoNombre, String? instrumento, double horasEfectivasMes});

enum _ModoCuadroHonor { global, curso, instrumento }

/// Ranking GLOBAL (no por asignatura) de horas efectivas de estudio de
/// INSTRUMENTO del mes en curso. A diferencia del ranking por
/// asignatura (`RankingAsignaturaScreen`, solo profesor/dirección por
/// privacidad de menores), este es visible para cualquier permiso,
/// incluidos los propios alumnos — es una excepción deliberada, ver
/// CLAUDE.md. Se puede agrupar por instrumento (para cualquiera) o por
/// curso (agrupación reservada a dirección: requiere leer matriculas
/// de TODOS los alumnos vía `cursosPorAlumno()`, y las reglas de
/// `matriculas` no dan ese acceso amplio a alumno ni a profesor).
class CuadroDeHonorScreen extends StatefulWidget {
  final Usuario perfil;

  const CuadroDeHonorScreen({super.key, required this.perfil});

  @override
  State<CuadroDeHonorScreen> createState() => _CuadroDeHonorScreenState();
}

class _CuadroDeHonorScreenState extends State<CuadroDeHonorScreen> {
  final DbService _db = DbService();
  _ModoCuadroHonor _modo = _ModoCuadroHonor.global;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuadro de honor')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                const Text('Horas de estudio de instrumento del mes en curso'),
                const SizedBox(height: 8),
                SegmentedButton<_ModoCuadroHonor>(
                  segments: [
                    const ButtonSegment(value: _ModoCuadroHonor.global, label: Text('Global')),
                    if (widget.perfil.esDireccion)
                      const ButtonSegment(value: _ModoCuadroHonor.curso, label: Text('Por curso')),
                    const ButtonSegment(
                        value: _ModoCuadroHonor.instrumento, label: Text('Por instrumento')),
                  ],
                  selected: {_modo},
                  onSelectionChanged: (s) => setState(() => _modo = s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<_FilaHonor>>(
              stream: _db.cuadroDeHonorMensual(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('No se pudo cargar el cuadro de honor: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final filas = snapshot.data!;
                if (filas.isEmpty) {
                  return const Center(child: Text('Todavía no hay horas de estudio este mes.'));
                }
                switch (_modo) {
                  case _ModoCuadroHonor.global:
                    return _ListaPlana(filas: filas);
                  case _ModoCuadroHonor.instrumento:
                    return _ListaAgrupadaPorInstrumento(filas: filas);
                  case _ModoCuadroHonor.curso:
                    return _ListaAgrupadaPorCurso(db: _db, filas: filas);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaPlana extends StatelessWidget {
  final List<_FilaHonor> filas;
  const _ListaPlana({required this.filas});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: filas.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _filaRanking(context, filas[i], i),
    );
  }
}

Widget _filaRanking(BuildContext context, _FilaHonor fila, int posicion) {
  return ListTile(
    leading: CircleAvatar(
      backgroundColor: posicion < 3 ? Colors.amber.withValues(alpha: 0.3) : null,
      child: Text('${posicion + 1}'),
    ),
    title: Text(fila.alumnoNombre),
    trailing: Text(
      '${fila.horasEfectivasMes.toStringAsFixed(1)} h',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}

class _ListaAgrupadaPorInstrumento extends StatelessWidget {
  final List<_FilaHonor> filas;
  const _ListaAgrupadaPorInstrumento({required this.filas});

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<_FilaHonor>>{};
    for (final fila in filas) {
      final clave = (fila.instrumento == null || fila.instrumento!.isEmpty)
          ? 'Sin instrumento'
          : fila.instrumento!;
      (grupos[clave] ??= []).add(fila);
    }
    final claves = grupos.keys.toList()..sort();
    return ListView(
      children: [
        for (final clave in claves) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(clave,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          for (var i = 0; i < grupos[clave]!.length; i++)
            _filaRanking(context, grupos[clave]![i], i),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ListaAgrupadaPorCurso extends StatelessWidget {
  final DbService db;
  final List<_FilaHonor> filas;
  const _ListaAgrupadaPorCurso({required this.db, required this.filas});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: db.cursoEscolarActivo(),
      builder: (context, snapActivo) {
        if (!snapActivo.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return FutureBuilder<Map<String, List<Curso>>>(
          future: db.cursosPorAlumno(cursoEscolar: snapActivo.data!),
          builder: (context, snapCursos) {
            if (!snapCursos.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final cursosPorAlumno = snapCursos.data!;
            final grupos = <String, ({Curso? curso, List<_FilaHonor> filas})>{};
            for (final fila in filas) {
              final cursos = cursosPorAlumno[fila.alumnoId] ?? const [];
              if (cursos.isEmpty) {
                final actual = grupos['_sin_matricular'];
                grupos['_sin_matricular'] = (
                  curso: null,
                  filas: [...(actual?.filas ?? const []), fila],
                );
                continue;
              }
              for (final curso in cursos) {
                final actual = grupos[curso.id];
                grupos[curso.id!] = (
                  curso: curso,
                  filas: [...(actual?.filas ?? const []), fila],
                );
              }
            }
            final entradas = grupos.values.toList()
              ..sort((a, b) {
                if (a.curso == null) return 1;
                if (b.curso == null) return -1;
                return a.curso!.nivel.index != b.curso!.nivel.index
                    ? a.curso!.nivel.index.compareTo(b.curso!.nivel.index)
                    : (a.curso!.numeroCurso ?? 0).compareTo(b.curso!.numeroCurso ?? 0);
              });
            return ListView(
              children: [
                for (final entrada in entradas) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(entrada.curso?.nombre ?? 'Sin matricular',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  for (var i = 0; i < entrada.filas.length; i++)
                    _filaRanking(context, entrada.filas[i], i),
                  const Divider(height: 1),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
