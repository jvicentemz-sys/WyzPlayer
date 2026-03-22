; =====================================================================
; FADE SYSTEM (FADE OUT / FADE IN)
; Controlado externamente por el juego
; =====================================================================

FADE            EQU $E330        ; BIT 0 = FADE OUT ON/OFF
                                 ; BIT 1 = FADE IN  ON/OFF
FADE_METER      EQU $E331        ; Nivel actual de fade (0..$10)
DECAY           EQU $E332        ; Cadencia (velocidad del fade)
DECAY_TEMP      EQU $E333        ; Temporizador interno

; =====================================================================
; START_FADE_OUT
; IN: A = cadencia (velocidad del fade)
; =====================================================================
START_FADE_OUT:
        LD   [DECAY],A           ; Guarda cadencia
        LD   [DECAY_TEMP],A      ; Inicializa temporizador
        XOR  A
        LD   [FADE_METER],A      ; Fade empieza en 0%
        LD   HL,FADE
        SET  0,[HL]              ; Activa FADE OUT
        RET

; =====================================================================
; FADE_OUT — Ejecutar un paso de fade-out
; Llamar en cada interrupción
; =====================================================================
FADE_OUT:
        LD   HL,DECAY_TEMP
        DEC  [HL]                ; Cuenta atrás de cadencia
        JR   NZ,FADEOJP0         ; Si no llega a 0, no toca volumen aún

        LD   A,[DECAY]
        LD   [HL],A              ; Reinicia temporizador

        LD   A,[FADE_METER]
        CP   $10                 ; ¿Fade completo?
        JP   Z,PLAYER_OFF        ; Sí ? apagar música

        INC  A
        LD   [FADE_METER],A      ; Aumenta nivel de fade

FADEOJP0:
        LD   A,[FADE_METER]      ; C = nivel de fade
        LD   C,A
        LD   HL,PSG_REG_SEC+8    ; Volúmenes PSG A/B/C
        LD   B,3                 ; 3 canales

FADEOBC0:
        LD   A,[HL]              ; A = volumen actual
        SUB  C                   ; Resta fade
        JR   NC,@@NO_RESET_VOL   ; Si no hay underflow, OK
        XOR  A                   ; Si <0 ? volumen = 0

@@NO_RESET_VOL:
        LD   [HL],A              ; Escribe volumen reducido
        INC  HL                  ; Siguiente canal
        DJNZ FADEOBC0            ; Repetir 3 veces
        RET
