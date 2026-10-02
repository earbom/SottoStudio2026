import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ca.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ca'),
    Locale('es')
  ];

  /// No description provided for @comunCancelar.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get comunCancelar;

  /// No description provided for @comunGuardar.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get comunGuardar;

  /// No description provided for @loginEmail.
  ///
  /// In es, this message translates to:
  /// **'Email'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get loginPassword;

  /// No description provided for @loginIniciarSesion.
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get loginIniciarSesion;

  /// No description provided for @loginOlvidasteContrasena.
  ///
  /// In es, this message translates to:
  /// **'¿Olvidaste tu contraseña?'**
  String get loginOlvidasteContrasena;

  /// No description provided for @loginCredencialesIncorrectas.
  ///
  /// In es, this message translates to:
  /// **'Credenciales incorrectas.'**
  String get loginCredencialesIncorrectas;

  /// No description provided for @loginRecuperarContrasenaTitulo.
  ///
  /// In es, this message translates to:
  /// **'Recuperar contraseña'**
  String get loginRecuperarContrasenaTitulo;

  /// No description provided for @loginEnviarEnlace.
  ///
  /// In es, this message translates to:
  /// **'Enviar enlace'**
  String get loginEnviarEnlace;

  /// No description provided for @loginEmailEnviado.
  ///
  /// In es, this message translates to:
  /// **'Si el email existe, te hemos enviado un enlace para restablecer la contraseña.'**
  String get loginEmailEnviado;

  /// No description provided for @loginEmailError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo enviar el email. Comprueba la dirección.'**
  String get loginEmailError;

  /// No description provided for @menuInicio.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get menuInicio;

  /// No description provided for @menuConfiguracionCentro.
  ///
  /// In es, this message translates to:
  /// **'Configuración del centro'**
  String get menuConfiguracionCentro;

  /// No description provided for @menuAyuda.
  ///
  /// In es, this message translates to:
  /// **'Ayuda'**
  String get menuAyuda;

  /// No description provided for @inicioBienvenidaTitulo.
  ///
  /// In es, this message translates to:
  /// **'¿Primera vez en Sotto Studio?'**
  String get inicioBienvenidaTitulo;

  /// No description provided for @inicioBienvenidaTexto.
  ///
  /// In es, this message translates to:
  /// **'En la Ayuda tienes, paso a paso, cómo hacer cada tarea. También la encontrarás siempre en el menú (☰).'**
  String get inicioBienvenidaTexto;

  /// No description provided for @inicioBienvenidaVerAyuda.
  ///
  /// In es, this message translates to:
  /// **'Ver la ayuda'**
  String get inicioBienvenidaVerAyuda;

  /// No description provided for @inicioBienvenidaCerrar.
  ///
  /// In es, this message translates to:
  /// **'Entendido'**
  String get inicioBienvenidaCerrar;

  /// No description provided for @menuGestionCentro.
  ///
  /// In es, this message translates to:
  /// **'Gestión del centro'**
  String get menuGestionCentro;

  /// No description provided for @menuCursosAsignaturas.
  ///
  /// In es, this message translates to:
  /// **'Asignaturas'**
  String get menuCursosAsignaturas;

  /// No description provided for @menuGestionarCursos.
  ///
  /// In es, this message translates to:
  /// **'Gestionar cursos'**
  String get menuGestionarCursos;

  /// No description provided for @menuAlumnos.
  ///
  /// In es, this message translates to:
  /// **'Alumnos'**
  String get menuAlumnos;

  /// No description provided for @menuProfesorado.
  ///
  /// In es, this message translates to:
  /// **'Profesorado'**
  String get menuProfesorado;

  /// No description provided for @menuNotasPendientes.
  ///
  /// In es, this message translates to:
  /// **'Notas pendientes'**
  String get menuNotasPendientes;

  /// No description provided for @menuAsistenciaSinMarcar.
  ///
  /// In es, this message translates to:
  /// **'Asistencia sin marcar'**
  String get menuAsistenciaSinMarcar;

  /// No description provided for @menuInformeHoras.
  ///
  /// In es, this message translates to:
  /// **'Informe de horas'**
  String get menuInformeHoras;

  /// No description provided for @menuInformeHorasTitulo.
  ///
  /// In es, this message translates to:
  /// **'Informe de horas de estudio'**
  String get menuInformeHorasTitulo;

  /// No description provided for @menuRegistroHorario.
  ///
  /// In es, this message translates to:
  /// **'Registro horario'**
  String get menuRegistroHorario;

  /// No description provided for @menuCursoEscolar.
  ///
  /// In es, this message translates to:
  /// **'Curso escolar'**
  String get menuCursoEscolar;

  /// No description provided for @menuImportarDatos.
  ///
  /// In es, this message translates to:
  /// **'Importar datos desde Excel'**
  String get menuImportarDatos;

  /// No description provided for @menuPlusesOrquesta.
  ///
  /// In es, this message translates to:
  /// **'Pluses de orquesta'**
  String get menuPlusesOrquesta;

  /// No description provided for @menuHorarioGeneral.
  ///
  /// In es, this message translates to:
  /// **'Horario general'**
  String get menuHorarioGeneral;

  /// No description provided for @menuDocencia.
  ///
  /// In es, this message translates to:
  /// **'Docencia'**
  String get menuDocencia;

  /// No description provided for @menuMisAsignaturas.
  ///
  /// In es, this message translates to:
  /// **'Mis asignaturas'**
  String get menuMisAsignaturas;

  /// No description provided for @menuMiEstudio.
  ///
  /// In es, this message translates to:
  /// **'Mi estudio'**
  String get menuMiEstudio;

  /// No description provided for @menuMedallasRoscos.
  ///
  /// In es, this message translates to:
  /// **'Medallas y roscos'**
  String get menuMedallasRoscos;

  /// No description provided for @menuMiHorario.
  ///
  /// In es, this message translates to:
  /// **'Mi horario'**
  String get menuMiHorario;

  /// No description provided for @menuMiJornadaLaboral.
  ///
  /// In es, this message translates to:
  /// **'Mi jornada laboral'**
  String get menuMiJornadaLaboral;

  /// No description provided for @menuFicharEntradaSalida.
  ///
  /// In es, this message translates to:
  /// **'Fichar entrada/salida'**
  String get menuFicharEntradaSalida;

  /// No description provided for @menuHerramientas.
  ///
  /// In es, this message translates to:
  /// **'Herramientas'**
  String get menuHerramientas;

  /// No description provided for @menuAfinador.
  ///
  /// In es, this message translates to:
  /// **'Afinador'**
  String get menuAfinador;

  /// No description provided for @menuMetronomo.
  ///
  /// In es, this message translates to:
  /// **'Metrónomo'**
  String get menuMetronomo;

  /// No description provided for @menuCuadroHonor.
  ///
  /// In es, this message translates to:
  /// **'Cuadro de honor'**
  String get menuCuadroHonor;

  /// No description provided for @menuReportarProblema.
  ///
  /// In es, this message translates to:
  /// **'Informar de un problema o sugerencia'**
  String get menuReportarProblema;

  /// No description provided for @menuModoDesarrollador.
  ///
  /// In es, this message translates to:
  /// **'Modo desarrollador'**
  String get menuModoDesarrollador;

  /// No description provided for @menuModoVista.
  ///
  /// In es, this message translates to:
  /// **'Modo de vista'**
  String get menuModoVista;

  /// No description provided for @menuIncidencias.
  ///
  /// In es, this message translates to:
  /// **'Incidencias'**
  String get menuIncidencias;

  /// No description provided for @menuCambiarContrasena.
  ///
  /// In es, this message translates to:
  /// **'Cambiar contraseña'**
  String get menuCambiarContrasena;

  /// No description provided for @menuAjustes.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get menuAjustes;

  /// No description provided for @menuModoOscuro.
  ///
  /// In es, this message translates to:
  /// **'Modo oscuro'**
  String get menuModoOscuro;

  /// No description provided for @menuCerrarSesion.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get menuCerrarSesion;

  /// No description provided for @menuCerrarSesionConfirmacion.
  ///
  /// In es, this message translates to:
  /// **'¿Seguro que quieres cerrar la sesión?'**
  String get menuCerrarSesionConfirmacion;

  /// No description provided for @inicioSaludo.
  ///
  /// In es, this message translates to:
  /// **'Hola, {nombre}'**
  String inicioSaludo(Object nombre);

  /// No description provided for @inicioElegirSeccion.
  ///
  /// In es, this message translates to:
  /// **'Elige una sección desde el menú (☰) para empezar.'**
  String get inicioElegirSeccion;

  /// No description provided for @inicioNotasNuevas.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Tienes 1 nota nueva desde tu última visita.} other{Tienes {count} notas nuevas desde tu última visita.}}'**
  String inicioNotasNuevas(int count);

  /// No description provided for @inicioDiasSinEstudiar.
  ///
  /// In es, this message translates to:
  /// **'Llevas {dias} días sin registrar estudio.'**
  String inicioDiasSinEstudiar(int dias);

  /// No description provided for @ajustesTitulo.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get ajustesTitulo;

  /// No description provided for @ajustesTamanoLetra.
  ///
  /// In es, this message translates to:
  /// **'Tamaño de letra'**
  String get ajustesTamanoLetra;

  /// No description provided for @ajustesTextoEjemplo.
  ///
  /// In es, this message translates to:
  /// **'Este es un texto de ejemplo con el tamaño actual.'**
  String get ajustesTextoEjemplo;

  /// No description provided for @ajustesTamanoIconos.
  ///
  /// In es, this message translates to:
  /// **'Tamaño de los iconos de asignatura'**
  String get ajustesTamanoIconos;

  /// No description provided for @ajustesTamanoIconosDescripcion.
  ///
  /// In es, this message translates to:
  /// **'Afecta a la cuadrícula de iconos de \"Asignaturas\" y \"Mis asignaturas\".'**
  String get ajustesTamanoIconosDescripcion;

  /// No description provided for @ajustesConfirmarCierreSesion.
  ///
  /// In es, this message translates to:
  /// **'Confirmar antes de cerrar sesión'**
  String get ajustesConfirmarCierreSesion;

  /// No description provided for @ajustesConfirmarCierreSesionDescripcion.
  ///
  /// In es, this message translates to:
  /// **'Evita cierres accidentales al tocar el menú.'**
  String get ajustesConfirmarCierreSesionDescripcion;

  /// No description provided for @ajustesExportacionTitulo.
  ///
  /// In es, this message translates to:
  /// **'Exportación automática de fichajes'**
  String get ajustesExportacionTitulo;

  /// No description provided for @ajustesExportacionDescripcion.
  ///
  /// In es, this message translates to:
  /// **'Al abrir la app tras terminar un mes, se genera solo un Excel con los fichajes de ese mes en esta carpeta. Es una copia de conveniencia: el registro real siempre vive en la base de datos y nunca se puede borrar.'**
  String get ajustesExportacionDescripcion;

  /// No description provided for @ajustesSinConfigurar.
  ///
  /// In es, this message translates to:
  /// **'Sin configurar'**
  String get ajustesSinConfigurar;

  /// No description provided for @ajustesElegirCarpeta.
  ///
  /// In es, this message translates to:
  /// **'Elegir carpeta'**
  String get ajustesElegirCarpeta;

  /// No description provided for @ajustesExportarAhora.
  ///
  /// In es, this message translates to:
  /// **'Exportar mes anterior ahora'**
  String get ajustesExportarAhora;

  /// No description provided for @ajustesExportacionExito.
  ///
  /// In es, this message translates to:
  /// **'Exportación del mes anterior generada.'**
  String get ajustesExportacionExito;

  /// No description provided for @ajustesExportacionError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo exportar: {error}'**
  String ajustesExportacionError(Object error);

  /// No description provided for @ajustesAsistenteTitulo.
  ///
  /// In es, this message translates to:
  /// **'Asistente (Claude)'**
  String get ajustesAsistenteTitulo;

  /// No description provided for @ajustesAsistenteDescripcion.
  ///
  /// In es, this message translates to:
  /// **'URL del servidor propio del centro que conecta el botón del asistente con la API de Claude. La clave de la API vive solo en ese servidor, nunca en esta app.'**
  String get ajustesAsistenteDescripcion;

  /// No description provided for @ajustesAsistenteUrlLabel.
  ///
  /// In es, this message translates to:
  /// **'URL del servidor'**
  String get ajustesAsistenteUrlLabel;

  /// No description provided for @ajustesAsistenteGuardar.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get ajustesAsistenteGuardar;

  /// No description provided for @ajustesRestablecer.
  ///
  /// In es, this message translates to:
  /// **'Restablecer valores por defecto'**
  String get ajustesRestablecer;

  /// No description provided for @ajustesIdioma.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get ajustesIdioma;

  /// No description provided for @ajustesIdiomaCastellano.
  ///
  /// In es, this message translates to:
  /// **'Castellano'**
  String get ajustesIdiomaCastellano;

  /// No description provided for @ajustesIdiomaCatalan.
  ///
  /// In es, this message translates to:
  /// **'Català'**
  String get ajustesIdiomaCatalan;

  /// No description provided for @fichajesNoHasFichado.
  ///
  /// In es, this message translates to:
  /// **'Todavía no has fichado hoy'**
  String get fichajesNoHasFichado;

  /// No description provided for @fichajesEntrada.
  ///
  /// In es, this message translates to:
  /// **'Entrada'**
  String get fichajesEntrada;

  /// No description provided for @fichajesSalida.
  ///
  /// In es, this message translates to:
  /// **'Salida'**
  String get fichajesSalida;

  /// No description provided for @fichajesConfirmarHora.
  ///
  /// In es, this message translates to:
  /// **'Se registrará a las {hora}. Una vez fichado no se puede cambiar (solo dirección puede corregirlo).'**
  String fichajesConfirmarHora(Object hora);

  /// No description provided for @fichajesFicharEntrada.
  ///
  /// In es, this message translates to:
  /// **'Fichar entrada'**
  String get fichajesFicharEntrada;

  /// No description provided for @fichajesFicharSalida.
  ///
  /// In es, this message translates to:
  /// **'Fichar salida'**
  String get fichajesFicharSalida;

  /// No description provided for @fichajesJornadaCompletada.
  ///
  /// In es, this message translates to:
  /// **'Jornada de hoy completada.'**
  String get fichajesJornadaCompletada;

  /// No description provided for @fichajesMiHorarioLaboral.
  ///
  /// In es, this message translates to:
  /// **'Mi horario laboral'**
  String get fichajesMiHorarioLaboral;

  /// No description provided for @fichajesSinConfigurar.
  ///
  /// In es, this message translates to:
  /// **'Sin configurar'**
  String get fichajesSinConfigurar;

  /// No description provided for @fichajesTurnos.
  ///
  /// In es, this message translates to:
  /// **'{count} turno(s) · aviso {min} min antes'**
  String fichajesTurnos(int count, int min);

  /// No description provided for @fichajesOlvidasteFichar.
  ///
  /// In es, this message translates to:
  /// **'¿Olvidaste fichar otro día?'**
  String get fichajesOlvidasteFichar;

  /// No description provided for @fichajesAutoinformar.
  ///
  /// In es, this message translates to:
  /// **'Autoinformar un día pasado sin fichar'**
  String get fichajesAutoinformar;

  /// No description provided for @fichajesEnviadoPendiente.
  ///
  /// In es, this message translates to:
  /// **'Enviado. Queda pendiente de que dirección lo valide.'**
  String get fichajesEnviadoPendiente;

  /// No description provided for @fichajesMisUltimosFichajes.
  ///
  /// In es, this message translates to:
  /// **'Mis últimos fichajes'**
  String get fichajesMisUltimosFichajes;

  /// No description provided for @fichajesSinFichajes.
  ///
  /// In es, this message translates to:
  /// **'Sin fichajes registrados todavía.'**
  String get fichajesSinFichajes;

  /// No description provided for @fichajesSinTurnos.
  ///
  /// In es, this message translates to:
  /// **'Sin turnos configurados todavía.'**
  String get fichajesSinTurnos;

  /// No description provided for @fichajesPendienteValidar.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de validar por dirección'**
  String get fichajesPendienteValidar;

  /// No description provided for @fichajesDiaSemana.
  ///
  /// In es, this message translates to:
  /// **'Día de la semana'**
  String get fichajesDiaSemana;

  /// No description provided for @fichajesAnadirTurno.
  ///
  /// In es, this message translates to:
  /// **'Añadir turno'**
  String get fichajesAnadirTurno;

  /// No description provided for @fichajesAvisarAntes.
  ///
  /// In es, this message translates to:
  /// **'Avisar antes de fichar (min):'**
  String get fichajesAvisarAntes;

  /// No description provided for @fichajesEligeOlvidaste.
  ///
  /// In es, this message translates to:
  /// **'Elige el día que olvidaste fichar'**
  String get fichajesEligeOlvidaste;

  /// No description provided for @fichajesHoraEntrada.
  ///
  /// In es, this message translates to:
  /// **'Hora de entrada'**
  String get fichajesHoraEntrada;

  /// No description provided for @fichajesHoraSalida.
  ///
  /// In es, this message translates to:
  /// **'Hora de salida'**
  String get fichajesHoraSalida;

  /// No description provided for @fichajesErrorCarga.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar el fichaje: {error}'**
  String fichajesErrorCarga(Object error);

  /// No description provided for @fichajesCorregido.
  ///
  /// In es, this message translates to:
  /// **'(corregido)'**
  String get fichajesCorregido;

  /// No description provided for @diaLunes.
  ///
  /// In es, this message translates to:
  /// **'Lunes'**
  String get diaLunes;

  /// No description provided for @diaMartes.
  ///
  /// In es, this message translates to:
  /// **'Martes'**
  String get diaMartes;

  /// No description provided for @diaMiercoles.
  ///
  /// In es, this message translates to:
  /// **'Miércoles'**
  String get diaMiercoles;

  /// No description provided for @diaJueves.
  ///
  /// In es, this message translates to:
  /// **'Jueves'**
  String get diaJueves;

  /// No description provided for @diaViernes.
  ///
  /// In es, this message translates to:
  /// **'Viernes'**
  String get diaViernes;

  /// No description provided for @diaSabado.
  ///
  /// In es, this message translates to:
  /// **'Sábado'**
  String get diaSabado;

  /// No description provided for @diaDomingo.
  ///
  /// In es, this message translates to:
  /// **'Domingo'**
  String get diaDomingo;

  /// No description provided for @grabarEstudioTitulo.
  ///
  /// In es, this message translates to:
  /// **'Registrar estudio'**
  String get grabarEstudioTitulo;

  /// No description provided for @grabarEstudioEfectivo.
  ///
  /// In es, this message translates to:
  /// **'Tocando: {tiempo}'**
  String grabarEstudioEfectivo(Object tiempo);

  /// No description provided for @grabarEstudioTotal.
  ///
  /// In es, this message translates to:
  /// **'Tiempo total: {tiempo}'**
  String grabarEstudioTotal(Object tiempo);

  /// No description provided for @grabarEstudioPulsaEmpezar.
  ///
  /// In es, this message translates to:
  /// **'Pulsa el micrófono para empezar a grabar tu estudio.'**
  String get grabarEstudioPulsaEmpezar;

  /// No description provided for @grabarEstudioGrabando.
  ///
  /// In es, this message translates to:
  /// **'Grabando… Cuando termines, pulsa el botón rojo para guardar.'**
  String get grabarEstudioGrabando;

  /// No description provided for @grabarEstudioExplicacion.
  ///
  /// In es, this message translates to:
  /// **'«Tocando» solo cuenta mientras suena tu instrumento (las pausas cortas también cuentan). No se guarda nada de audio.'**
  String get grabarEstudioExplicacion;

  /// No description provided for @grabarEstudioGuardada.
  ///
  /// In es, this message translates to:
  /// **'¡Sesión guardada! Has tocado {minutos} min.'**
  String grabarEstudioGuardada(Object minutos);

  /// No description provided for @grabarEstudioErrorMicro.
  ///
  /// In es, this message translates to:
  /// **'No se puede usar el micrófono. Dale permiso en los ajustes del móvil y vuelve a intentarlo.'**
  String get grabarEstudioErrorMicro;

  /// No description provided for @grabarEstudioErrorGuardar.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar la sesión. Comprueba la conexión a internet.'**
  String get grabarEstudioErrorGuardar;

  /// No description provided for @grabarEstudioSalirTitulo.
  ///
  /// In es, this message translates to:
  /// **'Estás grabando'**
  String get grabarEstudioSalirTitulo;

  /// No description provided for @grabarEstudioSalirTexto.
  ///
  /// In es, this message translates to:
  /// **'Si sales ahora, terminamos la grabación y guardamos lo que llevas.'**
  String get grabarEstudioSalirTexto;

  /// No description provided for @grabarEstudioSeguir.
  ///
  /// In es, this message translates to:
  /// **'Seguir grabando'**
  String get grabarEstudioSeguir;

  /// No description provided for @grabarEstudioGuardarYSalir.
  ///
  /// In es, this message translates to:
  /// **'Guardar y salir'**
  String get grabarEstudioGuardarYSalir;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ca', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ca':
      return AppLocalizationsCa();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
