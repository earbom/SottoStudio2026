import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../models/asignatura.dart';
import '../../services/db_service.dart';

class NotasPendientesScreen extends StatefulWidget {
  const NotasPendientesScreen({super.key});

  @override
  State<NotasPendientesScreen> createState() => _NotasPendientesScreenState();
}

class _NotasPendientesScreenState extends State<NotasPendientesScreen> {
  final DbService _db = DbService();
  final Set<String> _seleccionadas = {};
  bool _modoSeleccion = false;

  void _alternarSeleccion(String notaId) {
    setState(() {
      _seleccionadas.contains(notaId) ? _seleccionadas.remove(notaId) : _seleccionadas.add(notaId);
    });
  }

  void _salirDeSeleccion() {
    setState(() {
      _modoSeleccion = false;
      _seleccionadas.clear();
    });
  }

  Future<void> _marcarSeleccionadas(EstadoNota estado) async {
    await _db.actualizarEstadoNotas(_seleccionadas.toList(), estado);
    _salirDeSeleccion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _modoSeleccion
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: _salirDeSeleccion),
              title: Text('${_seleccionadas.length} seleccionada(s)'),
            )
          : null,
      body: StreamBuilder<List<Nota>>(
        stream: _db.notasPendientesSupervision(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notas = snapshot.data!;
          if (notas.isEmpty) {
            return const Center(child: Text('No hay notas pendientes de supervisión.'));
          }
          return Column(
            children: [
              if (!_modoSeleccion)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.checklist),
                      label: const Text('Seleccionar varias'),
                      onPressed: () => setState(() => _modoSeleccion = true),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: notas.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _FilaNota(
                    nota: notas[i],
                    db: _db,
                    modoSeleccion: _modoSeleccion,
                    seleccionada: _seleccionadas.contains(notas[i].id),
                    onToggleSeleccion: () => _alternarSeleccion(notas[i].id!),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _modoSeleccion && _seleccionadas.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _marcarSeleccionadas(EstadoNota.supervisada),
                        child: const Text('Marcar supervisadas'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _marcarSeleccionadas(EstadoNota.corregida),
                        child: const Text('Marcar corregidas'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _FilaNota extends StatelessWidget {
  final Nota nota;
  final DbService db;
  final bool modoSeleccion;
  final bool seleccionada;
  final VoidCallback onToggleSeleccion;

  const _FilaNota({
    required this.nota,
    required this.db,
    required this.modoSeleccion,
    required this.seleccionada,
    required this.onToggleSeleccion,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Usuario?>(
      future: db.obtenerUsuario(nota.alumnoId),
      builder: (context, snapAlumno) {
        final nombreAlumno = snapAlumno.data?.nombre ?? nota.alumnoId;
        return FutureBuilder<Asignatura?>(
          future: db.asignatura(nota.asignaturaId),
          builder: (context, snapAsignatura) {
            final nombreAsignatura = snapAsignatura.data?.nombre ?? nota.asignaturaId;
            return ListTile(
              leading: modoSeleccion
                  ? Checkbox(value: seleccionada, onChanged: (_) => onToggleSeleccion())
                  : null,
              title: Text('$nombreAlumno · $nombreAsignatura'),
              subtitle: Text(
                '${nota.valor.toStringAsFixed(1)} — ${nota.comentario}\n${DateFormat('dd/MM/yyyy').format(nota.fecha)}',
              ),
              isThreeLine: true,
              trailing: modoSeleccion
                  ? null
                  : PopupMenuButton<EstadoNota>(
                      onSelected: (estado) => db.actualizarEstadoNota(nota.id!, estado),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: EstadoNota.supervisada, child: Text('Marcar supervisada')),
                        PopupMenuItem(value: EstadoNota.corregida, child: Text('Marcar corregida')),
                      ],
                    ),
              onTap: modoSeleccion ? onToggleSeleccion : null,
            );
          },
        );
      },
    );
  }
}
