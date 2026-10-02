import 'package:firebase_auth/firebase_auth.dart';

/// Convierte una excepción en un texto que dirección/profesorado pueda
/// entender, en vez de mostrar el error técnico tal cual
/// ("[cloud_firestore/permission-denied] ..."). Los `Exception('...')`
/// que lanza nuestro propio código ya traen un mensaje pensado para el
/// usuario y se muestran sin el prefijo "Exception: ".
String mensajeError(Object e, {required String porDefecto}) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese email.';
      case 'invalid-email':
        return 'El email no tiene un formato válido.';
      case 'weak-password':
        return 'La contraseña es demasiado corta (mínimo 6 caracteres).';
      case 'wrong-password':
      case 'invalid-credential':
        return 'La contraseña actual no es correcta.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Inténtalo de nuevo.';
    }
    return porDefecto;
  }
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'No tienes permiso para hacer esto.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión a internet. Inténtalo de nuevo.';
    }
    return porDefecto;
  }
  if (e is FormatException) return e.message;
  final texto = e.toString();
  if (e is Exception && texto.startsWith('Exception: ')) {
    return texto.substring('Exception: '.length);
  }
  return porDefecto;
}
