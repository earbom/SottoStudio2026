import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usuario.dart';

/// Gestiona login, registro y sesión con Firebase Auth.
/// El documento en `usuarios/{uid}` se crea SIEMPRE con rol 'alumno'
/// desde el cliente (ver firestore.rules) — subir a profesor/direccion
/// se hace manualmente desde la consola de Firebase o con Admin SDK.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get cambiosDeUsuario => _auth.authStateChanges();
  User? get usuarioActual => _auth.currentUser;

  /// Valida la contraseña con la misma regla estricta definida en el
  /// PDF original: mínimo 8 caracteres, mayúscula, minúscula, dígito
  /// y símbolo.
  bool contrasenaValida(String password) {
    final tieneLongitud = password.length >= 8;
    final tieneMayuscula = RegExp(r'[A-Z]').hasMatch(password);
    final tieneMinuscula = RegExp(r'[a-z]').hasMatch(password);
    final tieneDigito = RegExp(r'\d').hasMatch(password);
    final tieneSimbolo = RegExp(r'[@#$%^&+=!]').hasMatch(password);
    return tieneLongitud &&
        tieneMayuscula &&
        tieneMinuscula &&
        tieneDigito &&
        tieneSimbolo;
  }

  Future<Usuario> registrar({
    required String nombre,
    required String email,
    required String password,
    String? instrumento,
    String? centroId,
  }) async {
    if (!contrasenaValida(password)) {
      throw Exception(
          'La contraseña debe tener al menos 8 caracteres, mayúscula, minúscula, dígito y símbolo.');
    }

    final credencial = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credencial.user!.uid;
    final usuario = Usuario(
      uid: uid,
      nombre: nombre,
      email: email,
      rol: Rol.alumno,
      instrumento: instrumento,
      centroId: centroId,
      createdAt: DateTime.now(),
    );

    await _db.collection('usuarios').doc(uid).set(usuario.toMap());
    return usuario;
  }

  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> cerrarSesion() async {
    await _auth.signOut();
  }

  Future<Usuario?> obtenerPerfil(String uid) async {
    final doc = await _db.collection('usuarios').doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap(uid, doc.data()!);
  }
}
