
;===========================================================
;  WYZPLAYER – LANZADOR PARA MSX
;===========================================================
;
;  *** GUÍA PARA EL USUARIO MSX ***
;
;  Este archivo contiene todo lo necesario para reproducir
;  música creada con WYZTracker en un MSX real o emulador.
;
;  SIGUE ESTOS PASOS:
;
;  1) Abre WYZTracker y crea tu música.
;     - Exporta el archivo ASM (instrumentos y tablas)
;     - Exporta el archivo MUS (datos de la canción)
;
;  2) Copia ambos archivos en la carpeta del proyecto:
;        EJEMPLO.MUS
;        EJEMPLO.MUS.asm
;
;  3) Sustituye los nombres al final del archivo:
;        .INCLUDE "EJEMPLO.MUS.asm"
;        SONG_0: .INCBIN "EJEMPLO.MUS"
;
;  4) Si tienes varias canciones:
;        SONG_1: .INCBIN "OTRA.MUS"
;        TABLA_SONG: DW SONG_0, SONG_1
;
;  5) Para elegir qué canción suena:
;        XOR A        ; 0 = SONG_0, 1 = SONG_1...
;        CALL CARGA_CANCION
;
;  6) Ensambla con asMSX:
;        asmsx /rom /msx1 TEST3.asm
;
;  7) Carga la ROM en tu MSX o emulador.
;
;  NOTAS IMPORTANTES:
;  - El player funciona por interrupciones (IM1).
;  - No modifiques el código del player.
;  - Solo debes tocar: buffers, includes y selección de canción.
;  - El programa queda en un bucle infinito mientras suena.
;
;===========================================================
;  FIN DE LA GUÍA
;===========================================================


                .filename "TEST3"
                .page 1
                .ROM

;-----------------------------------------------------------
; VARIABLES DEL SISTEMA MSX
;-----------------------------------------------------------

CLIKSW      EQU $F3DB          ; Click del teclado (no usado)
HOOK        EQU $FD9A          ; Hook de interrupción H.TIMI

DLAY60H     EQU $E001          ; Contador 60 Hz (si se usa)
DLAYFX      EQU $E002          ; Recarga del contador

                .INCLUDE "ASM/SYSVAR.ASM"

;-----------------------------------------------------------
; INICIO DEL PROGRAMA
;-----------------------------------------------------------

SPOINT:

;-----------------------------------------------------------
; AJUSTES INICIALES
;-----------------------------------------------------------

AJUSTES:
                DI                      ; Desactiva interrupciones
                CALL    PLAYER_OFF      ; Asegura que el player está parado

;-----------------------------------------------------------
; RESERVA DE BUFFERS DE SONIDO
; Cada canal necesita su propio buffer en RAM.
; Si quieres moverlos, cambia estas direcciones.
;-----------------------------------------------------------

                LD      HL,$D000
                LD      [CANAL_A],HL    ; Buffer canal A

                LD      HL,$D020
                LD      [CANAL_B],HL    ; Buffer canal B

                LD      HL,$D040
                LD      [CANAL_C],HL    ; Buffer canal C

                LD      HL,$D060
                LD      [CANAL_P],HL    ; Buffer percusión

;-----------------------------------------------------------
; CARGA DE LA CANCIÓN
; Cambia A por el número de canción que quieras reproducir.
;-----------------------------------------------------------

                XOR     A               ; Canción 0
                CALL    CARGA_CANCION

;-----------------------------------------------------------
; INSTALACIÓN DE LA INTERRUPCIÓN DEL PLAYER
; No modificar: esto conecta el player al sistema MSX.
;-----------------------------------------------------------

                LD      HL,INICIO       ; Rutina del player
                LD      [HOOK+1],HL     ; Dirección
                LD      A,$C3           ; Opcode JP
                LD      [HOOK],A        ; Activa el salto
                EI                      ; Activa interrupciones

;-----------------------------------------------------------
; BUCLE PRINCIPAL
; El programa queda aquí mientras la música suena.
;-----------------------------------------------------------

LOOP:           JP      LOOP



;-----------------------------------------------------------
; DATOS DE LA MÚSICA
; *** SUSTITUYE ESTOS NOMBRES POR LOS TUYOS ***
;-----------------------------------------------------------

                .INCLUDE "persona_rivers_in_desert.MUS.asm"

SONG_0:         .INCBIN "persona_rivers_in_desert.MUS"

TABLA_SONG:     DW SONG_0

;-----------------------------------------------------------
; WYZPLAYER
; No modificar.
;-----------------------------------------------------------

                .INCLUDE "Wyzplayer_release/WYZProplay47eMSX.asm"
