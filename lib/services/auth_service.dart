import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/usuario.dart';

/// Gestiona login, registro y sesión con Firebase Auth.
/// El documento en `usuarios/{uid}` se crea SIEMPRE con permisos
/// {alumno} desde el autorregistro (ver firestore.rules) — subir a
/// profesor/direccion se hace manualmente desde la consola de Firebase
/// o con Admin SDK.
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
    final tieneSimbolo = RegExp(r'[@#$%^&+=!_-]').hasMatch(password);
    return tieneLongitud &&
        tieneMayuscula &&
        tieneMinuscula &&
        tieneDigito &&
        tieneSimbolo;
  }

  /// Genera una contraseña temporal que cumple `contrasenaValida`, para
  /// mostrarla una vez a dirección y que la releve al alumno/familia.
  String generarPasswordTemporal() {
    const mayus = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // sin O/I ambiguas
    const minus = 'abcdefghijkmnpqrstuvwxyz';
    const digitos = '23456789';
    const simbolos = '@#\$%^&+=!_-';
    final rand = Random.secure();
    String elegir(String c) => c[rand.nextInt(c.length)];
    final chars = [elegir(mayus), elegir(minus), elegir(digitos), elegir(simbolos)];
    const todos = mayus + minus + digitos + simbolos;
    for (var i = 0; i < 6; i++) {
      chars.add(elegir(todos));
    }
    chars.shuffle(rand);
    return chars.join();
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
      permisos: {Permiso.alumno},
      instrumento: instrumento,
      centroId: centroId,
      createdAt: DateTime.now(),
    );

    await _db.collection('usuarios').doc(uid).set(usuario.toMap());
    return usuario;
  }

  /// Alta ágil de alumno o profesor desde el panel de dirección. No hay
  /// Cloud Functions desplegadas (falta plan Blaze, ver CLAUDE.md), así
  /// que para crear la cuenta de Firebase Auth sin cerrar la sesión de
  /// dirección se usa una FirebaseApp secundaria efímera solo para el
  /// alta en Auth; el documento de Firestore se escribe con la app
  /// PRIMARIA, que sigue autenticada como dirección (firestore.rules
  /// permite a dirección crear cualquier doc en `usuarios`).
  ///
  /// Workaround temporal: cuando el centro contrate el plan Blaze,
  /// migrar esto a una Cloud Function invocable con Admin SDK.
  Future<String> _crearUsuarioConPermiso({
    required String nombre,
    String? apellidos,
    required String email,
    required Permiso permiso,
    String? instrumento,
    String? centroId,
  }) async {
    final passwordTemporal = generarPasswordTemporal();
    final nombreApp = 'tempAdmin_${DateTime.now().microsecondsSinceEpoch}';
    final appSecundaria = await Firebase.initializeApp(
      name: nombreApp,
      options: Firebase.app().options,
    );
    try {
      final authSecundario = FirebaseAuth.instanceFor(app: appSecundaria);
      final credencial = await authSecundario.createUserWithEmailAndPassword(
        email: email,
        password: passwordTemporal,
      );
      final uid = credencial.user!.uid;
      final usuario = Usuario(
        uid: uid,
        nombre: nombre,
        apellidos: apellidos,
        email: email,
        permisos: {permiso},
        instrumento: instrumento,
        centroId: centroId,
        createdAt: DateTime.now(),
      );
      await _db.collection('usuarios').doc(uid).set(usuario.toMap());
      await authSecundario.signOut();
      return passwordTemporal;
    } finally {
      await appSecundaria.delete();
    }
  }

  Future<String> crearAlumno({
    required String nombre,
    String? apellidos,
    required String email,
    String? instrumento,
    String? centroId,
  }) {
    return _crearUsuarioConPermiso(
      nombre: nombre,
      apellidos: apellidos,
      email: email,
      permiso: Permiso.alumno,
      instrumento: instrumento,
      centroId: centroId,
    );
  }

  /// Alumno SIN cuenta de acceso (no usará la app: muy joven, o
  /// decide no hacerlo) — igualmente matriculable y puntuable por un
  /// profesor. A diferencia de `crearAlumno`, no toca Firebase Auth en
  /// absoluto: escribe directamente el documento en `usuarios` con un
  /// ID autogenerado de Firestore — las reglas ya permiten a
  /// dirección crear un documento en `usuarios` con cualquier id, no
  /// necesariamente un uid real de Auth. Ver CLAUDE.md.
  Future<String> crearAlumnoSinCuenta({
    required String nombre,
    String? apellidos,
    String? instrumento,
    String? centroId,
  }) async {
    final ref = _db.collection('usuarios').doc();
    final usuario = Usuario(
      uid: ref.id,
      nombre: nombre,
      apellidos: apellidos,
      email: null,
      permisos: {Permiso.alumno},
      instrumento: instrumento,
      centroId: centroId,
      createdAt: DateTime.now(),
      tieneCuenta: false,
    );
    await ref.set(usuario.toMap());
    return ref.id;
  }

  Future<String> crearProfesor({
    required String nombre,
    required String email,
    String? centroId,
  }) {
    return _crearUsuarioConPermiso(
      nombre: nombre,
      email: email,
      permiso: Permiso.profesor,
      centroId: centroId,
    );
  }

  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Envía el email de restablecimiento de contraseña estándar de
  /// Firebase Auth (enlace a una página alojada por Firebase, sin
  /// backend propio necesario). Accesible desde la pantalla de login.
  Future<void> enviarEmailDeRecuperacion(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Cambia la contraseña del usuario ya autenticado. Requiere
  /// reautenticar con la contraseña actual porque Firebase exige un
  /// login "reciente" para operaciones sensibles como esta.
  Future<void> cambiarPassword({
    required String passwordActual,
    required String passwordNueva,
  }) async {
    if (!contrasenaValida(passwordNueva)) {
      throw Exception(
          'La contraseña debe tener al menos 8 caracteres, mayúscula, minúscula, dígito y símbolo.');
    }
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No hay sesión activa.');
    }
    final credencial = EmailAuthProvider.credential(email: user.email!, password: passwordActual);
    await user.reauthenticateWithCredential(credencial);
    await user.updatePassword(passwordNueva);
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
