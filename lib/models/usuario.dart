enum Rol { alumno, profesor, direccion }

Rol rolDesdeTexto(String texto) {
  switch (texto) {
    case 'profesor':
      return Rol.profesor;
    case 'direccion':
      return Rol.direccion;
    case 'alumno':
    default:
      return Rol.alumno;
  }
}

String rolATexto(Rol rol) => rol.name;

class Usuario {
  final String uid;
  final String nombre;
  final String email;
  final Rol rol;
  final String? instrumento; // solo relevante si rol == alumno
  final String? centroId;
  final DateTime createdAt;

  Usuario({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.rol,
    this.instrumento,
    this.centroId,
    required this.createdAt,
  });

  factory Usuario.fromMap(String uid, Map<String, dynamic> data) {
    return Usuario(
      uid: uid,
      nombre: data['nombre'] ?? '',
      email: data['email'] ?? '',
      rol: rolDesdeTexto(data['rol'] ?? 'alumno'),
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
      'rol': rolATexto(rol),
      'instrumento': instrumento,
      'centroId': centroId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
