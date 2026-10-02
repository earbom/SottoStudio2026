// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Catalan Valencian (`ca`).
class AppLocalizationsCa extends AppLocalizations {
  AppLocalizationsCa([String locale = 'ca']) : super(locale);

  @override
  String get comunCancelar => 'Cancel·la';

  @override
  String get comunGuardar => 'Desa';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Contrasenya';

  @override
  String get loginIniciarSesion => 'Inicia sessió';

  @override
  String get loginOlvidasteContrasena => 'Has oblidat la contrasenya?';

  @override
  String get loginCredencialesIncorrectas => 'Credencials incorrectes.';

  @override
  String get loginRecuperarContrasenaTitulo => 'Recuperar contrasenya';

  @override
  String get loginEnviarEnlace => 'Envia l\'enllaç';

  @override
  String get loginEmailEnviado =>
      'Si l\'email existeix, t\'hem enviat un enllaç per restablir la contrasenya.';

  @override
  String get loginEmailError =>
      'No s\'ha pogut enviar l\'email. Comprova l\'adreça.';

  @override
  String get menuInicio => 'Inici';

  @override
  String get menuConfiguracionCentro => 'Configuració del centre';

  @override
  String get menuAyuda => 'Ajuda';

  @override
  String get inicioBienvenidaTitulo => 'Primera vegada a Sotto Studio?';

  @override
  String get inicioBienvenidaTexto =>
      'A l\'Ajuda tens, pas a pas, com fer cada tasca. També la trobaràs sempre al menú (☰).';

  @override
  String get inicioBienvenidaVerAyuda => 'Veure l\'ajuda';

  @override
  String get inicioBienvenidaCerrar => 'Entesos';

  @override
  String get menuGestionCentro => 'Gestió del centre';

  @override
  String get menuCursosAsignaturas => 'Assignatures';

  @override
  String get menuGestionarCursos => 'Gestionar cursos';

  @override
  String get menuAlumnos => 'Alumnes';

  @override
  String get menuProfesorado => 'Professorat';

  @override
  String get menuNotasPendientes => 'Notes pendents';

  @override
  String get menuAsistenciaSinMarcar => 'Assistència sense marcar';

  @override
  String get menuInformeHoras => 'Informe d\'hores';

  @override
  String get menuInformeHorasTitulo => 'Informe d\'hores d\'estudi';

  @override
  String get menuRegistroHorario => 'Registre horari';

  @override
  String get menuCursoEscolar => 'Curs escolar';

  @override
  String get menuImportarDatos => 'Importar dades des d\'Excel';

  @override
  String get menuPlusesOrquesta => 'Plusos d\'orquestra';

  @override
  String get menuHorarioGeneral => 'Horari general';

  @override
  String get menuDocencia => 'Docència';

  @override
  String get menuMisAsignaturas => 'Les meves assignatures';

  @override
  String get menuMiEstudio => 'El meu estudi';

  @override
  String get menuMedallasRoscos => 'Medalles i roscos';

  @override
  String get menuMiHorario => 'El meu horari';

  @override
  String get menuMiJornadaLaboral => 'La meva jornada laboral';

  @override
  String get menuFicharEntradaSalida => 'Fitxar entrada/sortida';

  @override
  String get menuHerramientas => 'Eines';

  @override
  String get menuAfinador => 'Afinador';

  @override
  String get menuMetronomo => 'Metrònom';

  @override
  String get menuCuadroHonor => 'Quadre d\'honor';

  @override
  String get menuReportarProblema => 'Informa d\'un problema o suggeriment';

  @override
  String get menuModoDesarrollador => 'Mode desenvolupador';

  @override
  String get menuModoVista => 'Mode de vista';

  @override
  String get menuIncidencias => 'Incidències';

  @override
  String get menuCambiarContrasena => 'Canviar contrasenya';

  @override
  String get menuAjustes => 'Ajustos';

  @override
  String get menuModoOscuro => 'Mode fosc';

  @override
  String get menuCerrarSesion => 'Tancar sessió';

  @override
  String get menuCerrarSesionConfirmacion => 'Segur que vols tancar la sessió?';

  @override
  String inicioSaludo(Object nombre) {
    return 'Hola, $nombre';
  }

  @override
  String get inicioElegirSeccion =>
      'Tria una secció des del menú (☰) per començar.';

