import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';

typedef _FilaBloque = ({String alumnoId, String alumnoNombre, String asignaturaId, double horasEfectivasMes});

/// Cuadro de Honor: horas efectivas de estudio del mes en curso,
/// agrupadas por curso → asignatura (único criterio, ver CLAUDE.md —
/// se simplificó desde una versión anterior con varios modos y un
/// filtro por curso/asignatura, ya retirados). Visible para cualquier
/// permiso, incluidos los propios alumnos — excepción deliberada del
/// punto 14 (privacidad de nombres), ver CLAUDE.md. No necesita leer
/// `matriculas` (dirección-only): `sesionesEstudio.asignaturaId` ya
/// está denormalizado, así que basta cruzar con `asignaturas`/`cursos`
/// (ambas de lectura abierta).
class CuadroDeHonorScreen extends StatelessWidget {
  final Usuario perfil;

  const CuadroDeHonorScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Cuadro de honor')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text('Horas de estudio del mes en curso'),
          ),
          Expanded(child: _ListaAgrupadaPorBloques(db: db)),
        ],
      ),
    );
  }
}

/// Curso → asignatura, cada bloque coloreado contra el objetivo de ESA
/// asignatura (`Asignatura.horasObjetivoMensual`, ver CLAUDE.md).
class _ListaAgrupadaPorBloques extends StatelessWidget {
  final DbService db;
  const _ListaAgrupadaPorBloques({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_FilaBloque>>(
      stream: db.horasPorAsignaturaMensual(),
      builder: (context, snapFilas) {
        if (snapFilas.hasError) {
          return Center(child: Text('No se pudo cargar el cuadro de honor: ${snapFilas.error}'));
        }
        if (!snapFilas.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final filas = snapFilas.data!;
        if (filas.isEmpty) {
          return const Center(child: Text('Todavía no hay horas de estudio este mes.'));
        }
        return FutureBuilder<(List<Asignatura>, List<Curso>)>(
          future: Future.wait([db.todasLasAsignaturas().first, db.cursos().first]).then(
              (r) => (r[0] as List<Asignatura>, r[1] as List<Curso>)),
          builder: (context, snapRef) {
            if (!snapRef.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (asignaturas, cursos) = snapRef.data!;
            final asignaturaPorId = {for (final a in asignaturas) a.id!: a};
            final cursoPorId = {for (final c in cursos) c.id!: c};

            final bloques = <String, Map<String, List<_FilaBloque>>>{};
            for (final fila in filas) {
              final asignatura = asignaturaPorId[fila.asignaturaId];
              if (asignatura == null) continue;
              final porAsignatura = bloques[asignatura.cursoId] ??= {};
              (porAsignatura[fila.asignaturaId] ??= []).add(fila);
            }

            final cursoIds = bloques.keys.toList()
              ..sort((a, b) {
                final ca = cursoPorId[a];
                final cb = cursoPorId[b];
                if (ca == null) return 1;
                if (cb == null) return -1;
                return ca.nivel.index != cb.nivel.index
                    ? ca.nivel.index.compareTo(cb.nivel.index)
                    : (ca.numeroCurso ?? 0).compareTo(cb.numeroCurso ?? 0);
              });

            if (cursoIds.isEmpty) {
              return const Center(child: Text('Todavía no hay horas de estudio este mes.'));
            }

            return ListView(
              children: [
                for (final cursoId in cursoIds) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(cursoPorId[cursoId]?.nombre ?? 'Curso desconocido',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  for (final asignaturaEntry in (bloques[cursoId]!.entries.toList()
                    ..sort((a, b) => (asignaturaPorId[a.key]?.nombre ?? '')
                        .compareTo(asignaturaPorId[b.key]?.nombre ?? ''))))
                    _BloqueAsignatura(
                      asignatura: asignaturaPorId[asignaturaEntry.key],
                      filas: asignaturaEntry.value,
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _BloqueAsignatura extends StatelessWidget {
  final Asignatura? asignatura;
  final List<_FilaBloque> filas;
  const _BloqueAsignatura({required this.asignatura, required this.filas});

  @override
  Widget build(BuildContext context) {
    final ordenadas = [...filas]..sort((a, b) => b.horasEfectivasMes.compareTo(a.horasEfectivasMes));
    final objetivo = asignatura?.horasObjetivoMensual ?? 0;
    final tieneObjetivo = objetivo > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(asignatura?.nombre ?? 'Asignatura desconocida',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              if (tieneObjetivo) ...[
                const SizedBox(width: 8),
                Text('· objetivo ${objetivo.toStringAsFixed(1)} h',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
              ],
            ],
          ),
        ),
        for (var i = 0; i < ordenadas.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
            title: Text(ordenadas[i].alumnoNombre),
            trailing: Text(
              '${ordenadas[i].horasEfectivasMes.toStringAsFixed(1)} h',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: !tieneObjetivo
                    ? null
                    : (ordenadas[i].horasEfectivasMes >= objetivo ? Colors.green : Colors.red),
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
