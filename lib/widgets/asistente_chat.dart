import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ajustes_service.dart';
import '../services/asistente_service.dart';

/// Botón flotante del asistente de Claude — siempre visible, esquina
/// inferior derecha. Desplazado por encima de la zona habitual de los
/// FABs propios de cada pantalla (p. ej. "Nuevo alumno", "+" de
/// criterios) para no solaparse con ellos, ver CLAUDE.md.
class BotonAsistente extends StatelessWidget {
  const BotonAsistente({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 88,
      child: FloatingActionButton(
        heroTag: 'asistente_claude',
        tooltip: 'Asistente',
        onPressed: () => _abrirChat(context),
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }

  void _abrirChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _PanelAsistente(),
    );
  }
}

class _PanelAsistente extends StatefulWidget {
  const _PanelAsistente();

  @override
  State<_PanelAsistente> createState() => _PanelAsistenteState();
}

class _PanelAsistenteState extends State<_PanelAsistente> {
  final AsistenteService _servicio = AsistenteService();
  final TextEditingController _controlador = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<MensajeAsistente> _mensajes = [];
  bool _enviando = false;

  @override
  void dispose() {
    _controlador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _controlador.text.trim();
    if (texto.isEmpty || _enviando) return;
    final url = context.read<AjustesService>().asistenteUrl;

    setState(() {
      _mensajes.add(MensajeAsistente(texto: texto, esUsuario: true));
      _controlador.clear();
      _enviando = true;
    });
    _desplazarAbajo();

    final respuesta = await _servicio.enviarMensaje(
      url: url,
      mensaje: texto,
      historial: _mensajes,
    );

    if (!mounted) return;
    setState(() {
      _mensajes.add(MensajeAsistente(texto: respuesta, esUsuario: false));
      _enviando = false;
    });
    _desplazarAbajo();
  }

  void _desplazarAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controladorScroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: esquema.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Asistente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _mensajes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Pídeme una gestión del centro, por ejemplo:\n'
                          '"Cambia a María de las 19:00 a las 20:00 los martes".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: esquema.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _mensajes.length,
                      itemBuilder: (context, i) => _BurbujaMensaje(mensaje: _mensajes[i]),
                    ),
            ),
            if (_enviando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controlador,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviar(),
                        decoration: const InputDecoration(
                          hintText: 'Escribe qué necesitas…',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _enviando ? null : _enviar,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BurbujaMensaje extends StatelessWidget {
  final MensajeAsistente mensaje;

  const _BurbujaMensaje({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Align(
      alignment: mensaje.esUsuario ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mensaje.esUsuario ? esquema.primary : esquema.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          mensaje.texto,
          style: TextStyle(color: mensaje.esUsuario ? esquema.onPrimary : esquema.onSurface),
        ),
      ),
    );
  }
}
