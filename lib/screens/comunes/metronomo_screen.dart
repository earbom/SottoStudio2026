import 'package:flutter/material.dart';
import '../../services/metronomo_service.dart';

class MetronomoScreen extends StatefulWidget {
  const MetronomoScreen({super.key});

  @override
  State<MetronomoScreen> createState() => _MetronomoScreenState();
}

class _MetronomoScreenState extends State<MetronomoScreen> {
  final _metronomo = MetronomoService();
  int _pulsoActual = 0;

  @override
  void initState() {
    super.initState();
    _metronomo.pulsoActual.listen((pulso) {
      if (mounted) setState(() => _pulsoActual = pulso);
    });
  }

  @override
  void dispose() {
    _metronomo.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    if (_metronomo.sonando) {
      await _metronomo.detener();
      setState(() => _pulsoActual = 0);
    } else {
      await _metronomo.iniciar();
    }
    setState(() {});
  }

  void _cambiarBpm(int delta) {
    setState(() => _metronomo.cambiarBpm(_metronomo.bpm + delta));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Metrónomo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador visual de pulso
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_metronomo.compas.pulsos, (i) {
                    final activo = _pulsoActual == i + 1;
                    final esAcento = i == 0;
                    return Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activo
                            ? (esAcento ? Colors.deepOrange : Theme.of(context).colorScheme.primary)
                            : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                Text('${_metronomo.bpm}', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold)),
                const Text('BPM', style: TextStyle(color: Colors.grey)),
                Text(
                  nombreItalianoTempo(_metronomo.bpm),
                  style: TextStyle(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _cambiarBpm(-1),
                    ),
                    Expanded(
                      child: Slider(
                        min: 20,
                        max: 240,
                        divisions: 220,
                        value: _metronomo.bpm.toDouble(),
                        label: '${_metronomo.bpm}',
                        onChanged: (v) => setState(() => _metronomo.cambiarBpm(v.round())),
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _cambiarBpm(1),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Compas>(
                        initialValue: _metronomo.compas,
                        decoration: const InputDecoration(labelText: 'Compás'),
                        items: compasesDisponibles
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.nombre)))
                            .toList(),
                        onChanged: (c) => setState(() => _metronomo.cambiarCompas(c!)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<FiguraClic>(
                        initialValue: _metronomo.figura,
                        decoration: const InputDecoration(labelText: 'Figura'),
                        items: FiguraClic.values
                            .map((f) => DropdownMenuItem(value: f, child: Text(f.etiqueta)))
                            .toList(),
                        onChanged: (f) => setState(() => _metronomo.cambiarFigura(f!)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                IconButton(
                  iconSize: 96,
                  color: _metronomo.sonando ? Colors.red : Theme.of(context).colorScheme.primary,
                  icon: Icon(_metronomo.sonando ? Icons.stop_circle : Icons.play_circle),
                  onPressed: _alternar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
