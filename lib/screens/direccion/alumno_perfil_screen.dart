import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/asignatura.dart';
import '../../models/contacto_alumno.dart';
import '../../models/criterio_evaluacion.dart';
import '../../models/matricula.dart';
import '../../models/nota.dart';
import '../../models/usuario.dart';
import '../../services/db_service.dart';
import '../../utils/boletin_pdf.dart';
import '../../utils/mensaje_error.dart';
import '../comunes/asignatura_detalle_screen.dart';
import '../../widgets/error_carga.dart';
import '../../widgets/acciones_usuario.dart';
import '../../widgets/campo_busqueda.dart';

/// Ficha de un alumno para dirección: sus asignaturas matriculadas en
/// el curso escolar activo, con la opción de generar un boletín de
/// notas en PDF eligiendo cuáles incluir.
class AlumnoPerfilScreen extends StatefulWidget {
  final Usuario alumno;
  // Quien mira (dirección): necesario para abrir la ficha de una
  // asignatura desde aquí.
  final Usuario perfil;

  const AlumnoPerfilScreen({super.key, required this.alumno, required this.perfil});

  @override
  State<AlumnoPerfilScreen> createState() => _AlumnoPerfilScreenState();
}

class _AlumnoPerfilScreenState extends State<AlumnoPerfilScreen> {
  final DbService _db = DbService();
  bool _generando = false;
  late Usuario _alumno = widget.alumno;

  /// Matricular desde la ficha del alumno (dirección piensa "por
  /// alumno": le doy de alta y le pongo sus asignaturas), sin tener que
  /// ir a cada asignatura por separado.
  Future<void> _matricular(Set<String> yaMatriculadas) async {
    final asignaturas = await _db.todasLasAsignaturas().first;
    final cursos = await _db.cursos().first;
    if (!mounted) return;
    final nombreCurso = {for (final c in cursos) c.id!: c.nombre};
    final ordenCurso = {for (var i = 0; i < cursos.length; i++) cursos[i].id!: i};
    final disponibles = asignaturas.where((a) => !yaMatriculadas.contains(a.id)).toList()
      ..sort((a, b) {
        final c = (ordenCurso[a.cursoId] ?? 999).compareTo(ordenCurso[b.cursoId] ?? 999);
        return c != 0 ? c : a.nombre.compareTo(b.nombre);
      });
    final elegida = await showDialog<Asignatura>(
      context: context,
      builder: (context) => _DialogoElegirAsignatura(asignaturas: disponibles, nombreCurso: nombreCurso),
    );
    if (elegida == null || !mounted) return;
    await configurarYMatricular(context, alumno: _alumno, asignatura: elegida);
  }

  Future<void> _recargar() async {
    final actualizado = await _db.obtenerUsuario(_alumno.uid);
    if (actualizado != null && mounted) setState(() => _alumno = actualizado);
  }