  @override
  String inicioNotasNuevas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tens $count notes noves des de la teva darrera visita.',
      one: 'Tens 1 nota nova des de la teva darrera visita.',
    );
    return '$_temp0';
  }

  @override
  String inicioDiasSinEstudiar(int dias) {
    return 'Fa $dias dies que no registres estudi.';
  }

  @override
  String get ajustesTitulo => 'Ajustos';

  @override
  String get ajustesTamanoLetra => 'Mida de la lletra';

  @override
  String get ajustesTextoEjemplo =>
      'Aquest és un text d\'exemple amb la mida actual.';

  @override
  String get ajustesTamanoIconos => 'Mida de les icones d\'assignatura';

  @override
  String get ajustesTamanoIconosDescripcion =>
      'Afecta la quadrícula d\'icones de \"Assignatures\" i \"Les meves assignatures\".';

  @override
  String get ajustesConfirmarCierreSesion => 'Confirmar abans de tancar sessió';

  @override
  String get ajustesConfirmarCierreSesionDescripcion =>
      'Evita tancaments accidentals en tocar el menú.';

  @override
  String get ajustesExportacionTitulo => 'Exportació automàtica de fitxatges';

  @override
  String get ajustesExportacionDescripcion =>
      'En obrir l\'app després d\'acabar un mes, es genera només un Excel amb els fitxatges d\'aquest mes en aquesta carpeta. És una còpia de conveniència: el registre real sempre viu a la base de dades i mai es pot esborrar.';

  @override
  String get ajustesSinConfigurar => 'Sense configurar';

  @override
  String get ajustesElegirCarpeta => 'Tria carpeta';

  @override
  String get ajustesExportarAhora => 'Exportar el mes anterior ara';

  @override
  String get ajustesExportacionExito => 'Exportació del mes anterior generada.';

  @override
  String ajustesExportacionError(Object error) {
    return 'No s\'ha pogut exportar: $error';
  }

  @override
  String get ajustesAsistenteTitulo => 'Assistent (Claude)';

  @override
  String get ajustesAsistenteDescripcion =>
      'URL del servidor propi del centre que connecta el botó de l\'assistent amb l\'API de Claude. La clau de l\'API viu només en aquest servidor, mai en aquesta app.';

  @override
  String get ajustesAsistenteUrlLabel => 'URL del servidor';

  @override
  String get ajustesAsistenteGuardar => 'Desa';

  @override
  String get ajustesRestablecer => 'Restableix els valors per defecte';

  @override
  String get ajustesIdioma => 'Idioma';

  @override
  String get ajustesIdiomaCastellano => 'Castellà';

  @override
  String get ajustesIdiomaCatalan => 'Català';

  @override
  String get fichajesNoHasFichado => 'Encara no has fitxat avui';

  @override
  String get fichajesEntrada => 'Entrada';

  @override
  String get fichajesSalida => 'Sortida';

  @override
  String fichajesConfirmarHora(Object hora) {
    return 'Es registrarà a les $hora. Un cop fitxat no es pot canviar (només direcció ho pot corregir).';
  }

  @override
  String get fichajesFicharEntrada => 'Fitxar entrada';

  @override
  String get fichajesFicharSalida => 'Fitxar sortida';

  @override
  String get fichajesJornadaCompletada => 'Jornada d\'avui completada.';

  @override
  String get fichajesMiHorarioLaboral => 'El meu horari laboral';

  @override
  String get fichajesSinConfigurar => 'Sense configurar';

  @override
  String fichajesTurnos(int count, int min) {
    return '$count torn(s) · avís $min min abans';
  }

  @override
  String get fichajesOlvidasteFichar => 'Vas oblidar fitxar un altre dia?';

  @override
  String get fichajesAutoinformar =>
      'Autoinformar d\'un dia passat sense fitxar';

  @override
  String get fichajesEnviadoPendiente =>
      'Enviat. Queda pendent que direcció ho validi.';

  @override
  String get fichajesMisUltimosFichajes => 'Els meus darrers fitxatges';

  @override
  String get fichajesSinFichajes => 'Encara no hi ha fitxatges registrats.';

  @override
  String get fichajesSinTurnos => 'Encara no hi ha torns configurats.';

  @override
  String get fichajesPendienteValidar => 'Pendent de validar per direcció';

  @override
  String get fichajesDiaSemana => 'Dia de la setmana';

  @override
  String get fichajesAnadirTurno => 'Afegeix torn';

  @override
  String get fichajesAvisarAntes => 'Avisar abans de fitxar (min):';

  @override
  String get fichajesEligeOlvidaste => 'Tria el dia que vas oblidar fitxar';

  @override
  String get fichajesHoraEntrada => 'Hora d\'entrada';

  @override
  String get fichajesHoraSalida => 'Hora de sortida';

  @override
  String fichajesErrorCarga(Object error) {
    return 'No s\'ha pogut carregar el fitxatge: $error';
  }

  @override
  String get fichajesCorregido => '(corregit)';

  @override
  String get diaLunes => 'Dilluns';

  @override
  String get diaMartes => 'Dimarts';

  @override
  String get diaMiercoles => 'Dimecres';

  @override
  String get diaJueves => 'Dijous';

  @override
  String get diaViernes => 'Divendres';

  @override
  String get diaSabado => 'Dissabte';

  @override
  String get diaDomingo => 'Diumenge';

  @override
  String get grabarEstudioTitulo => 'Registrar estudi';

  @override
  String grabarEstudioEfectivo(Object tiempo) {
    return 'Tocant: $tiempo';
  }

  @override
  String grabarEstudioTotal(Object tiempo) {
    return 'Temps total: $tiempo';
  }

  @override
  String get grabarEstudioPulsaEmpezar =>
      'Prem el micròfon per començar a gravar el teu estudi.';

  @override
  String get grabarEstudioGrabando =>
      'Gravant… Quan acabis, prem el botó vermell per desar.';

  @override
  String get grabarEstudioExplicacion =>
      '«Tocant» només compta mentre sona el teu instrument (les pauses curtes també compten). No es desa cap àudio.';

  @override
  String grabarEstudioGuardada(Object minutos) {
    return 'Sessió desada! Has tocat $minutos min.';
  }

  @override
  String get grabarEstudioErrorMicro =>
      'No es pot fer servir el micròfon. Dona-li permís a la configuració del mòbil i torna-ho a provar.';

  @override
  String get grabarEstudioErrorGuardar =>
      'No s\'ha pogut desar la sessió. Comprova la connexió a internet.';

  @override
  String get grabarEstudioSalirTitulo => 'Estàs gravant';

  @override
  String get grabarEstudioSalirTexto =>
      'Si surts ara, aturem la gravació i desem el que portes.';

  @override
  String get grabarEstudioSeguir => 'Continuar gravant';

  @override
  String get grabarEstudioGuardarYSalir => 'Desar i sortir';
}
