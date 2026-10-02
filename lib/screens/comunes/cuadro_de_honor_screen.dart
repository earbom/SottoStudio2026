import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/curso.dart';
import '../../models/usuario.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

typedef _FilaBloque = ({String alumnoId, String alumnoNombre, String asignaturaId, double horasEfectivasMes});

// Sin `initializeDateFormatting('es')` en el arranque de la app, un
// `DateFormat.MMMM('es')` lanzaría en tiempo de ejecución — un nombre
// de mes fijo evita añadir esa inicialización solo para esta etiqueta.
const _nombresMes = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _mesAnteriorEtiqueta() {
  final ahora = DateTime.now();
  final mesAnterior = DateTime(ahora.year, ahora.month - 1, 1);
  return '${_nombresMes[mesAnterior.month - 1]} de ${mesAnterior.year}';
}

/// Cuadro de Honor: quiénes llegaron al objetivo de horas efectivas de
/// estudio del MES ANTERIOR YA CERRADO (pedido por dirección: deja de
/// ser en tiempo real sobre el mes en curso — ver
/// `DbService.horasPorAsignaturaMensual`), agrupadas por curso →
/// asignatura (único criterio, ver CLAUDE.md — se simplificó desde una
/// versión anterior con varios modos y un filtro por curso/asignatura,
/// ya retirados). Solo se muestran asignaturas CON objetivo configurado
/// (`Asignatura.horasObjetivoMensual > 0`) y, dentro de ellas, solo los
/// alumnos que lo alcanzaron — ya no es un ranking de todos, es un
/// reconocimiento de quien llegó. Visible para cualquier permiso,
/// incluidos los propios alumnos — excepción deliberada del punto 14
/// (privacidad de nombres), ver CLAUDE.md. No necesita leer
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
            child: Text('Objetivo de horas cumplido en ${_mesAnteriorEtiqueta()}'),
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
          return const Center(child: Text('Nadie ha llegado al objetivo de horas el mes pasado.'));
        }
        return FutureBuilder<(List<Asignatura>, List<Curso>)>(
          future: Future.wait([db.todasLasAsignaturas().first, db.cursos().first]).then(
              (r) => (r[0] as List<Asignatura>, r[1] as List<Curso>)),
          builder: (context, snapRef) {
            if (snapRef.hasError) {
              return const ErrorCarga();
            }
            if (!snapRef.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (asignaturas, cursos) = snapRef.data!;
            final asignaturaPorId = {for (final a in asignaturas) a.id!: a};
            final cursoPorId = {for (final c in cursos) c.id!: c};

            // Solo asignaturas CON objetivo configurado y, dentro de
            // ellas, solo quien lo alcanzó — ver comentario de la clase.
            final bloques = <String, Map<String, List<_FilaBloque>>>{};
            for (final fila in filas) {
              final asignatura = asignaturaPorId[fila.asignaturaId];
              if (asignatura == null) continue;
              final objetivo = asignatura.horasObjetivoMensual;
              if (objetivo <= 0 || fila.horasEfectivasMes < objetivo) continue;
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
              return const Center(child: Text('Nadie ha llegado al objetivo de horas el mes pasado.'));
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

/// Solo recibe alumnos que YA alcanzaron el objetivo (filtrado en
/// `_ListaAgrupadaPorBloques`) — esto ya no es un ranking con
/// rojo/verde, es un reconocimiento de quien llegó.
class _BloqueAsignatura extends StatelessWidget {
  final Asignatura? asignatura;
  final List<_FilaBloque> filas;
  const _BloqueAsignatura({required this.asignatura, required this.filas});

  @override
  Widget build(BuildContext context) {
    final ordenadas = [...filas]..sort((a, b) => b.horasEfectivasMes.compareTo(a.horasEfectivasMes));
    final objetivo = asignatura?.horasObjetivoMensual ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(asignatura?.nombre ?? 'Asignatura desconocida',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('· objetivo ${objetivo.toStringAsFixed(1)} h',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            ],
          ),
        ),
        for (final fila in ordenadas)
          ListTile(
            dense: true,
            leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
            title: Text(fila.alumnoNombre),
            trailing: Text(
              '${fila.horasEfectivasMes.toStringAsFixed(1)} h',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
