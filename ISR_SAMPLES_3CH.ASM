; ================================================================
;  REPRODUCTOR DE SAMPLES PSG (3 CANALES)
;  Formato de frame (6 bytes por frame):
;    	HH = [volumen (4 bits)] [reg1 (4 bits)]
;	LL = reg0 (8 bits)Byte 0 : TONE_A_L              ; R0 low

;  Terminador:
;    Byte 0 = $80                   ; FRAME_TERMINATOR, fin de sample
; ================================================================

FRAME_TERMINATOR    EQU $80          ; Byte de fin de sample
PNT_FRAME           EQU $C000        ; DW puntero al frame actual del sample

; ------------------------------------------------
; SET_SAMPLE_P — Inicia sample con A = ID + 9
; ------------------------------------------------
SET_SAMPLE_P:       SUB 9            ; Ajusta ID (A) para tabla de samples
                    ; cae a SET_SAMPLE

; ------------------------------------------------
; SET_SAMPLE — Inicia sample con ID en A
; ------------------------------------------------
SET_SAMPLE:         PUSH AF          ; Guarda ID de sample

                    LD   HL, TABLA_SAMPLES ; HL = tabla de punteros
                    CALL EXT_WORD    ; HL = puntero al SAMPLE_A
                    LD   [PNT_FRAME], HL   ; Guarda puntero al inicio del sample

                    POP  AF          ; Restaura A (por si se usa después)

                    LD   HL, INTERR  ; Flag de interrupciones / estado
                    SET  5, [HL]     ; Activa reproducción de sample
                    RET

; ================================================================
;  REPLAYERUPDATEPSG — Reproduce un frame del sample
;  Llamar en cada interrupción (50/60 Hz)
; ================================================================
REPLAYERUPDATEPSG:  LD   HL, INTERR  ; HL ? flags
                    BIT  5, [HL]     ; ¿Sample activo?
                    RET  Z           ; No ? salir

                    LD   HL, [PNT_FRAME] ; HL ? frame actual
                    LD   A, [HL]     ; Lee primer byte del frame
                    CP   FRAME_TERMINATOR ; ¿Fin de sample?
                    JR   Z, FIN_SAMPLE   ; Sí ? apagar y salir

                    ; -------------------------------
                    ; 1) Copiar tonos (6 bytes ? R0..R5)
                    ; -------------------------------
                    LD   DE, PSG_REG_SEC+0 ; Destino: registros de tono
                    LD   BC, 3*2      ; 3 canales × 2 bytes
                    LDIR              ; Copia 6 bytes (tono A/B/C)

                    ; -------------------------------
                    ; 2) Extraer volúmenes (nibble alto de cada par)
                    ;    y escribir en R8..R10
                    ; -------------------------------
                    LD   DE, PSG_REG_SEC+8 ; Volúmenes A/B/C
                    LD   B, 3         ; 3 canales

                    LD   HL, [PNT_FRAME] ; HL ? inicio del frame
                    INC  HL           ; HL ? Byte 1 (TONE_A_H | VOL_A)

VOL_LOOP:           LD   A, [HL]      ; A = TONE_X_H | VOL_X
                    RLCA             ; Mueve nibble alto al bajo
                    RLCA
                    RLCA
                    RLCA
                    AND  00001111B   ; A = volumen 0–15
                    CALL VolConv     ; Ajusta curva de volumen
                    LD   [DE], A     ; Escribe volumen en PSG

                    INC  HL          ; HL ? siguiente byte (TONE_Y_L)
                    INC  HL          ; HL ? siguiente (TONE_Y_H | VOL_Y)
                    INC  DE          ; Siguiente registro de volumen
                    DJNZ VOL_LOOP    ; Repite para 3 canales

                    DEC  HL          ; HL quedó 1 byte por delante ? corrige
                    LD   [PNT_FRAME], HL ; Guarda puntero al siguiente frame (HL0+6)

                    RET

; ================================================================
;  FIN_SAMPLE — Apaga volúmenes y desactiva flag
; ================================================================
FIN_SAMPLE:         LD   HL, PSG_REG_SEC+8 ; Volúmenes A/B/C
                    XOR  A            ; A = 0
                    LD   [HL], A      ; Vol A = 0
                    INC  HL
                    LD   [HL], A      ; Vol B = 0
                    INC  HL
                    LD   [HL], A      ; Vol C = 0

                    LD   HL, INTERR   ; Flags
                    RES  5, [HL]      ; Desactiva reproducción de sample
                    RET

