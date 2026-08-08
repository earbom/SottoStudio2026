enum Permiso { alumno, profesor, direccion }

Permiso? permisoDesdeTexto(String texto) {
  switch (texto) {
    case 'alumno':
      return Permiso.alumno;
    case 'profesor':
      return Permiso.profesor;
    case 'direccion':
      return Permiso.direccion;
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
  final String email;
  final Set<Permiso> permisos;
  final String? instrumento; // solo relevante si tiene permiso alumno
  final String? centroId;
  final DateTime createdAt;

  Usuario({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.permisos,
    this.instrumento,
    this.centroId,
    required this.createdAt,
  });

  bool tienePermiso(Permiso p) => permisos.contains(p);
  bool get esAlumno => tienePermiso(Permiso.alumno);
  bool get esProfesor => tienePermiso(Permiso.profesor);
  bool get esDireccion => tienePermiso(Permiso.direccion);

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
      email: data['email'] ?? '',
      permisos: permisos.isEmpty ? {Permiso.alumno} : permisos,
      instrumento: data['instrumento'],
      centroId: data['centroId'],
      createdAt: (data['createdAt'] is DateTime)
          ? data['createdAt']
          : DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'email': email,
      'permisos': permisos.map((p) => p.name).toList(),
      'instrumento': instrumento,
      'centroId': centroId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
