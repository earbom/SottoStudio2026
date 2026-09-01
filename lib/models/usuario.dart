// `desarrollador` es una cuenta especial única (la de Edgar, fijada a
// mano por consola de Firebase junto a los otros 3 permisos, ver
// CLAUDE.md) — nunca se ofrece como opción en ninguna pantalla de alta
// de cuentas (ninguna itera Permiso.values, todas fijan un valor
// literal). Da acceso al panel de incidencias y al "modo de vista"
// para simular un único rol sin necesitar varias cuentas de prueba.
enum Permiso { alumno, profesor, direccion, desarrollador }

Permiso? permisoDesdeTexto(String texto) {
  switch (texto) {
    case 'alumno':
      return Permiso.alumno;
    case 'profesor':
      return Permiso.profesor;
    case 'direccion':
      return Permiso.direccion;
    case 'desarrollador':
      return Permiso.desarrollador;
    default:
      return null;
  }
}

Set<Permiso> permisosDesdeLista(List<dynamic>? lista) {
  if (lista == null) return {};
  return lista
      .map((e) => permisoDesdeTexto(e.toString()))
      .whereType<Permiso>()
      .toSet();
}

class Usuario {
  final String uid;
  final String nombre;
  final String? apellidos; // opcional: cuentas antiguas no lo tienen, se ordena por nombre
  // Nullable: un alumno sin cuenta de acceso (ver tieneCuenta) no
  // tiene email ni cuenta de Firebase Auth detrás — sigue existiendo
  // en Firestore para poder matricularlo/puntuarlo. Ver CLAUDE.md.
  final String? email;
  final Set<Permiso> permisos;
  final String? instrumento; // solo relevante si tiene permiso alumno
  final String? centroId;
  final DateTime createdAt;
  // false = alumno SIN cuenta de Firebase Auth (muy joven, o decide no
  // usar la app) — creado con DbService/AuthService.crearAlumnoSinCuenta,
  // id autogenerado de Firestore en vez de un uid real. Default true:
  // toda cuenta creada antes de este campo tenía cuenta real. Ver
  // CLAUDE.md.
  final bool tieneCuenta;

  Usuario({
    required this.uid,
    required this.nombre,
    this.apellidos,
    this.email,
    required this.permisos,
    this.instrumento,
    this.centroId,
    required this.createdAt,
    this.tieneCuenta = true,
  });

  bool tienePermiso(Permiso p) => permisos.contains(p);
  bool get esAlumno => tienePermiso(Permiso.alumno);
  bool get esProfesor => tienePermiso(Permiso.profesor);
  bool get esDireccion => tienePermiso(Permiso.direccion);
  bool get esDesarrollador => tienePermiso(Permiso.desarrollador);

  /// Copia narrowed/ampliada usada por el modo desarrollador para
  /// simular un único permiso en la UI sin tocar el documento real de
  /// Firestore (que sigue teniendo los 4 permisos, para que las
  /// reglas de seguridad concedan todo lo que un rol real necesitaría
  /// — ver CLAUDE.md). Todo lo demás (uid, nombre, email...) se
  /// conserva igual.
  Usuario copiarConPermisos(Set<Permiso> nuevosPermisos) => Usuario(
        uid: uid,
        nombre: nombre,
        apellidos: apellidos,
        email: email,
        permisos: nuevosPermisos,
        instrumento: instrumento,
        centroId: centroId,
        createdAt: createdAt,
        tieneCuenta: tieneCuenta,
      );

  // Igualdad por uid (no por identidad de objeto): imprescindible para
  // widgets como DropdownButtonFormField<Usuario>, cuya lista de items
  // viene de un StreamBuilder en vivo — cada reemisión crea instancias
  // nuevas aunque los datos no cambien, y sin esto Flutter no
  // encuentra el valor seleccionado entre los items (crash).
  @override
  bool operator ==(Object other) => other is Usuario && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;

  factory Usuario.fromMap(String uid, Map<String, dynamic> data) {
    // Si el documento viniera corrupto o vacío, mínimo privilegio: alumno.
    final permisos = permisosDesdeLista(data['permisos'] as List<dynamic>?);
    return Usuario(
      uid: uid,
      nombre: data['nombre'] ?? '',
      apellidos: data['apellidos'],
      email: data['email'],
      permisos: permisos.isEmpty ? {Permiso.alumno} : permisos,
      instrumento: data['instrumento'],
      centroId: data['centroId'],
      createdAt: (data['createdAt'] is DateTime)
          ? data['createdAt']
          : DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
              DateTime.now(),
      tieneCuenta: data['tieneCuenta'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'apellidos': apellidos,
      'email': email,
      'permisos': permisos.map((p) => p.name).toList(),
      'instrumento': instrumento,
      'centroId': centroId,
      'createdAt': createdAt.toIso8601String(),
      'tieneCuenta': tieneCuenta,
    };
  }
}
