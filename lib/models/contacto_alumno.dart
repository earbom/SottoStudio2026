/// Datos de contacto de la familia de un alumno (`contactosAlumno/
/// {alumnoId}`). Van en una colección APARTE de `usuarios` a propósito:
/// `usuarios` lo puede leer cualquier profesor, y estos son datos
/// personales de menores que solo necesita dirección (RGPD, mínimo
/// privilegio — ver CLAUDE.md). Sin datos de salud: "observaciones" es
/// texto libre para cosas como "recoge el abuelo los martes".
class ContactoAlumno {
  final String alumnoId;
  final String tutorNombre;
  final String tutorTelefono;
  final String tutorEmail;
  final String segundoTelefono;
  final String observaciones;

  const ContactoAlumno({
    required this.alumnoId,
    this.tutorNombre = '',
    this.tutorTelefono = '',
    this.tutorEmail = '',
    this.segundoTelefono = '',
    this.observaciones = '',
  });

  bool get estaVacio =>
      tutorNombre.isEmpty &&
      tutorTelefono.isEmpty &&
      tutorEmail.isEmpty &&
      segundoTelefono.isEmpty &&
      observaciones.isEmpty;

  factory ContactoAlumno.fromMap(String alumnoId, Map<String, dynamic> data) {
    return ContactoAlumno(
      alumnoId: alumnoId,
      tutorNombre: data['tutorNombre'] ?? '',
      tutorTelefono: data['tutorTelefono'] ?? '',
      tutorEmail: data['tutorEmail'] ?? '',
      segundoTelefono: data['segundoTelefono'] ?? '',
      observaciones: data['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'tutorNombre': tutorNombre,
        'tutorTelefono': tutorTelefono,
        'tutorEmail': tutorEmail,
        'segundoTelefono': segundoTelefono,
        'observaciones': observaciones,
        'actualizadoEn': DateTime.now().toIso8601String(),
      };
}
