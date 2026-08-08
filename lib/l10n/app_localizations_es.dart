// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get comunCancelar => 'Cancelar';

  @override
  String get comunGuardar => 'Guardar';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Contraseña';

  @override
  String get loginIniciarSesion => 'Iniciar sesión';

  @override
  String get loginOlvidasteContrasena => '¿Olvidaste tu contraseña?';

  @override
  String get loginCredencialesIncorrectas => 'Credenciales incorrectas.';

  @override
  String get loginRecuperarContrasenaTitulo => 'Recuperar contraseña';

  @override
  String get loginEnviarEnlace => 'Enviar enlace';

  @override
  String get loginEmailEnviado =>
      'Si el email existe, te hemos enviado un enlace para restablecer la contraseña.';

  @override
  String get loginEmailError =>
      'No se pudo enviar el email. Comprueba la dirección.';

  @override
  String get menuGestionCentro => 'Gestión del centro';

  @override
  String get menuCursosAsignaturas => 'Cursos y asignaturas';

  @override
  String get menuAlumnos => 'Alumnos';

  @override
  String get menuProfesorado => 'Profesorado';

  @override
  String get menuNotasPendientes => 'Notas pendientes';

  @override
  String get menuAsistenciaSinMarcar => 'Asistencia sin marcar';

  @override
  String get menuInformeHoras => 'Informe de horas';

  @override
  String get menuInformeHorasTitulo => 'Informe de horas efectivas';

  @override
  String get menuRegistroHorario => 'Registro horario';

  @override
  String get menuCursoEscolar => 'Curso escolar';

  @override
  String get menuDocencia => 'Docencia';

  @override
  String get menuMisAsignaturas => 'Mis asignaturas';

  @override
  String get menuMiEstudio => 'Mi estudio';

  @override
  String get menuMiJornadaLaboral => 'Mi jornada laboral';

  @override
  String get menuFicharEntradaSalida => 'Fichar entrada/salida';

  @override
  String get menuHerramientas => 'Herramientas';

  @override
  String get menuAfinador => 'Afinador';

  @override
  String get menuMetronomo => 'Metrónomo';

  @override
  String get menuCuadroHonor => 'Cuadro de honor';

  @override
  String get menuCambiarContrasena => 'Cambiar contraseña';

  @override
  String get menuAjustes => 'Ajustes';

  @override
  String get menuModoOscuro => 'Modo oscuro';

  @override
  String get menuCerrarSesion => 'Cerrar sesión';

  @override
  String get menuCerrarSesionConfirmacion =>
      '¿Seguro que quieres cerrar la sesión?';

  @override
  String inicioSaludo(Object nombre) {
    return 'Hola, $nombre';
  }

  @override
  String get inicioElegirSeccion =>
      'Elige una sección desde el menú (☰) para empezar.';

  @override
  String inicioNotasNuevas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tienes $count notas nuevas desde tu última visita.',
      one: 'Tienes 1 nota nueva desde tu última visita.',
    );
    return '$_temp0';
  }

  @override
  String inicioDiasSinEstudiar(int dias) {
    return 'Llevas $dias días sin registrar estudio.';
  }

  @override
  String get ajustesTitulo => 'Ajustes';

  @override
  String get ajustesTamanoLetra => 'Tamaño de letra';

  @override
  String get ajustesTextoEjemplo =>
      'Este es un texto de ejemplo con el tamaño actual.';

  @override
  String get ajustesTamanoIconos => 'Tamaño de los iconos de asignatura';

  @override
  String get ajustesTamanoIconosDescripcion =>
      'Afecta a la cuadrícula de iconos de \"Cursos y asignaturas\" y \"Mis asignaturas\".';

  @override
  String get ajustesConfirmarCierreSesion => 'Confirmar antes de cerrar sesión';

  @override
  String get ajustesConfirmarCierreSesionDescripcion =>
      'Evita cierres accidentales al tocar el menú.';

  @override
  String get ajustesExportacionTitulo => 'Exportación automática de fichajes';

  @override
  String get ajustesExportacionDescripcion =>
      'Al abrir la app tras terminar un mes, se genera solo un Excel con los fichajes de ese mes en esta carpeta. Es una copia de conveniencia: el registro real siempre vive en la base de datos y nunca se puede borrar.';

  @override
  String get ajustesSinConfigurar => 'Sin configurar';

  @override
  String get ajustesElegirCarpeta => 'Elegir carpeta';

  @override
  String get ajustesExportarAhora => 'Exportar mes anterior ahora';

  @override
  String get ajustesExportacionExito =>
      'Exportación del mes anterior generada.';

  @override
  String ajustesExportacionError(Object error) {
    return 'No se pudo exportar: $error';
  }

  @override
  String get ajustesRestablecer => 'Restablecer valores por defecto';

  @override
  String get ajustesIdioma => 'Idioma';

  @override
  String get ajustesIdiomaCastellano => 'Castellano';

  @override
  String get ajustesIdiomaCatalan => 'Català';

  @override
  String get fichajesNoHasFichado => 'Todavía no has fichado hoy';

  @override
  String get fichajesEntrada => 'Entrada';

  @override
  String get fichajesSalida => 'Salida';

  @override
  String get fichajesFicharEntrada => 'Fichar entrada';

  @override
  String get fichajesFicharSalida => 'Fichar salida';

  @override
  String get fichajesJornadaCompletada => 'Jornada de hoy completada.';

  @override
  String get fichajesMiHorarioLaboral => 'Mi horario laboral';

  @override
  String get fichajesSinConfigurar => 'Sin configurar';

  @override
  String fichajesTurnos(int count, int min) {
    return '$count turno(s) · aviso $min min antes';
  }

  @override
  String get fichajesOlvidasteFichar => '¿Olvidaste fichar otro día?';

  @override
  String get fichajesAutoinformar => 'Autoinformar un día pasado sin fichar';

  @override
  String get fichajesEnviadoPendiente =>
      'Enviado. Queda pendiente de que dirección lo valide.';

  @override
  String get fichajesMisUltimosFichajes => 'Mis últimos fichajes';

  @override
  String get fichajesSinFichajes => 'Sin fichajes registrados todavía.';

  @override
  String get fichajesSinTurnos => 'Sin turnos configurados todavía.';

  @override
  String get fichajesPendienteValidar => 'Pendiente de validar por dirección';

  @override
  String get fichajesDiaSemana => 'Día de la semana';

  @override
  String get fichajesAnadirTurno => 'Añadir turno';

  @override
  String get fichajesAvisarAntes => 'Avisar antes de fichar (min):';

  @override
  String get fichajesEligeOlvidaste => 'Elige el día que olvidaste fichar';

  @override
  String get fichajesHoraEntrada => 'Hora de entrada';

  @override
  String get fichajesHoraSalida => 'Hora de salida';

  @override
  String fichajesErrorCarga(Object error) {
    return 'No se pudo cargar el fichaje: $error';
  }

  @override
  String get fichajesCorregido => '(corregido)';

  @override
  String get diaLunes => 'Lunes';

  @override
  String get diaMartes => 'Martes';

  @override
  String get diaMiercoles => 'Miércoles';

  @override
  String get diaJueves => 'Jueves';

  @override
  String get diaViernes => 'Viernes';

  @override
  String get diaSabado => 'Sábado';

  @override
  String get diaDomingo => 'Domingo';

  @override
  String get grabarEstudioTitulo => 'Registrar estudio';

  @override
  String grabarEstudioEfectivo(Object tiempo) {
    return 'Efectivo: $tiempo';
  }

  @override
  String grabarEstudioTotal(Object tiempo) {
    return 'Total: $tiempo';
  }
}
