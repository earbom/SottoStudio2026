import 'package:flutter/material.dart';
import '../../models/asignatura.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../widgets/grabador_estudio_widget.dart';

/// Punto de entrada único y visible para empezar a grabar una sesión
/// de estudio: primero se elige a qué asignatura de instrumento
/// corresponde (solo aparecen las que dirección ha marcado con
/// `permiteGrabarEstudio == true`, ver CLAUDE.md punto 41), y debajo
/// se muestran los mismos botones de grabación de siempre. Antes solo
/// se podía empezar a grabar desde la tarjeta de cada asignatura en
/// "Mi estudio" — reportado como poco intuitivo/difícil de encontrar.
class EmpezarEstudioScreen extends StatefulWidget {
  final Usuario perfil;

  const EmpezarEstudioScreen({super.key, required this.perfil});

  @override
  State<EmpezarEstudioScreen> createState() => _EmpezarEstudioScreenState();
}

class _EmpezarEstudioScreenState extends State<EmpezarEstudioScreen> {
  final DbService _db = DbService();
  bool _cargando = true;
  List<Asignatura> _asignaturasDisponibles = [];
  Asignatura? _seleccionada;
  bool _grabando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cursoEscolar = await _db.cursoEscolarActivo().first;
    final matriculas = await _db.matriculasDeAlumno(widget.perfil.uid, cursoEscolar: cursoEscolar).first;
    final asignaturas = (await Future.wait(matriculas.map((m) => _db.asignatura(m.asignaturaId))))
        .whereType<Asignatura>()
        .where((a) => a.permiteGrabarEstudio)
        .toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    if (!mounted) return;
    setState(() {
      _asignaturasDisponibles = asignaturas;
      _seleccionada = asignaturas.isEmpty ? null : asignaturas.first;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Empezar estudio de instrumento')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _asignaturasDisponibles.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavía no tienes ninguna asignatura de instrumento habilitada para grabar '
                      'estudio. Pide a dirección que la active desde la asignatura correspondiente.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<Asignatura>(
                        initialValue: _seleccionada,
                        decoration: const InputDecoration(labelText: 'Asignatura'),
                        // Bloqueado mientras se graba, para no perder
                        // una sesión a medio grabar cambiando de
                        // asignatura por debajo.
                        onChanged: _grabando
                            ? null
                            : (a) => setState(() => _seleccionada = a),
                        items: _asignaturasDisponibles
                            .map((a) => DropdownMenuItem(value: a, child: Text(a.nombre)))
                            .toList(),
                      ),
                      const SizedBox(height: 32),
                      Expanded(
                        child: Center(
                          child: GrabadorEstudioWidget(
                            key: ValueKey(_seleccionada!.id),
                            alumnoId: widget.perfil.uid,
                            instrumento: widget.perfil.instrumento,
                            asignaturaId: _seleccionada!.id!,
                            onGrabandoChanged: (v) => setState(() => _grabando = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
