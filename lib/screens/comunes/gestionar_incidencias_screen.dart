import 'package:flutter/material.dart';
import '../../models/incidencia.dart';
import '../../services/auth_service.dart';
import '../../services/db_service.dart';

/// Panel del desarrollador (ver CLAUDE.md, modo desarrollador): todas
/// las incidencias enviadas por cualquier usuario, agrupadas por
/// estado. Alcanzable solo desde el bloque de drawer gateado por
/// `perfilReal.esDesarrollador`; las reglas de Firestore ya restringen
/// `todasLasIncidencias()` a esa cuenta, así que no hace falta ninguna
/// comprobación de permiso adicional aquí.
class GestionarIncidenciasScreen extends StatelessWidget {
  const GestionarIncidenciasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService();
    return Scaffold(
      appBar: AppBar(title: const Text('Incidencias')),
      body: StreamBuilder<List<Incidencia>>(
        stream: db.todasLasIncidencias(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final incidencias = snapshot.data!;
          if (incidencias.isEmpty) {
            return const Center(child: Text('No hay incidencias todavía.'));
          }
          final pendientes = incidencias.where((i) => i.estado == EstadoIncidencia.pendiente).toList();
          final resueltas = incidencias.where((i) => i.estado == EstadoIncidencia.resuelto).toList();
          return ListView(
            children: [
              if (pendientes.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Pendientes', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final i in pendientes) _FilaIncidencia(incidencia: i, db: db),
              ],
              if (resueltas.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Resueltas', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final i in resueltas) _FilaIncidencia(incidencia: i, db: db),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FilaIncidencia extends StatelessWidget {
  final Incidencia incidencia;
  final DbService db;

  const _FilaIncidencia({required this.incidencia, required this.db});

  Future<void> _cambiarEstado(BuildContext context) async {
    final nuevo = incidencia.estado == EstadoIncidencia.pendiente
        ? EstadoIncidencia.resuelto
        : EstadoIncidencia.pendiente;
    await db.actualizarEstadoIncidencia(incidencia.id!, nuevo);
  }

  Future<void> _comentar(BuildContext context) async {
    final ctrl = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir comentario'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (texto == null || texto.isEmpty) return;
    final yo = AuthService().usuarioActual;
    await db.agregarComentarioIncidencia(
      incidencia.id!,
      ComentarioIncidencia(
        autorId: yo?.uid ?? '',
        autorNombre: 'Desarrollador',
        texto: texto,
        fecha: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esPendiente = incidencia.estado == EstadoIncidencia.pendiente;
    return ExpansionTile(
      leading: Icon(
        incidencia.tipo == TipoIncidencia.problema ? Icons.error_outline : Icons.lightbulb_outline,
      ),
      title: Text(incidencia.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${incidencia.autorNombre} · ${incidencia.fecha.day}/${incidencia.fecha.month}/${incidencia.fecha.year}'),
      children: [
        for (final c in incidencia.comentarios)
          ListTile(
            dense: true,
            title: Text(c.texto),
            subtitle: Text(c.autorNombre),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: () => _comentar(context),
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Comentar'),
              ),
              FilledButton.icon(
                onPressed: () => _cambiarEstado(context),
                icon: Icon(esPendiente ? Icons.check_circle_outline : Icons.replay_outlined),
                label: Text(esPendiente ? 'Marcar resuelto' : 'Reabrir'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
