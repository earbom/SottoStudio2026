import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/db_service.dart';

/// Dirección gestiona aquí el curso escolar activo del centro (p.ej.
/// "2025-2026"), que discrimina qué alumnos aparecen matriculados en
/// cada asignatura (ver CLAUDE.md). Avanzar de curso NO borra nada: el
/// curso anterior queda en el historial, consultable (no editable)
/// desde cada pantalla afectada (lista de la asignatura, ranking,
/// informe de horas). Cada fila del historial que no sea la activa
/// permite volver a marcarla como activa (sin perder nada, ver
/// CLAUDE.md) o eliminarla del historial (solo la quita de la lista,
/// nunca borra matrículas/notas/asistencias reales).
class CursoEscolarScreen extends StatefulWidget {
  const CursoEscolarScreen({super.key});

  @override
  State<CursoEscolarScreen> createState() => _CursoEscolarScreenState();
}

class _CursoEscolarScreenState extends State<CursoEscolarScreen> {
  final DbService _db = DbService();

  Future<void> _crearOActivarCurso(String cursoActual) async {
    final ctrl = TextEditingController();
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear/activar un curso escolar nuevo'),
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
              'consultable desde cada pantalla. Para volver a un curso que '
              'ya existe en el historial, usa "Marcar como activo" en su fila.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Crear/activar'),
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

  Future<void> _marcarComoActivo(String cursoEscolar) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como activo'),
        content: Text(
          'Vas a volver a marcar "$cursoEscolar" como curso escolar activo. '
          'Sus matrículas, notas y asistencias ya existentes siguen intactas '
          'y podrás seguir trabajando en él con normalidad.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Marcar como activo')),
        ],
      ),
    );
    if (confirmar != true) return;
    await _db.avanzarCursoEscolar(cursoEscolar);
  }

  Future<void> _eliminarDelHistorial(String cursoEscolar) async {
    final tieneDatos = await _db.tieneDatosCursoEscolar(cursoEscolar);
    if (!mounted) return;

    if (tieneDatos) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Este curso escolar tiene datos'),
          content: Text(
            'El curso escolar "$cursoEscolar" tiene matrículas (y posiblemente '
            'notas o asistencias) de alumnos. Esta acción NO borra esos datos '
            '— seguirán existiendo en la base de datos — pero el año dejará '
            'de aparecer como opción de curso escolar en la app.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (continuar != true) return;
      if (!mounted) return;
    }

    final confirmado = await _confirmarConCuentaAtras(cursoEscolar);
    if (confirmado != true) return;
    await _db.eliminarCursoEscolarDelHistorial(cursoEscolar);
  }

  Future<bool?> _confirmarConCuentaAtras(String cursoEscolar) {
    return showDialog<bool>(
      context: context,
      builder: (context) => _DialogoConfirmarConCuentaAtras(cursoEscolar: cursoEscolar),
    );
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
                            onPressed: () => _crearOActivarCurso(activo),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Crear/activar un curso escolar nuevo'),
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
                        trailing: curso == activo
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check_circle_outline),
                                    tooltip: 'Marcar como activo',
                                    onPressed: () => _marcarComoActivo(curso),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Eliminar del historial',
                                    onPressed: () => _eliminarDelHistorial(curso),
                                  ),
                                ],
                              ),
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

class _DialogoConfirmarConCuentaAtras extends StatefulWidget {
  final String cursoEscolar;
  const _DialogoConfirmarConCuentaAtras({required this.cursoEscolar});

  @override
  State<_DialogoConfirmarConCuentaAtras> createState() => _DialogoConfirmarConCuentaAtrasState();
}

class _DialogoConfirmarConCuentaAtrasState extends State<_DialogoConfirmarConCuentaAtras> {
  static const _segundosIniciales = 5;
  int _segundosRestantes = _segundosIniciales;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes <= 1) {
        timer.cancel();
        setState(() => _segundosRestantes = 0);
      } else {
        setState(() => _segundosRestantes--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = _segundosRestantes == 0;
    return AlertDialog(
      title: Text('Eliminar ${widget.cursoEscolar} del historial'),
      content: const Text(
        'Vas a eliminar este curso escolar del historial. Dejará de aparecer '
        'como opción en toda la app (aunque no se borre ningún dato). Espera '
        'unos segundos para confirmar.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: habilitado ? () => Navigator.pop(context, true) : null,
          child: Text(habilitado ? 'Eliminar' : 'Eliminar ($_segundosRestantes)'),
        ),
      ],
    );
  }
}