; ================================================================
;  LOGVOL — Extrae volumen del nibble alto (rutina auxiliar)
; ================================================================
LOGVOL:             LD   A, [HL]      ; A = [HL]
                    RLCA             ; Nibble alto ? bajo
                    RLCA
                    RLCA
                    RLCA
                    AND  15          ; A = 0–15
                    LD   [DE], A     ; Guarda volumen
                    INC  DE
                    INC  HL
                    RET

; ================================================================
;  VolConv — Convierte volumen lineal ? curva logarítmica PSG
; ================================================================
VolConv:            EXX              ; Usa banco alterno
                    AND  15          ; A = 0–15
                    LD   E, A
                    LD   D, 0
                    LD   HL, VolumTab ; Tabla de conversión
                    ADD  HL, DE
                    LD   A, [HL]     ; A = volumen ajustado
                    AND  00001111B   ; A = 0–15 (por seguridad)
                    EXX
                    RET

VolumTab:           DB 0,1,1,1,2,2,2,3,3,4,5,6,7,8,9,10,11,12,13,14,15
                    ;  PSG 1–15 ? curva más suave (logarítmica aproximada)

; ================================================================
;  TABLA_SAMPLES — Punteros a cada sample PSG
; ================================================================
; Cada SAMPLE_X:
;   .INCLUDE "nombre.wav_psg_cmpct.asm"
;   DB FRAME_TERMINATOR ($80)
; ================================================================
TABLA_SAMPLES:      DW SAMPLE_0, SAMPLE_1, SAMPLE_2, SAMPLE_3
                    DW SAMPLE_4, SAMPLE_5, SAMPLE_6, SAMPLE_7
                    DW SAMPLE_8, SAMPLE_9, SAMPLE_A, SAMPLE_B
                    DW SAMPLE_C, SAMPLE_D, SAMPLE_E, SAMPLE_F

SAMPLE_0:           .INCLUDE "TULUM\TCOD_KISHA.wav_psg_cmpct.asm"          ; KISHA
                    DB FRAME_TERMINATOR
SAMPLE_1:           .INCLUDE "TULUM\TCOD_MARCADOR.wav_psg_cmpct.asm"       ; MARCADOR
                    DB FRAME_TERMINATOR
SAMPLE_2:           .INCLUDE "TULUM\TCOD_TEST3.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_3:           .INCLUDE "TULUM\TCOD_TEST4.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_4:           .INCLUDE "TULUM\TCOD_COGER.wav_psg_cmpct.asm"          ; COGER
                    DB FRAME_TERMINATOR
SAMPLE_5:           .INCLUDE "TULUM\TCOD_TECLA.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_6:           .INCLUDE "TULUM\TCOD_TEST7.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_7:           .INCLUDE "TULUM\TCOD_PUERTA.wav_psg_cmpct.asm"         ; PUERTA
                    DB FRAME_TERMINATOR

SAMPLE_8:           .INCLUDE "TULUM\TCOD_TEST9.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_9:           .INCLUDE "TULUM\TCOD_TESTA.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_A:           .INCLUDE "TULUM\TCOD_ACCION.wav_psg_cmpct.asm"         ; ACCION
                    DB FRAME_TERMINATOR
SAMPLE_B:           .INCLUDE "TULUM\TCOD_EVENTO.wav_psg_cmpct.asm"         ; EVENTO
                    DB FRAME_TERMINATOR
SAMPLE_C:           .INCLUDE "TULUM\TCOD_CAMBIO_PERSONAJE.wav_psg_cmpct.asm" ; CAMBIO PERSONAJE
                    DB FRAME_TERMINATOR
SAMPLE_D:           .INCLUDE "TULUM\TCOD_INSECTOS.wav_psg_cmpct.asm"
                    DB FRAME_TERMINATOR
SAMPLE_E:           .INCLUDE "BOMBAJACK\REPONER_LUZ_2.asm"
                    DB FRAME_TERMINATOR
SAMPLE_F:           .INCLUDE "TULUM\TCOD_TECLA_2.wav_psg_cmpct.asm"        ; PULSA TECLA
                    DB FRAME_TERMINATOR