  Future<void> _generarBoletin(String cursoEscolar, List<Asignatura> todas) async {
    final seleccionadas = await showDialog<List<Asignatura>>(
      context: context,
      builder: (context) => _DialogoSeleccionAsignaturas(asignaturas: todas),
    );
    if (seleccionadas == null || seleccionadas.isEmpty) return;

    setState(() => _generando = true);
    try {
      final criteriosPorAsignatura = <String, List<CriterioEvaluacion>>{};
      final notasPorAsignatura = <String, List<Nota>>{};
      final todasLasNotas = await _db.notasDeAlumno(_alumno.uid).first;
      for (final asignatura in seleccionadas) {
        criteriosPorAsignatura[asignatura.id!] = await _db.criteriosDeAsignatura(asignatura.id!).first;
        notasPorAsignatura[asignatura.id!] =
            todasLasNotas.where((n) => n.asignaturaId == asignatura.id).toList();
      }

      final doc = await generarBoletinPdf(
        alumno: _alumno,
        cursoEscolar: cursoEscolar,
        asignaturas: seleccionadas,
        criteriosPorAsignatura: criteriosPorAsignatura,
        notasPorAsignatura: notasPorAsignatura,
      );

      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'Boletin_${_alumno.nombre}_$cursoEscolar',
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_alumno.nombre),
        actions: [MenuAccionesUsuario(usuario: _alumno, esAlumno: true, onEditado: _recargar)],
      ),
      body: StreamBuilder<String>(
        stream: _db.cursoEscolarActivo(),
        builder: (context, snapActivo) {
          if (snapActivo.hasError) {
            return const ErrorCarga();
          }
          if (!snapActivo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cursoEscolar = snapActivo.data!;
          return StreamBuilder<List<Matricula>>(
            stream: _db.matriculasDeAlumno(_alumno.uid, cursoEscolar: cursoEscolar),
            builder: (context, snapMatriculas) {
              if (snapMatriculas.hasError) {
                return const ErrorCarga();
              }
              if (!snapMatriculas.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matriculas = snapMatriculas.data!;
              return FutureBuilder<(List<Asignatura>, Map<String, String>)>(
                future: Future.wait([
                  Future.wait(matriculas.map((m) => _db.asignatura(m.asignaturaId)))
                      .then((lista) => lista.whereType<Asignatura>().toList()),
                  _db.cursos().first.then((cs) => {for (final c in cs) c.id!: c.nombre}),
                ]).then((r) => (r[0] as List<Asignatura>, r[1] as Map<String, String>)),
                builder: (context, snapAsignaturas) {
                  if (snapAsignaturas.hasError) {
                    return const ErrorCarga();
                  }
                  if (!snapAsignaturas.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final (asignaturas, nombreCurso) = snapAsignaturas.data!;
                  final matriculaPorAsignatura = {for (final m in matriculas) m.asignaturaId: m};
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_alumno.apellidos?.isNotEmpty ?? false)
                              Text('${_alumno.nombre} ${_alumno.apellidos}',
                                  style: Theme.of(context).textTheme.titleMedium),
                            if (_alumno.tieneCuenta && (_alumno.email?.isNotEmpty ?? false))
                              Text('Email: ${_alumno.email}'),
                            if (_alumno.instrumento?.isNotEmpty ?? false)
                              Text('Instrumento: ${_alumno.instrumento}'),
                            const SizedBox(height: 4),
                            Text('Curso escolar: $cursoEscolar', style: const TextStyle(color: Colors.grey)),
                            if (!_alumno.tieneCuenta) ...[
                              const SizedBox(height: 4),
                              const Text('Sin acceso a la app',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                      ),
                      _TarjetaContacto(alumnoId: _alumno.uid),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Asignaturas', style: Theme.of(context).textTheme.titleSmall),
                            ),
                            TextButton.icon(
                              onPressed: () => _matricular(asignaturas.map((a) => a.id!).toSet()),
                              icon: const Icon(Icons.add),
                              label: const Text('Matricular en una asignatura'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: asignaturas.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'No está matriculado en ninguna asignatura en el curso escolar $cursoEscolar.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: asignaturas.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final a = asignaturas[i];
                                  final m = matriculaPorAsignatura[a.id];
                                  final dias = m == null
                                      ? ''
                                      : m.diasSemana.map((d) => nombresDiasSemana[d - 1]).join(', ');
                                  final horario = [
                                    nombreCurso[a.cursoId] ?? '',
                                    if (dias.isNotEmpty) dias,
                                    if (m != null && m.horaInicio.isNotEmpty) '${m.horaInicio}-${m.horaFin}',
                                  ].where((t) => t.isNotEmpty).join(' · ');
                                  return ListTile(
                                    leading: const Icon(Icons.menu_book_outlined),
                                    title: Text(a.nombre),
                                    subtitle: horario.isEmpty ? null : Text(horario),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AsignaturaDetalleScreen(asignatura: a, perfil: widget.perfil),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                          onPressed:
                              _generando || asignaturas.isEmpty ? null : () => _generarBoletin(cursoEscolar, asignaturas),
                          icon: _generando
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Generar boletín de notas'),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DialogoSeleccionAsignaturas extends StatefulWidget {
  final List<Asignatura> asignaturas;

  const _DialogoSeleccionAsignaturas({required this.asignaturas});

  @override
  State<_DialogoSeleccionAsignaturas> createState() => _DialogoSeleccionAsignaturasState();
}

class _DialogoSeleccionAsignaturasState extends State<_DialogoSeleccionAsignaturas> {
  final Set<String> _seleccionadas = {};

  @override
  void initState() {
    super.initState();
    _seleccionadas.addAll(widget.asignaturas.map((a) => a.id!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asignaturas a incluir'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.asignaturas
              .map((a) => CheckboxListTile(
                    title: Text(a.nombre),
                    value: _seleccionadas.contains(a.id),
                    onChanged: (v) => setState(() {
                      v == true ? _seleccionadas.add(a.id!) : _seleccionadas.remove(a.id);
                    }),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.asignaturas.where((a) => _seleccionadas.contains(a.id)).toList(),
          ),
          child: const Text('Generar'),
        ),
      ],
    );
  }
}

class _DialogoElegirAsignatura extends StatefulWidget {
  final List<Asignatura> asignaturas;
  final Map<String, String> nombreCurso;

  const _DialogoElegirAsignatura({required this.asignaturas, required this.nombreCurso});

  @override
  State<_DialogoElegirAsignatura> createState() => _DialogoElegirAsignaturaState();
}

class _DialogoElegirAsignaturaState extends State<_DialogoElegirAsignatura> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final q = _busqueda.trim().toLowerCase();
    final filtradas = widget.asignaturas
        .where((a) => q.isEmpty ||
            '${a.nombre} ${widget.nombreCurso[a.cursoId] ?? ''}'.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: const Text('¿En qué asignatura?'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            CampoBusqueda(
              hint: 'Buscar asignatura o curso',
              autofocus: true,
              onChanged: (v) => setState(() => _busqueda = v),
            ),
            Expanded(
              child: filtradas.isEmpty
                  ? const Center(child: Text('Ninguna asignatura coincide.'))
                  : ListView.builder(
                      itemCount: filtradas.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(filtradas[i].nombre),
                        subtitle: Text(widget.nombreCurso[filtradas[i].cursoId] ?? ''),
                        onTap: () => Navigator.pop(context, filtradas[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}

/// Contacto de la familia (solo dirección: colección aparte con reglas
/// propias, ver ContactoAlumno). Plegado por defecto para no ocupar la
/// ficha; se despliega y se edita aquí mismo.
class _TarjetaContacto extends StatefulWidget {
  final String alumnoId;

  const _TarjetaContacto({required this.alumnoId});

  @override
  State<_TarjetaContacto> createState() => _TarjetaContactoState();
}

class _TarjetaContactoState extends State<_TarjetaContacto> {
  final _db = DbService();
  late Future<ContactoAlumno> _futuro = _db.contactoAlumno(widget.alumnoId);

  Future<void> _editar(ContactoAlumno actual) async {
    final nombre = TextEditingController(text: actual.tutorNombre);
    final telefono = TextEditingController(text: actual.tutorTelefono);
    final email = TextEditingController(text: actual.tutorEmail);
    final segundo = TextEditingController(text: actual.segundoTelefono);
    final observaciones = TextEditingController(text: actual.observaciones);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contacto de la familia'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Madre, padre o tutor legal')),
              TextField(
                controller: telefono,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email de la familia'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: segundo,
                decoration: const InputDecoration(labelText: 'Otro teléfono (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: observaciones,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  hintText: 'p. ej. quién le recoge',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Text(
                'Solo dirección puede ver estos datos. No apuntes aquí datos de salud.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _db.guardarContactoAlumno(ContactoAlumno(
        alumnoId: widget.alumnoId,
        tutorNombre: nombre.text.trim(),
        tutorTelefono: telefono.text.trim(),
        tutorEmail: email.text.trim(),
        segundoTelefono: segundo.text.trim(),
        observaciones: observaciones.text.trim(),
      ));
      messenger.showSnackBar(const SnackBar(content: Text('Contacto guardado.')));
      setState(() => _futuro = _db.contactoAlumno(widget.alumnoId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensajeError(e, porDefecto: 'No se pudo guardar el contacto.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContactoAlumno>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.hasError) {
          return const ListTile(
            leading: Icon(Icons.contact_phone_outlined),
            title: Text('No se pudo cargar el contacto de la familia'),
          );
        }
        if (!snap.hasData) return const SizedBox(height: 48);
        final c = snap.data!;
        final lineas = [
          if (c.tutorNombre.isNotEmpty) c.tutorNombre,
          if (c.tutorTelefono.isNotEmpty) 'Tel. ${c.tutorTelefono}',
          if (c.segundoTelefono.isNotEmpty) 'Otro tel. ${c.segundoTelefono}',
          if (c.tutorEmail.isNotEmpty) c.tutorEmail,
          if (c.observaciones.isNotEmpty) c.observaciones,
        ];
        return ListTile(
          leading: const Icon(Icons.contact_phone_outlined),
          title: const Text('Contacto de la familia'),
          subtitle: Text(c.estaVacio ? 'Sin datos todavía.' : lineas.join('\n')),
          isThreeLine: lineas.length > 1,
          trailing: TextButton(
            onPressed: () => _editar(c),
            child: Text(c.estaVacio ? 'Añadir' : 'Editar'),
          ),
        );
      },
    );
  }
}
