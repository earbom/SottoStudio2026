import 'package:flutter/material.dart';
import '../../models/incidencia.dart';
import '../../models/usuario.dart';
import '../../widgets/error_carga.dart';
import '../../services/db_service.dart';

/// Cualquier usuario autenticado (alumno, profesor o dirección) puede
/// informar de un problema o sugerencia aquí, y ver el estado de lo
/// que ha enviado — solo el desarrollador puede marcarlo como
/// resuelto (ver CLAUDE.md, modo desarrollador); el autor puede
/// añadir comentarios de aclaración pero nunca resolverse a sí mismo.
class ReportarIncidenciaScreen extends StatefulWidget {
  final Usuario perfil;

  const ReportarIncidenciaScreen({super.key, required this.perfil});

  @override
  State<ReportarIncidenciaScreen> createState() => _ReportarIncidenciaScreenState();
}

class _ReportarIncidenciaScreenState extends State<ReportarIncidenciaScreen> {
  final _db = DbService();
  final _descripcionCtrl = TextEditingController();
  TipoIncidencia _tipo = TipoIncidencia.problema;
  bool _enviando = false;

  Future<void> _enviar() async {
    if (_descripcionCtrl.text.trim().isEmpty) return;
    setState(() => _enviando = true);
    try {
      await _db.crearIncidencia(Incidencia(
        autorId: widget.perfil.uid,
        autorNombre: widget.perfil.nombre,
        tipo: _tipo,
        descripcion: _descripcionCtrl.text.trim(),
        fecha: DateTime.now(),
      ));
      _descripcionCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enviado. Gracias por avisar.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _anadirComentario(Incidencia incidencia) async {
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
    await _db.agregarComentarioIncidencia(
      incidencia.id!,
      ComentarioIncidencia(
        autorId: widget.perfil.uid,
        autorNombre: widget.perfil.nombre,
        texto: texto,
        fecha: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informar de un problema o sugerencia')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<TipoIncidencia>(
                  segments: const [
                    ButtonSegment(value: TipoIncidencia.problema, label: Text('Problema')),
                    ButtonSegment(value: TipoIncidencia.sugerencia, label: Text('Sugerencia')),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (s) => setState(() => _tipo = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descripcionCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Mis incidencias enviadas', style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Incidencia>>(
              stream: _db.misIncidencias(widget.perfil.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ErrorCarga();
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final incidencias = snapshot.data!;
                if (incidencias.isEmpty) {
                  return const Center(child: Text('Todavía no has enviado nada.'));
                }
                return ListView.separated(
                  itemCount: incidencias.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final incidencia = incidencias[i];
                    return ExpansionTile(
                      title: Text(incidencia.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${incidencia.tipo == TipoIncidencia.problema ? 'Problema' : 'Sugerencia'} · '
                        '${incidencia.estado == EstadoIncidencia.resuelto ? 'Resuelto' : 'Pendiente'}',
                      ),
                      children: [
                        for (final c in incidencia.comentarios)
                          ListTile(
                            dense: true,
                            title: Text(c.texto),
                            subtitle: Text(c.autorNombre),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _anadirComentario(incidencia),
                              icon: const Icon(Icons.add_comment_outlined),
                              label: const Text('Añadir comentario'),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
