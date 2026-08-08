import 'package:flutter/material.dart';
import '../../services/db_service.dart';

/// Dirección gestiona aquí el curso escolar activo del centro (p.ej.
/// "2025-2026"), que discrimina qué alumnos aparecen matriculados en
/// cada asignatura (ver CLAUDE.md). Avanzar de curso NO borra nada: el
/// curso anterior queda en el historial, consultable (no editable)
/// desde cada pantalla afectada (lista de la asignatura, ranking,
/// informe de horas).
class CursoEscolarScreen extends StatefulWidget {
  const CursoEscolarScreen({super.key});

  @override
  State<CursoEscolarScreen> createState() => _CursoEscolarScreenState();
}

class _CursoEscolarScreenState extends State<CursoEscolarScreen> {
  final DbService _db = DbService();

  Future<void> _avanzarCurso(String cursoActual) async {
    final ctrl = TextEditingController();
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Avanzar de curso escolar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Curso activo actual: $cursoActual'),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Nuevo curso escolar',
                hintText: 'p. ej. 2026-2027',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            const Text(
              'El curso actual no se borra: queda en el historial, solo '
              'consultable desde cada pantalla.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Avanzar'),
          ),
        ],
      ),
    );

    if (nuevo == null || nuevo.isEmpty) return;
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(nuevo)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formato no válido. Usa "aaaa-aaaa", p. ej. 2026-2027.')),
      );
      return;
    }
    await _db.avanzarCursoEscolar(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Curso escolar')),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final activo = snapActivo.data!;
          return StreamBuilder<List<String>>(
            stream: _db.historialCursosEscolares(),
            builder: (context, snapHistorial) {
              final historial = snapHistorial.data ?? [activo];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Activo actualmente', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(activo, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _avanzarCurso(activo),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Avanzar de curso escolar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Historial de cursos escolares', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...historial.reversed.map((curso) => ListTile(
                        leading: Icon(curso == activo ? Icons.star : Icons.history),
                        title: Text(curso),
                        subtitle: curso == activo ? const Text('Activo') : null,
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
