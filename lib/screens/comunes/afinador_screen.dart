import 'package:flutter/material.dart';
import '../../services/afinador_service.dart';
import '../../utils/instrumentos_afinador.dart';

class AfinadorScreen extends StatefulWidget {
  const AfinadorScreen({super.key});

  @override
  State<AfinadorScreen> createState() => _AfinadorScreenState();
}

class _AfinadorScreenState extends State<AfinadorScreen> {
  final _afinador = AfinadorService();
  LecturaAfinador? _ultimaLectura;
  String? _error;
  bool _cargando = false;

  InstrumentoAfinador _instrumento = instrumentosAfinador.first;
  AfinacionInstrumento? _afinacion;

  @override
  void initState() {
    super.initState();
    _afinador.lecturas.listen((lectura) {
      if (mounted) setState(() => _ultimaLectura = lectura);
    });
  }

  void _cambiarInstrumento(InstrumentoAfinador nuevo) {
    setState(() {
      _instrumento = nuevo;
      _afinacion = nuevo.afinaciones.isEmpty ? null : nuevo.afinaciones.first;
    });
    _afinador.frecuenciaMin = nuevo.frecuenciaMin;
    _afinador.frecuenciaMax = nuevo.frecuenciaMax;
  }

  /// Cuerda/nota objetivo que coincide EXACTAMENTE (misma nota+octava)
  /// con lo detectado. Todas las afinaciones del catálogo usan notas
  /// estándar de temperamento igual, así que los "cents" que ya
  /// calcula AfinadorService respecto a la nota cromática más cercana
  /// son directamente los cents respecto a esta cuerda — no hace
  /// falta recalcularlos contra su frecuencia exacta.
  NotaObjetivo? _cuerdaCoincidente(LecturaAfinador lectura) {
    if (!lectura.detectada || _afinacion == null) return null;
    for (final n in _afinacion!.notas) {
      if (n.nota == lectura.nota && n.octava == lectura.octava) return n;
    }
    return null;
  }

  @override
  void dispose() {
    _afinador.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    if (_afinador.escuchando) {
      await _afinador.detener();
      setState(() {
        _ultimaLectura = null;
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _afinador.iniciar();
    } catch (e) {
      setState(() => _error = 'No se pudo acceder al micrófono. Revisa los permisos del navegador.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lectura = _ultimaLectura;
    final detectada = lectura?.detectada ?? false;
    final cents = (lectura?.cents ?? 0).clamp(-50.0, 50.0);
    final afinado = detectada && cents.abs() <= 5;
    final cuerdaCoincidente = detectada ? _cuerdaCoincidente(lectura!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Afinador')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                DropdownButtonFormField<InstrumentoAfinador>(
                  initialValue: _instrumento,
                  decoration: const InputDecoration(labelText: 'Instrumento'),
                  isExpanded: true,
                  items: instrumentosAfinador
                      .map((i) => DropdownMenuItem(value: i, child: Text(i.nombre)))
                      .toList(),
                  onChanged: (i) => _cambiarInstrumento(i!),
                ),
                if (_instrumento.afinaciones.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AfinacionInstrumento>(
                    initialValue: _afinacion,
                    decoration: const InputDecoration(labelText: 'Afinación'),
                    isExpanded: true,
                    items: _instrumento.afinaciones
                        .map((a) => DropdownMenuItem(value: a, child: Text(a.nombre)))
                        .toList(),
                    onChanged: (a) => setState(() => _afinacion = a),
                  ),
                ],
                if (_afinacion != null) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _afinacion!.notas.map((n) {
                      final activa = n == cuerdaCoincidente;
                      return Chip(
                        label: Text(n.etiqueta),
                        backgroundColor: activa
                            ? (afinado ? Colors.green : Colors.deepOrange).withValues(alpha: 0.2)
                            : null,
                        side: activa
                            ? BorderSide(color: afinado ? Colors.green : Colors.deepOrange, width: 2)
                            : null,
                        labelStyle: TextStyle(fontWeight: activa ? FontWeight.bold : FontWeight.normal),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  detectada ? '${lectura!.nota}${lectura.octava}' : '—',
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.bold,
                    color: afinado ? Colors.green : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detectada
                      ? '${lectura!.frecuencia!.toStringAsFixed(1)} Hz'
                      : (_afinador.escuchando ? 'Escuchando... toca una nota' : 'Pulsa el micrófono para empezar'),
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                // Medidor de cents: -50 (bemol) .. 0 (afinado) .. +50 (sostenido)
                SizedBox(
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Container(width: 2, height: 40, color: Colors.black45),
                      if (detectada)
                        Align(
                          alignment: Alignment(cents / 50, 0),
                          child: Container(
                            width: 16,
                            height: 48,
                            decoration: BoxDecoration(
                              color: afinado ? Colors.green : Colors.deepOrange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (detectada)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      cents == 0
                          ? 'Afinado'
                          : (cents < 0 ? '${cents.toStringAsFixed(0)} cents (bemol)' : '+${cents.toStringAsFixed(0)} cents (sostenido)'),
                    ),
                  ),
                const SizedBox(height: 48),
                IconButton(
                  iconSize: 88,
                  color: _afinador.escuchando ? Colors.red : Theme.of(context).colorScheme.primary,
                  icon: _cargando
                      ? const SizedBox(width: 48, height: 48, child: CircularProgressIndicator())
                      : Icon(_afinador.escuchando ? Icons.mic : Icons.mic_none),
                  onPressed: _cargando ? null : _alternar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
