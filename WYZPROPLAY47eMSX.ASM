; ==============================================================================
; MSX PSG proPLAYER V 47e - WYZ 15.03.2026
; VERSION ESTRUCTURADA, TABULADA Y DOCUMENTADA (PRE-OPTIMIZACION)
; ==============================================================================
; ENSAMBLAR CON AsMSX 
;
; CARACTERISTICAS:
; 5 OCTAVAS:            O[2-6] = 60 NOTAS
; 4 LONGITUDES DE NOTA: L[0-3] + PUNTILLO 
;
; ==============================================================================
; FORMATO .MUS 
; ==============================================================================
; CABECERA (12 Bytes):
; Byte 0: [Bit 7: Tempo Híbrido | Bits 6-0: Tempo Base (Frames por tick)]
; Byte 1:[-|-|-|-| Bits 2-1: Canal FX (0=A, 1=B, 2=C) | Bit 0: Loop (1=ON)]
; Byte 2-3: Reservados
; Byte 4 a 11: Offsets (Words) para bucles de Canales A, B, C y P.
;
; DATOS COMPRIMIDOS RLE (A partir del Byte 12):
; 
; Los canales están concatenados unos detrás de otros en este orden exacto:
; Canal A -> Canal B -> Canal C -> Canal P.
;
; Cada evento es 1 Byte con formato:[ L1 L0 | N5 N4 N3 N2 N1 N0 ]
; - Bits L1,L0 (Longitud): 00=x1, 01=x2, 10=x4, 11=x8 (Multiplicador de frames)
; - Bits N5..N0 (Nota):
;   * 00 (0)  = FIN DE CANAL
;   * 01 (1)  = SILENCIO
;   * 02..61  = NOTA MUSICAL
;   * 62 (3E) = PUNTILLO (Dotted: +50% de duración sin re-disparar)
;   * 63 (3F) = PREFIJO DE COMANDOS ESPECIALES
;
; COMANDOS ESPECIALES (Cuando N5..N0 = 63):
; - Si L1,L0 = 00 ($3F) -> CAMBIO DE INSTRUMENTO. Lee 2 bytes extra (ID|Tempo,Vol).
; - Si L1,L0 = 01 ($7F) -> EFECTO DE SONIDO (SFX). Lee 1 byte extra (ID).
; - Si L1,L0 = 10 ($BF) -> ENVOLVENTE HARDWARE. Lee 1 byte extra (Forma).
; ==============================================================================
;; CANAL P (Canal de Percusión / Agrupador de SFX / Lanzador de Eventos)
; ------------------------------------------------------------------------------
; El Canal P no es un canal de audio del PSG. Su función es agrupar los
; efectos sonoros (SFX) generados por el tracker, especialmente los de
; percusión. El player puede lanzar SFX desde cualquier canal mediante
; el comando especial $7F correspondiente, el tracker organiza estos
; eventos en el Canal P para mantener la estructura del módulo.
; ==============================================================================

; ============================================================
; Selección de plataforma (solo una) 0/1: SELECCIONADA
; ============================================================

MSX = 1
CPC = 0
ZX  = 0

; ==============================================================================
; MAPA DE MEMORIA Y VARIABLES DE ENTORNO (WORKSPACE RAM)
; ==============================================================================

HYBRID          EQU     $E3FF           ; TEMPO HIBRIDO (Permite tempos decimales)
                                        ; BIT 7 = HYBRID ON/OFF
                                        ; BIT 6 = ALTERNADOR (Salto de frame)

INTERR          EQU     $E400           ; BYTE DE ESTADO/INTERRUPTORES (1=ON 0=OFF)
                                        ; BIT 0 = CARGA CANCION ON/OFF
                                        ; BIT 1 = PLAYER ON/OFF (Música sonando)
                                        ; BIT 2 = EFECTOS ON/OFF (SFX sonando)
                                        ; BIT 3 = SFX ON/OFF (Activa canal de ruidos)
                                        ; BIT 4 = LOOP (Bucle de la canción)

SONG            EQU     INTERR+1        ; DB: N° DE CANCION ACTUAL
TEMPO           EQU     INTERR+2        ; DB: TEMPO (Frames por tick musical)
TTEMPO          EQU     INTERR+3        ; DB: CONTADOR TEMPO (Frames transcurridos)

; --- PUNTEROS DE LECTURA (En tiempo real durante la reproducción) ---
PUNTERO_A       EQU     INTERR+4        ; DW: PUNTERO DEL CANAL A (Nota actual)
PUNTERO_B       EQU     INTERR+6        ; DW: PUNTERO DEL CANAL B (Nota actual)
PUNTERO_C       EQU     INTERR+8        ; DW: PUNTERO DEL CANAL C (Nota actual)

; --- DIRECCIONES BASE DE LA MUSICA DESCOMPRIMIDA ---
CANAL_A         EQU     INTERR+$0A      ; DW: DIRECION DE INICIO DE LA MUSICA A
CANAL_B         EQU     INTERR+$0C      ; DW: DIRECION DE INICIO DE LA MUSICA B
CANAL_C         EQU     INTERR+$0E      ; DW: DIRECION DE INICIO DE LA MUSICA C

; --- PUNTEROS DE PAUTAS (Macros/Instrumentos en ejecución) ---
PUNTERO_P_A     EQU     INTERR+$10      ; DW: PUNTERO PAUTA CANAL A (Paso actual)
PUNTERO_P_B     EQU     INTERR+$12      ; DW: PUNTERO PAUTA CANAL B (Paso actual)
PUNTERO_P_C     EQU     INTERR+$14      ; DW: PUNTERO PAUTA CANAL C (Paso actual)

PUNTERO_P_A0    EQU     INTERR+$16      ; DW: INI PUNTERO PAUTA CANAL A (Reset)
PUNTERO_P_B0    EQU     INTERR+$18      ; DW: INI PUNTERO PAUTA CANAL B (Reset)
PUNTERO_P_C0    EQU     INTERR+$1A      ; DW: INI PUNTERO PAUTA CANAL C (Reset)

; --- PUNTEROS DEL DECODIFICADOR (Para descomprimir al vuelo/inicio) ---
PUNTERO_P_DECA  EQU     INTERR+$1C      ; DW: PUNTERO DE INICIO DEL DECODER CANAL A
PUNTERO_P_DECB  EQU     INTERR+$1E      ; DW: PUNTERO DE INICIO DEL DECODER CANAL B
PUNTERO_P_DECC  EQU     INTERR+$20      ; DW: PUNTERO DE INICIO DEL DECODER CANAL C

PUNTERO_DECA    EQU     INTERR+$22      ; DW: PUNTERO DECODER CANAL A (Posición actual)
PUNTERO_DECB    EQU     INTERR+$24      ; DW: PUNTERO DECODER CANAL B (Posición actual)
PUNTERO_DECC    EQU     INTERR+$26      ; DW: PUNTERO DECODER CANAL C (Posición actual)

; --- REGISTROS DE ESTADO DE LOS CANALES ---
REG_NOTA_A      EQU     INTERR+$28      ; DB: REGISTRO DE LA NOTA EN EL CANAL A
VOL_INST_A      EQU     INTERR+$29      ; DB: VOLUMEN RELATIVO DEL INSTRUMENTO CANAL A
REG_NOTA_B      EQU     INTERR+$2A      ; DB: REGISTRO DE LA NOTA EN EL CANAL B
VOL_INST_B      EQU     INTERR+$2B      ; DB: VOLUMEN RELATIVO DEL INSTRUMENTO CANAL B
REG_NOTA_C      EQU     INTERR+$2C      ; DB: REGISTRO DE LA NOTA EN EL CANAL C
VOL_INST_C      EQU     INTERR+$2D      ; DB: VOLUMEN RELATIVO DEL INSTRUMENTO CANAL C

; --- PUNTEROS DE BUCLE (Para repetir patrones) ---
PUNTERO_L_DECA  EQU     INTERR+$2E      ; DW: PUNTERO INICIO LOOP DEL DECODER CANAL A
PUNTERO_L_DECB  EQU     INTERR+$30      ; DW: PUNTERO INICIO LOOP DEL DECODER CANAL B
PUNTERO_L_DECC  EQU     INTERR+$32      ; DW: PUNTERO INICIO LOOP DEL DECODER CANAL C

; --- CANAL DE EFECTOS DE RITMO (Percusiones que enmascaran canales) ---
PUNTERO_P       EQU     INTERR+$34      ; DW: PUNTERO DEL CANAL EFECTOS (Reproducción)
CANAL_P         EQU     INTERR+$36      ; DW: DIRECION DE INICIO DE LOS EFECTOS
PUNTERO_P_DECP  EQU     INTERR+$38      ; DW: PUNTERO DE INICIO DEL DECODER CANAL P
PUNTERO_DECP    EQU     INTERR+$3A      ; DW: PUNTERO DECODER CANAL P
PUNTERO_L_DECP  EQU     INTERR+$3C      ; DW: PUNTERO DE INICIO DEL LOOP DECODER CANAL P

; --- EFECTOS ESPECIALES / SFX (Disparos, explosiones...) ---
SFX_L           EQU     INTERR+$3E      ; DW: DIR BUFFER SFX REGISTRO BAJO (Pitch)
SFX_H           EQU     INTERR+$40      ; DW: DIR BUFFER SFX REGISTRO ALTO (Pitch)
SFX_V           EQU     INTERR+$42      ; DW: DIR BUFFER SFX REGISTRO VOLUMEN
SFX_MIX         EQU     INTERR+$44      ; DW: DIR BUFFER SFX REGISTRO MIXER (Ruido/Tono)

N_SONIDO        EQU     INTERR+$46      ; DB: NUMERO DE SONIDO (ID del SFX)
PUNTERO_SONIDO  EQU     INTERR+$47      ; DW: PUNTERO DEL SONIDO QUE SE REPRODUCE

; --- BUFFERS DEL PSG AY-3-8910 (14 Registros físicos) ---
PSG_REG         EQU     INTERR+$49      ; DB [14]: BUFFER PRINCIPAL DEL PSG (Cálculo)
PSG_REG_SEC     EQU     INTERR+$59      ; DB [14]: BUFFER SECUNDARIO (Listo para HW)
ENVOLVENTE      EQU     INTERR+$69      ; DB: FORMA DE LA ENVOLVENTE (Registro 13)
                                        ; BIT 0   : FRECUENCIA CANAL ON/OFF
                                        ; BIT 1-2 : RATIO 
                                        ; BIT 3-3 : FORMA	
ENVOLVENTE_BACK EQU     INTERR+$70      ; DB: BACKUP DE LA FORMA (Evita re-triggear R13)

ENV_PER_L_BACK  EQU 	INTERR+$71 	; DB: backup R11 (periodo envolvente bajo) - RESTAURA TRAS UN SFX
ENV_PER_H_BACK  EQU 	INTERR+$72 	; DB: backup R12 (periodo envolvente alto)
MIXER_BACK      EQU 	INTERR+$73 	; DB: backup R7
VOL_BACK        EQU 	INTERR+$74 	; DB: backup volumen canal SFX

; ==============================================================================
; BLOQUE: INICIO - Rutina principal llamada desde la interrupción (ej. 50Hz)
; ==============================================================================
INICIO:         CALL    ROUT            ; 1. Vuelca el buffer calculado al chip PSG HW
                CALL    PLAY            ; 2. Calcula la música para el frame actual
                LD      HL,PSG_REG      ; 3. Origen: Buffer donde PLAY ha trabajado
                LD      DE,PSG_REG_SEC  ; 4. Destino: Buffer secundario 
                LD      BC,14           ; 5. Copia los 14 registros del chip
                LDIR                    ; 6. Ejecuta copia de bloques (Z80)
                CALL    REPRODUCE_SONIDO; 7. Superpone SFX encima de la música (modifica PSG_REG_SEC)
                RET                     ; Retorna al sistema u origen de interrupción
                
; ==============================================================================
; BLOQUE: REPRODUCE_SONIDO - Gestor de Efectos Especiales (SFX) prioritarios
; ==============================================================================
; ==============================================================
; FRAME SIN ENVOLVENTE  (CONTROL bit7 = 0)
; --------------------------------------------------------------
; Byte 0 : PITCH_L              ; Periodo AY bajo
; Byte 1 : [PITCH_H:4 | VOL:4]  ; PITCH_H = periodo alto, VOL = 0–15
; Byte 2 : CONTROL              ; bit7=0, bits0-6 = ruido (R6) o 0
; ==============================================================


; ==============================================================
; FRAME CON ENVOLVENTE  (CONTROL bit7 = 1)
; --------------------------------------------------------------
; Byte 0 : PITCH_L              ; Periodo AY bajo
; Byte 1 : [PITCH_H:4 | VOL:4]  ; VOL se ignora (usa envolvente HW)
; Byte 2 : CONTROL              ; bit7=1, bits0-6 = ruido (R6)
; Byte 3 : ENV_PER_L            ; Periodo envolvente bajo (R11)
; Byte 4 : ENV_PER_H            ; Periodo envolvente alto (R12)
; Byte 5 : ENV_SHAPE            ; Forma (R13) — 1 = mantener forma previa
; ==============================================================
; ==============================================================
; FIN DEL SFX
; --------------------------------------------------------------
; Byte 0 = $FF  ?  termina el efecto
; ==============================================================

REPRODUCE_SONIDO:
                LD      HL,INTERR       ; Apunta al byte de estado principal
                BIT     2,[HL]          ; ¿ESTÁ ACTIVADO EL EFECTO? (Bit 2 = 1)
                RET     Z               ; Si es 0, no hay SFX que reproducir. Sale.
                
                LD      HL,[PUNTERO_SONIDO] ; HL apunta al frame actual del SFX
                LD      A,[HL]          ; Lee el primer byte (Pitch bajo o fin)
                CP      $FF             ; $FF significa "Fin del efecto"
                JR      Z,FIN_SONIDO    ; Si es $FF, salta a la rutina de apagado de SFX
                
                LD      DE,[SFX_L]      ; DE = Puntero al registro de tono bajo asociado
                LD      [DE],A          ; Sobrescribe el tono bajo del canal afectado
                INC     HL              ; Avanza al siguiente byte del SFX
                LD      A,[HL]          ; Lee el byte mixto (Volumen + Pitch Alto)
                
                ; Extrae el pitch alto (nibble alto del byte)
                RRCA                    ; Rota a la derecha 4 veces (baja los 4 bits altos)
                RRCA
                RRCA
                RRCA
                AND     00001111B       ; Máscara para quedarse solo con el valor (0-15)
                LD      DE,[SFX_H]      ; Puntero al registro de tono alto del PSG
                LD      [DE],A          ; Aplica el tono alto al canal asociado
                
                ; Extrae el volumen (nibble bajo del byte)
                LD      A,[HL]          ; Recupera el byte original
                AND     00001111B       ; Máscara: aísla el nibble inferior (volumen 0-15)
                LD      DE,[SFX_V]      ; Puntero al registro de volumen del PSG
                LD      [DE],A          ; Aplica el volumen al canal asociado
                
                INC     HL              ; Avanza al tercer byte del SFX (Control)
                LD      A,[HL]          ; Lee el byte de control
                LD      B,A             ; Lo guarda en B para uso posterior
                BIT     7,A             ; ¿BIT MAS SIGNIFICATIVO? -> ACTIVA ENVOLVENTES HW
                JR      Z,NO_ENVOLVENTES_SONIDO ; Si es 0, es un volumen de software normal
                
                ; Configura envolvente hardware para el SFX
                LD      A,$12           ; $12 = 18 en decimal. En modo envolvente, vol debe ser $10 (16).
                                        ; Nota: aquí escribe $12. MSX PSG usa bit 4 (valor 16) para envolvente.
                LD      [DE],A          ; Escribe volumen envolvente
                INC     HL              ; Siguiente byte: Periodo de envolvente bajo (R11)
                LD      A,[HL]          
                LD	[PSG_REG_SEC+11],A 
                INC     HL              ; Siguiente byte: Periodo de envolvente alto (R12)
                LD      A,[HL]          
                LD      [PSG_REG_SEC+12],A 
                INC     HL              ; Siguiente byte: Forma de la envolvente (R13)
                LD      A,[HL]          
                CP      1               ; Valor especial: 1 significa mantener forma previa
                JR      Z,NO_ENVOLVENTES_SONIDO ; NO ESCRIBE LA ENVOLVENTE SI SU VALOR ES 1
                LD      [PSG_REG_SEC+13],A ; Si es diferente de 1, escribe R13

NO_ENVOLVENTES_SONIDO:
                LD      A,B             ; Recupera byte de control (desde B)
                RES     7,A             ; Elimina el bit de envolvente (limpia bit 7)
                AND     A               ; Comprueba si queda algo (0 = no hay ruido blanco)
                JR      Z,NO_RUIDO      ; Salta si es cero
                
                ; Configura canal de ruido para el SFX
                LD      [PSG_REG_SEC+6],A ; R6 = Frecuencia de Ruido del PSG
                LD      A,[SFX_MIX]     ; Recupera la máscara del Mixer precalculada para este canal
                JR      SI_RUIDO        ; Salta a aplicar el Mixer
                
NO_RUIDO:       XOR     A               ; A=0
                LD      [PSG_REG_SEC+6],A ; Apaga el periodo de ruido
                LD      A,10111000B     ; Mixer por defecto (Solo Tonos ABC encendidos, Ruido OFF)
                
SI_RUIDO:       LD      [PSG_REG_SEC+7],A ; R7 = Mixer (Aplica configuración de Ruido/Tono)
                INC     HL              ; Avanza puntero al siguiente frame del SFX
                LD      [PUNTERO_SONIDO],HL ; Guarda el puntero para la próxima interrupción
                RET                     ; Fin
                
FIN_SONIDO:     LD      HL,INTERR	; Efecto terminado	
                RES     2,[HL]              ; SFX OFF

                
                LD      A,[ENVOLVENTE_BACK]	; ¿La música usaba envolvente?
                AND     A
                JR      Z,NO_ENV_RESTORE    	; 0 = música sin envolvente
                LD      [PSG_REG_SEC+13],A                

                LD      A,[ENV_PER_L_BACK]	; Restaurar periodo de envolvente REG.11/12
                LD      [PSG_REG_SEC+11],A
                LD      A,[ENV_PER_H_BACK]
                LD      [PSG_REG_SEC+12],A
              

NO_ENV_RESTORE: LD      A,[MIXER_BACK]		; Restaurar mixer original
                LD      [PSG_REG_SEC+7],A

                LD      A,[VOL_BACK]		; Restaurar volumen del canal del SFX
                LD      DE,[SFX_V]
                LD      [DE],A

                RET    




; ==============================================================================
; BLOQUE: ROUT - Envia el buffer PSG_REG_SEC al chip físico AY-3-8910 (MSX)
; ==============================================================================
; ==============================================================================
; ROUT — Envía el buffer PSG_REG_SEC al chip AY-3-8910 (según plataforma)
; ==============================================================================

ROUT:
        LD A,[PSG_REG+13]               ; Lee R13 (forma de envolvente)
        AND A                           ; ¿Es 0?
        JR Z,NO_BACKUP_ENV              ; Si es 0, no se guarda
        LD [ENVOLVENTE_BACK],A          ; Guarda envolvente para SFX
NO_BACKUP_ENV:

; ==============================================================================
;   MSX
; ==============================================================================
IF MSX

        XOR A                           ; A=0 ? primer registro
        LD C,$A0                        ; Puerto control PSG MSX
        LD HL,PSG_REG_SEC               ; HL ? buffer secundario

LOUT_MSX:
        OUT [C],A                       ; Selecciona registro
        INC C                           ; C=$A1 (datos)
        OUTI                            ; OUT (C),(HL) y HL++
        DEC C                           ; Vuelve a $A0
        INC A                           ; Siguiente registro
        CP 13                           ; ¿R13?
        JR NZ,LOUT_MSX                  ; Sigue

        OUT [C],A                       ; Selecciona R13
        LD A,[HL]                       ; Valor envolvente
        AND A                           ; ¿0?
        RET Z                           ; No disparar
        INC C                           ; C=$A1
        OUT [C],A                       ; Dispara envolvente

        XOR A                           ; Limpia R13
        LD [PSG_REG_SEC+13],A
        LD [PSG_REG+13],A
        RET
ENDIF

; ==============================================================================
;   CPC
; ==============================================================================
IF CPC

        LD HL,PSG_REG_SEC               ; HL ? buffer
        LD B,13                         ; Registros 0..12
        LD C,$F6                        ; Puerto PSG CPC

LOUT_CPC:
        LD A,B                          ; A = nº registro
        OUT [C],A                       ; Selecciona registro
        LD A,[HL]                       ; Dato
        OUT [C],A                       ; Escribe
        INC HL                          ; Siguiente
        DJNZ LOUT_CPC                   ; Repite

        LD A,13                         ; R13
        OUT [C],A
        LD A,[HL]                       ; Valor envolvente
        AND A
        RET Z
        OUT [C],A                       ; Dispara envolvente

        XOR A                           ; Limpia R13
        LD [PSG_REG_SEC+13],A
        LD [PSG_REG+13],A
        RET
ENDIF
; ==============================================================================
;   ZX Spectrum 128 / +2 / +3
; ==============================================================================
IF ZX

            XOR     A                   ; A=0 ? primer registro AY
ROUT_A0:
            LD      DE,$FFBF            ; D=$FF (puerto select), E=$BF (puerto data)
            LD      BC,$FFFD            ; B=$FF, C=$FD ? puerto select AY
            LD      HL,PSG_REG_SEC      ; HL ? buffer secundario

LOUT:       OUT     [C],A               ; OUT ($FFFD),A ? selecciona registro A
            LD      B,E                 ; B=$BF ? puerto $BFFD (datos)
            OUTI                        ; OUT ($BFFD),(HL) y HL++, B--
            LD      B,D                 ; B=$FF ? vuelve a puerto $FFFD
            INC     A                   ; siguiente registro
            CP      13                  ; ¿hemos llegado a R13?
            JR      NZ,LOUT             ; si no, continúa

            OUT     [C],A               ; selecciona R13
            LD      A,[HL]              ; lee valor de envolvente
            AND     A                   ; ¿es 0?
            RET     Z                   ; si es 0 ? no disparar envolvente
            LD      B,E                 ; B=$BF ? puerto datos
            OUTI                        ; OUT ($BFFD),A ? dispara envolvente

            XOR     A                   ; A=0
            LD      [PSG_REG_SEC+13],A  ; limpia R13 en buffer secundario
            LD      [PSG_REG+13],A      ; limpia R13 en buffer primario
            RET                          ; fin rutina ZX
ENDIF

; ==============================================================================
; BLOQUE: INICIA_SONIDO - Prepara la reproducción de un Efecto de Sonido
; IN: [A] = Número de Sonido
; ==============================================================================
INICIA_SONIDO:
                LD      HL,TABLA_SONIDOS
                CALL    EXT_WORD
                LD      [PUNTERO_SONIDO],HL

                ;--------------------------------------------------
                ; GUARDAR ESTADO DE LA MÚSICA ANTES DEL SFX - 
                ; (PSG_REG_SEC ya contiene la música recién calculada)
                ; NO TOCAR EL REG 13
                ;--------------------------------------------------

                
                LD      A,[PSG_REG_SEC+11]	; Guardar periodo de envolvente
                LD      [ENV_PER_L_BACK],A

                LD      A,[PSG_REG_SEC+12]
                LD      [ENV_PER_H_BACK],A
                
                LD      A,[PSG_REG_SEC+7]	; Guardar mixer
                LD      [MIXER_BACK],A
               
                LD      DE,[SFX_V]		; Guardar volumen del canal del SFX
                LD      A,[DE]
                LD      [VOL_BACK],A
                
                LD      HL,INTERR		; Activar SFX
                SET     2,[HL]

                RET

; ==============================================================================
; BLOQUE: PLAYER_OFF - Apaga el reproductor y silencia el chip
; ==============================================================================
PLAYER_OFF:     XOR     A               ; A = 0
                LD      [INTERR],A      ; Apaga todos los interruptores (Música, SFX = OFF)
                ;LD     [FADE],A        ; Comentado: Solo si hay fade out

CLEAR_PSG_BUFFER:                       ; Rellena con ceros los buffers del PSG
                LD      HL,PSG_REG      ; Desde el inicio del buffer principal
                LD      DE,PSG_REG+1    ; Destino desfasado 1 byte
                LD      BC,14           ; Tamaño de los registros
                LD      [HL],A          ; Ponemos 0 en el primero
                LDIR                    ; El bloque se llena de ceros (Efecto dominó)
                
                LD      A,10111000B     ; Valor por defecto del R7 (Mixer: Ruido y Tonos apagados/encendidos)
                LD      [PSG_REG+7],A   ; SILENCIA los canales (Mute)
                
                LD      HL,PSG_REG      
                LD      DE,PSG_REG_SEC  
                LD      BC,14           
                LDIR                    ; Copia el buffer "limpio" al buffer secundario

                CALL    ROUT            ; Vuelca los ceros al hardware real (apaga el sonido físicamente)
                RET

; ==============================================================================
; BLOQUE: CARGA_CANCION - Prepara e Inicializa una melodía
; IN: [A] = Número de Canción
; ==============================================================================
CARGA_CANCION:  LD      HL,INTERR       
                SET     1,[HL]          ; Enciende Bit 1: REPRODUCE CANCION = ON
                LD      HL,SONG
                LD      [HL],A          ; Guarda el N° de canción actual
                
; ==============================================================================
; BLOQUE: DECODE_SONG - Descomprime el módulo .MUS entero en la RAM plana
; ==============================================================================
DECODE_SONG:    LD      A,[SONG]        ; Recupera el N° de canción a cargar

; LEE CABECERA DE LA CANCION (BYTE 0 = TEMPO)
                LD      HL,TABLA_SONG   ; Apunta a la lista de punteros de canciones
                CALL    EXT_WORD        ; HL = Puntero al inicio de los datos comprimidos
                LD      A,[HL]          ; Lee Byte 0 (Temporizador / Velocidad)
                AND     01111111B       ; Quita el bit alto (Bit 7 = Flag Hybrid)
                LD      [TEMPO],A       ; Guarda la velocidad
                DEC     A
                LD      [TTEMPO],A      ; Contador de frames, inicia casi a tope para arrancar ya
                LD      A,[HL]          ; Vuelve a leer Byte 0
                AND     10000000B       ; Extrae solo el bit 7
                LD      [HYBRID],A      ; Guarda flag de "Tempo Híbrido" (Intercalado de frames)
                
; HEADER BYTE 1 ->[- | - | - | - | 3-1: FX CHN | 0: LOOP]
                INC     HL              
                LD      A,[HL]          ; Lee Byte 1
                BIT     0,A             ; LOOP 1=ON / 0=OFF
                JR      Z,NPTJP0        ; Si es 0, no hay bucle infinito
                PUSH    HL
                LD      HL,INTERR
                SET     4,[HL]          ; Enciende Bit 4: Activa LOOP
                POP     HL
                
; SELECCION DEL CANAL DE EFECTOS DE RITMO (A, B o C)
NPTJP0:         AND     00000110B       ; Filtra los bits 1 y 2 (Indican qué canal es para percusión)
                RRA                     ; Los mueve abajo para tener índice 0, 1 o 2
                
                PUSH    HL
                LD      HL,TABLA_DATOS_CANAL_SFX ; Tabla con dir de punteros según canal de destino
                CALL    EXT_WORD        ; Extrae puntero (Apunta a SELECT_CANAL_A, B o C)
                PUSH    HL
                POP     IX              ; IX apunta a la configuración de percusión para ese canal
                
                ; Configura los punteros indirectos para escribir el SFX sobre el canal correcto
                LD      E,[IX+0]
                LD      D,[IX+1]
                LD	[SFX_L],DE      ; Puntero al R. Bajo de ese canal

                LD      E,[IX+2]
                LD      D,[IX+3]
                LD      [SFX_H],DE      ; Puntero al R. Alto de ese canal

                LD      E,[IX+4]
                LD      D,[IX+5]
                LD      [SFX_V],DE      ; Puntero al R. Volumen de ese canal

                LD      A,[IX+6]
                LD	[SFX_MIX],A     ; Máscara R7 (Ruido) para ese canal
                POP     HL
                
                INC     HL              ; (2 BYTES RESERVADOS en el formato WYZ)
                INC     HL
                INC     HL

; BUSCA Y GUARDA INICIO DE LOS CANALES EN EL MODULO (Descomprime offsets)
                PUSH    HL              ; IX = HL (Inicio offsets loop por canal)
                POP     IX
                
                LD      DE,$0008        ; Salta la cabecera (8 bytes) para llegar al Canal A
                ADD     HL,DE
                
                LD      [PUNTERO_P_DECA],HL ; GUARDA PUNTERO INICIO CANAL A
                LD      E,[IX+0]        ; Extrae Offset de Loop para A (relativo)
                LD      D,[IX+1]
                ADD     HL,DE
                LD      [PUNTERO_L_DECA],HL ; GUARDA PUNTERO INICIO LOOP CANAL A

                CALL    BGICMODBC1      ; Avanza hasta encontrar el inicio del Canal B
                LD      [PUNTERO_P_DECB],HL 
                LD      E,[IX+2]
                LD      D,[IX+3]
                ADD     HL,DE
                LD	[PUNTERO_L_DECB],HL

                CALL    BGICMODBC1      ; Avanza hasta encontrar el inicio del Canal C
                LD      [PUNTERO_P_DECC],HL
                LD      E,[IX+4]
                LD      D,[IX+5]
                ADD     HL,DE
                LD      [PUNTERO_L_DECC],HL
                
                CALL    BGICMODBC1      ; Avanza hasta encontrar el inicio del Canal Efectos/Rítmo (P)
                LD	[PUNTERO_P_DECP],HL
                LD      E,[IX+6]
                LD      D,[IX+7]
                ADD     HL,DE
                LD	[PUNTERO_L_DECP],HL
                
; INICIA LA DESCOMPRESIÓN REAL HACIA LOS BUFFERS
INIT_DECODER:   LD      DE,[CANAL_A]    ; Destino descompresión A
                LD      [PUNTERO_A],DE  ; Puntero inicial reproducción A
                LD      HL,[PUNTERO_P_DECA] ; Origen de compresión A
                CALL    DECODE_CANAL    ; DECODIFICA CANAL A
                LD      [PUNTERO_DECA],HL ; Guarda la posición final origen
                
                LD      DE,[CANAL_B]    
                LD	[PUNTERO_B],DE
                LD      HL,[PUNTERO_P_DECB]
                CALL    DECODE_CANAL    ; DECODIFICA CANAL B
                LD	[PUNTERO_DECB],HL
                
                LD      DE,[CANAL_C]    
                LD	[PUNTERO_C],DE
                LD      HL,[PUNTERO_P_DECC]
                CALL    DECODE_CANAL    ; DECODIFICA CANAL C
                LD	[PUNTERO_DECC],HL
                
                LD      DE,[CANAL_P]    
                LD      [PUNTERO_P],DE
                LD      HL,[PUNTERO_P_DECP]
                CALL    DECODE_CANAL    ; DECODIFICA CANAL P (Percusión)
                LD      [PUNTERO_DECP],HL
               
                RET

; ==============================================================================
; BLOQUE: BGICMODBC1 - Escanea buscando la siguiente marca de Canal en archivo MUS
; Busca el patrón: 00, 3F, (X), (Y), 00. (Instrumento 0, Volumen 0).
; ==============================================================================
BGICMODBC1:     XOR     A               ; BUSCA EL BYTE 0 (Fin de canal/bloque)
                LD      E,$3F           ; E = CODIGO INSTRUMENTO 0 (63)
                LD      B,$FF           ; Limita a 255 repeticiones de búsqueda
                CPIR                    ; Z80: Busca A (0) en memoria HL, auto-incrementa HL
                
                DEC     HL              ; Retrocede un poco para verificar patrón
                DEC     HL
                LD      A,E             ; A = $3F (Instrumento 0)
                CP      [HL]            ; ES EL INSTRUMENTO 0 ??
                INC     HL
                INC     HL
                JR      Z,BGICMODBC1    ; Si era Instrumento 0, es un falso positivo. Sigue buscando.

                DEC     HL
                DEC     HL
                DEC     HL
                LD      A,E             ; Comprueba si es el volumen 0
                CP      [HL]
                INC     HL
                INC     HL
                INC     HL
                JR      Z,BGICMODBC1    ; Si lo es, sigue buscando
                RET                     ; Si no, HL apunta al inicio real del siguiente canal

; ==============================================================================
; BLOQUE: DECODE_CANAL - Descomprime RLE y comandos de notas en memoria plana
; IN [HL] = ORIGEN COMPRIMIDO, [DE] = DIRECCION DESTINO
; ==============================================================================
; ==============================================================================
; FORMATO MUS (byte comprimido):
;   LL NNNNNN (bin) ? LL=duración codificada, NNNNNN=nota/comando
;   LL: 00b?1, 01b?2, 10b?4, 11b?8
;   NNNNNN:
;     01h ? silencio
;     3Eh ? puntillo
;     3Fh ? comando especial (flags en byte siguiente)
;
; FORMATO PLANO (salida):
;   [evento] [0..duración-1 ceros] [81h] (1000 0001b fin de longitud)
;   Fin de canal: [80h] (1000 0000b)
; ==============================================================================

DECODE_CANAL:   LD A,[HL]            ; Lee byte MUS (LL NNNNNN)
                AND A               ; ¿00h? ? fin de canal
                JR Z,FIN_DEC_CANAL
                CALL GETLEN         ; A=nota/valor, B=duración (1,2,4,8)

                CP 01h              ; ¿silencio?
                JR Z,ES_SILENCIO
                CP 3Eh              ; ¿puntillo?
                JR Z,ES_PUNTILLO
                CP 3Fh              ; ¿comando especial?
                JR Z,ES_COMANDO

NO_MODIFICA:    LD [DE],A           ; Escribe nota/valor
                INC DE
                DEC B               ; ¿quedan ceros?
                JR Z,FIN_RLE
                XOR A               ; A=00h ? ceros

RLE_LOOP:       LD [DE],A           ; Escribe 00h
                INC DE
                DJNZ RLE_LOOP

FIN_RLE:        LD A,81h            ; 1000 0001b ? fin de longitud
                LD [DE],A
                INC DE
                INC HL              ; Avanza origen
                RET

ES_SILENCIO:    SET 6,A             ; Bit6=1 ? silencio (A|40h)
                JR NO_MODIFICA

ES_PUNTILLO:    RRC B               ; B=B/2
                XOR A               ; A=00h
                JR NO_MODIFICA

; ----------------------------------------------------------------------
; COMANDO ESPECIAL (NNNNNN=3Fh)
; Byte siguiente = flags: 00000EVIb
;   I=bit0 ? instrumento
;   V=bit1 ? efecto
;   E=bit2 ? envolvente
; ----------------------------------------------------------------------

ES_COMANDO:     BIT 0,B             ; ¿instrumento?
                JR Z,CHK_ENV
                LD A,0C1h           ; 1100 0001b ? comando instrumento
                LD [DE],A
                INC DE
                INC HL              ; Nº instrumento
                LD A,[HL]
                LD [DE],A
                INC DE
                INC HL              ; Volumen
                LD A,[HL]
                LD [DE],A
                INC DE
                INC HL
                JR DECODE_CANAL

CHK_ENV:        BIT 2,B             ; ¿envolvente?
                JR Z,CHK_EFX
                LD A,0C4h           ; 1100 0100b ? comando envolvente
                LD [DE],A
                INC DE
                INC HL              ; ID envolvente
                LD A,[HL]
                LD [DE],A
                INC DE
                INC HL
                JR DECODE_CANAL

CHK_EFX:        BIT 1,B             ; ¿efecto?
                JR Z,NO_MODIFICA
                LD A,0C2h           ; 1100 0010b ? comando efecto
                LD [DE],A
                INC DE
                INC HL              ; ID efecto
                LD A,[HL]
                CALL GETLEN         ; A=valor efecto, B=duración
                JR NO_MODIFICA

FIN_DEC_CANAL:  LD A,80h            ; 1000 0000b ? fin absoluto de canal
                LD [DE],A
                INC DE
                RET


; ============================================================
; GETLEN - versión optimizada sin DJNZ en DCBC0
; IN:  A = byte MUS (LL NNNNNN)
; OUT: A = nota (6 bits)
;      B = factor (1,2,4,8)
; ============================================================
; ==============================================================================
; GETLEN — Decodifica duración MUS
; Entrada:  A = LL NNNNNN
; Salida:   A = NNNNNN (nota/comando)
;           B = duración (1,2,4,8)
; LL:
;   00b ? 1
;   01b ? 2
;   10b ? 4
;   11b ? 8
; ==============================================================================

GETLEN: 	LD      B,A                 ; Guarda byte original en B
		AND     00111111B           ; A = nota (6 bits)
		PUSH    AF                  ; Guarda nota limpia
		LD      A,B                 ; Recupera original
		AND     11000000B           ; A = LL00 0000
		RLCA                        ; LL pasa a bits 5-4
		RLCA                        ; LL pasa a bits 3-2
		INC     A                   ; A = 1..4 (contador de desplazamientos)
		LD      B,A                 ; B = 1..4
		LD      A,1                 ; empezamos en 1 (x1)

DCBC0_OPT:	DEC     B
		JR      Z,DCBC0_DONE        ; si B=1 ? ya está (1)
		ADD     A,A                 ; x2

		DEC     B
		JR      Z,DCBC0_DONE        ; si B=2 ? x2
		ADD     A,A                 ; x4

		DEC     B
		JR      Z,DCBC0_DONE        ; si B=3 ? x4
		ADD     A,A                 ; x8
        				    ; si B=4 ? cae aquí con A=x8

DCBC0_DONE:	LD      B,A                 ; B = 1,2,4,8
		POP     AF                  ; A = nota limpia
		RET


                
; ==============================================================================
; BLOQUE: PLAY - Máquina de estado (Tick musical frame a frame)
; ==============================================================================
PLAY:           LD      HL,INTERR       ; ¿PLAY BIT 1 ON?
                BIT     1,[HL]
                RET     Z               ; Si música = OFF, salimos

                ; COMPROBACION TEMPO HIBRIDO
                LD      HL,HYBRID
                BIT     7,[HL]          ; ¿Tempo hibrido activo?
                JR      Z,TEMPO_ENTERO  ; Si no, avanza entero clásico
                BIT     6,[HL]          ; Chequea el bit oscilador
                JR      Z,TEMPO_ENTERO  ; Alterna entre semi y entero cada tick para interpolar

TEMPO_SEMI:     LD      HL,TTEMPO       ; CONTADOR TEMPO
                INC     [HL]            ; Incrementa contador
                LD      A,[TEMPO]
                DEC     A               ; Si es semi, el objetivo del tick es un frame menos (Tempo-1)
                CP	[HL]            ; ¿Llegamos al final del delay de nota?
                JR      NZ,PAUTAS       ; Si no, solo procesa macros (pautas)
                LD      [HL],0          ; Reset contador tempo
                LD      HL,HYBRID
                RES     6,[HL]          ; Alterna flag: Próximo paso será ENTERO
                JR      INTERPRETA      ; Pasa a cambiar de nota
                
TEMPO_ENTERO:   LD      HL,TTEMPO       ; CONTADOR TEMPO CLASICO
                INC     [HL]
                LD      A,[TEMPO]
                CP      [HL]            ; ¿Llegó al fin del delay?
                JR      NZ,PAUTAS       ; Si no, sigue tocando la pauta/instrumento actual
                LD      [HL],0
                LD      HL,HYBRID
                SET     6,[HL]          ; Alterna flag: Próximo será SEMI
                
INTERPRETA:     ; Aquí se actualizan las notas si es momento de avanzar el secuenciador
                LD      IY,PSG_REG      ; Punteros Canal A (Frecuencia en R0, R1)
                LD      IX,PUNTERO_A    ; Puntero a la música del canal A
                LD      BC,PSG_REG+8    ; Puntero al Volumen R8
                CALL    LOCALIZA_NOTA   ; Carga la siguiente instrucción A
                
                LD      IY,PSG_REG+2    ; Punteros Canal B (Frecuencia en R2, R3)
                LD      IX,PUNTERO_B    
                LD      BC,PSG_REG+9    ; Volumen R9
                CALL    LOCALIZA_NOTA   
                
                LD      IY,PSG_REG+4    ; Punteros Canal C (Frecuencia en R4, R5)
                LD      IX,PUNTERO_C    
                LD      BC,PSG_REG+10   ; Volumen R10
                CALL    LOCALIZA_NOTA   
                
                LD      IX,PUNTERO_P    ; EL CANAL P (Percusión/SFX) ENMASCARA A LOS OTROS
                CALL    LOCALIZA_EFECTO              

PAUTAS:         ; Independientemente de si cambia de nota, los instrumentos avanzan por "Pautas" cada frame.
                LD      IY,PSG_REG+0    
                LD      IX,PUNTERO_P_A
                LD      HL,PSG_REG+8
                CALL    PAUTA           ; Ejecuta Macro/Instrumento CANAL A
                
                LD      IY,PSG_REG+2
                LD      IX,PUNTERO_P_B
                LD      HL,PSG_REG+9
                CALL    PAUTA           ; Ejecuta Macro/Instrumento CANAL B
                
                LD      IY,PSG_REG+4
                LD      IX,PUNTERO_P_C
                LD      HL,PSG_REG+10
                CALL    PAUTA           ; Ejecuta Macro/Instrumento CANAL C                
                RET

; ==============================================================================
; BLOQUE: LOCALIZA_NOTA - Interpreta los datos descompuestos (Música Canal A/B/C)
; IN[PUNTERO_X] vía indexación [IX]
; ==============================================================================
LOCALIZA_NOTA:  LD      L,[IX+PUNTERO_A-PUNTERO_A] ; HL = Puntero actual del canal
                LD      H,[IX+PUNTERO_A-PUNTERO_A+1]
                LD      A,[HL]          ; Carga el byte
                AND     11000000B       ; Verifica si es ¿COMANDO? (Bits altos a 11)
                CP      11000000B
                JR      NZ,LNJP0        ; Si no es comando, es nota/silencio/bucle. Salta.

; --- INTERPRETE DE COMANDOS (Inst/Env/SFX) ---
COMANDOS:       LD      A,[HL]
                BIT     0,A             ; ¿Es INSTRUMENTO?
                JR      Z,COM_EFECTO    ; Si no, chequea si es efecto

                INC     HL
                LD      A,[HL]          ; Lee N° DE PAUTA (ID Instrumento)
                INC     HL
                LD      E,[HL]          ; Lee Volumen Relativo / TEMPO extra
                
                PUSH    HL              ; --- PARSEO DEL TEMPO GLOBAL ASOCIADO AL INSTRUMENTO ---
                LD      HL,TEMPO
                BIT     5,E             ; ¿Bit 5 activo? Disminuye el tempo global
                JR      Z,NO_DEC_TEMPO
                DEC	[HL]
NO_DEC_TEMPO:   BIT     6,E             ; ¿Bit 6 activo? Incrementa el tempo global
                JR      Z,NO_INC_TEMPO
                INC     [HL]
NO_INC_TEMPO:   RES     5,E             ; Limpia bits de tempo, dejando solo volumen puro
                RES     6,E
                POP     HL
                
                LD	[IX+VOL_INST_A-PUNTERO_A],E ; Guarda el VOLUMEN RELATIVO
                INC     HL
                LD      [IX+PUNTERO_A-PUNTERO_A],L  ; Actualiza Puntero música
                LD	[IX+PUNTERO_A-PUNTERO_A+1],H
                
                LD      HL,TABLA_PAUTAS ; Busca la dirección base del nuevo instrumento
                CALL    EXT_WORD
                
                ; Establece los punteros de Pauta Inicial y Actual (Reinicia envolvente de volumen)
                LD	[IX+PUNTERO_P_A0-PUNTERO_A],L
                LD	[IX+PUNTERO_P_A0-PUNTERO_A+1],H
                LD	[IX+PUNTERO_P_A-PUNTERO_A],L
                LD	[IX+PUNTERO_P_A-PUNTERO_A+1],H
                LD      L,C
                LD      H,B
                RES     4,[HL]          ; APAGA EFECTO ENVOLVENTE hardware para este canal
                XOR     A               ; A=0
                LD      [PSG_REG_SEC+13],A ; Limpia registro 13 (Forma Envolvente)
                LD      [PSG_REG+13],A
                JR      LOCALIZA_NOTA   ; Vuelve a interpretar el siguiente byte

COM_EFECTO:     BIT     1,A             ; ¿Es un EFECTO DE SONIDO en el track?
                JR      Z,COM_ENVOLVENTE; Si no, pasa a comprobar envolvente hw

                INC     HL
                LD      A,[HL]          ; Carga ID de efecto
                INC     HL
                LD	[IX+PUNTERO_A-PUNTERO_A],L ; Guarda puntero música actualizado
                LD      [IX+PUNTERO_A-PUNTERO_A+1],H
                CALL    INICIA_SONIDO   ; Lanza efecto de sonido
                RET

COM_ENVOLVENTE: BIT     2,A
                RET     Z               ; IGNORA / ERROR. Retorna.
           
                INC     HL
                LD      A,[HL]          ; CARGA CODIGO DE ENVOLVENTE
                LD	[ENVOLVENTE],A  ; Guarda el tipo de envolvente
                INC     HL
                LD	[IX+PUNTERO_A-PUNTERO_A],L
                LD	[IX+PUNTERO_A-PUNTERO_A+1],H
                LD      L,C
                LD      H,B
                LD      [HL],00010000B  ; ENCIENDE EFECTO ENVOLVENTE (Escribe 16 en Volumen)
                JR      LOCALIZA_NOTA
                
; --- PARSEO DE DATOS (Nota o Bucle) ---
LNJP0:          LD      A,[HL]          ; Lee la nota pura
                INC     HL
                BIT     7,A             ; Bit 7 marca Fin de Bloque/Paso
                JR      Z,NO_FIN_CANAL_A
                BIT     0,A             ; Bit 0 adicional indica Fin Total
                JR      Z,FIN_CANAL_A

FIN_NOTA_A:     ; Rutina de decodificación al vuelo del siguiente bloque RLE
                LD      E,[IX+CANAL_A-PUNTERO_A]
                LD      D,[IX+CANAL_A-PUNTERO_A+1]  ; Puntero Buffer al Inicio
                LD      [IX+PUNTERO_A-PUNTERO_A],E
                LD	[IX+PUNTERO_A-PUNTERO_A+1],D
                LD      L,[IX+PUNTERO_DECA-PUNTERO_A] ; Carga Puntero Decoder Compressed
                LD      H,[IX+PUNTERO_DECA-PUNTERO_A+1]
                PUSH    BC
                CALL    DECODE_CANAL    ; DECODIFICA siguiente bloque al buffer plano
                POP     BC
                LD	[IX+PUNTERO_DECA-PUNTERO_A],L ; Guarda posición compresión
                LD	[IX+PUNTERO_DECA-PUNTERO_A+1],H
                JP      LOCALIZA_NOTA   ; Reintenta leer el byte recién decodificado
                
FIN_CANAL_A:    LD      HL,INTERR       ; Fin canción. ¿LOOP ACTIVO?
                BIT     4,[HL]              
                JR      NZ,FCA_CONT     ; Si hay loop, continua
                POP     AF
                JP      PLAYER_OFF      ; Si no hay loop, apaga el reproductor
                
FCA_CONT:       LD      L,[IX+PUNTERO_L_DECA-PUNTERO_A] ; Carga PUNTERO INICIAL DEL LOOP
                LD      H,[IX+PUNTERO_L_DECA-PUNTERO_A+1]
                LD      [IX+PUNTERO_DECA-PUNTERO_A],L
                LD      [IX+PUNTERO_DECA-PUNTERO_A+1],H
                JR      FIN_NOTA_A
                
NO_FIN_CANAL_A: LD	[IX+PUNTERO_A-PUNTERO_A],L  ; GUARDA PUNTERO de ejecución actual
                LD      [IX+PUNTERO_A-PUNTERO_A+1],H
                AND     A               ; NO REPRODUCE NOTA SI NOTA=0
                JR      Z,FIN_RUTINA
                BIT     6,A             ; ¿SILENCIO? (Bit 6 fue seteado en el decode)
                JR      Z,NO_SILENCIO_A
                LD      A,[BC]
                AND     00010000B       ; Chequea si estaba usando envolvente HW
                JR      NZ,SILENCIO_ENVOLVENTE
                
                XOR     A
                LD	[BC],A          ; RESET VOLUMEN del chip (Silencio = Vol 0)
                LD	[IY+0],A        ; Resetea Pitch (R0/R2/R4)
                LD	[IY+1],A        ; Resetea Pitch Alto (R1/R3/R5)
                RET
                
SILENCIO_ENVOLVENTE:
                LD      A,$FF           ; Desactiva envolvente
                LD      [PSG_REG+11],A  ; Manda periodo env a $FFFF
                LD      [PSG_REG+12],A               
                XOR     A
                LD	[PSG_REG+13],A  ; Limpia forma                             
                LD      [IY+0],A        ; Pitch a 0
                LD      [IY+1],A
                RET

NO_SILENCIO_A:  LD      [IX+REG_NOTA_A-PUNTERO_A],A 	; Guarda REGISTRO DE LA NOTA DEL CANAL         
                CALL    NOTA            		; Transforma "Nota N" a "Frecuencia MSX"
                LD      L,[IX+PUNTERO_P_A0-PUNTERO_A] 	; RESETEA LA PAUTA DEL INSTRUMENTO
                LD      H,[IX+PUNTERO_P_A0-PUNTERO_A+1]
                LD	[IX+PUNTERO_P_A-PUNTERO_A],L 
                LD	[IX+PUNTERO_P_A-PUNTERO_A+1],H
FIN_RUTINA:     RET

; ==============================================================================
; BLOQUE: LOCALIZA_EFECTO - Interpreta datos del Canal Percusión y eventos (P)
; IN: HL=[PUNTERO_P] vía[IX]
; ==============================================================================


LOCALIZA_EFECTO:LD      L,[IX+0]        ; HL = [PUNTERO_P]
                LD      H,[IX+1]
                LD      A,[HL]
                CP      11000010B       ; Comando "Efecto HW/SFX"
                JR      NZ,LEJP0

                INC     HL
                LD      A,[HL]
                INC     HL
                LD      [IX+00],L
                LD	[IX+01],H
                CALL    INICIA_SONIDO
                RET
            
LEJP0:          INC     HL
                BIT     7,A
                JR      Z,NO_FIN_CANAL_P
                BIT     0,A
                JR      Z,FIN_CANAL_P
                
FIN_NOTA_P:     LD      DE,[CANAL_P]
                LD      [IX+0],E
                LD	[IX+1],D
                LD      HL,[PUNTERO_DECP] ; Carga Puntero Compresor Percusión
                PUSH    BC
                CALL    DECODE_CANAL    ; DECODIFICA al vuelo
                POP     BC
                LD      [PUNTERO_DECP],HL 
                JP      LOCALIZA_EFECTO
                
FIN_CANAL_P:    LD      HL,[PUNTERO_L_DECP] ; Loop decoder Percusión
                LD      [PUNTERO_DECP],HL
                JR      FIN_NOTA_P
                
NO_FIN_CANAL_P: LD	[IX+0],L        ; Guarda puntero ejecución
                LD      [IX+1],H
                RET

; ==============================================================================
; BLOQUE: PAUTA - Máquina de Instrumentos/Macros (Volumen, arpegios y vibratos)
; IN: [IX] = PUNTERO DE LA PAUTA (Inst) | [HL] = REG. VOLUMEN | [IY] = REG. FREC
; FORMATO DE MACRO (2 BYTES POR FRAME): 
; BYTE 1:[ LOOP | OCT-1 | OCT+1 | ORNMT | VOL (3-0) ]  
; BYTE 2:[ PITCH (Offset fino) / NOTA ORNAMENTO ]
; ==============================================================================

PAUTA:
                BIT     4,[HL]                  ; Si envolvente HW activa ? no pauta
                RET     NZ                      ; Salir si HW domina

                LD      A,[IY+0]                ; Cargar parte baja de frecuencia
                OR      [IY+1]                  ; OR con parte alta (optimización)
                RET     Z                       ; Si frecuencia = 0 ? no pauta

                PUSH    HL                      ; Guardar puntero de volumen

; ------------------------------------------------------------------------------
; LECTURA DE PAUTA (HL ? puntero de macro)
; ------------------------------------------------------------------------------
PCAJP4:         LD      L,[IX+00h]              ; Cargar puntero pauta (low)
                LD      H,[IX+01h]              ; Cargar puntero pauta (high)
                LD      A,[HL]                  ; Leer Byte1 de macro

; ------------------------------------------------------------------------------
; LOOP (bit 7)
; ------------------------------------------------------------------------------
                BIT     7,A                     ; ¿Loop activo?
                JR      Z,PCAJP0                ; Si no, saltar
                AND     1Fh                     ; Extraer valor de loop (0..31)
                RLCA                            ; x2 (cada instrucción = 2 bytes)
                LD      D,00h                   ; DE = desplazamiento
                LD      E,A
                SBC     HL,DE                   ; Retroceder HL
                LD      A,[HL]                  ; Releer Byte1 tras loop

; ------------------------------------------------------------------------------
; OCTAVA -1 (bit 6)
; ------------------------------------------------------------------------------
PCAJP0:         BIT     6,A                     ; ¿Octava baja?
                JR      Z,PCAJP1                ; Si no, saltar
                LD      E,[IY+0]                ; Cargar frecuencia actual
                LD      D,[IY+1]
                XOR     A                       ; Limpia carry (optimización)
                RRC     D                       ; Rotación ? divide periodo por 2
                RR      E
                LD      [IY+0],E                ; Guardar nueva frecuencia
                LD      [IY+1],D
                JR      PCAJP2                  ; Saltar a siguiente fase

; ------------------------------------------------------------------------------
; OCTAVA +1 (bit 5)
; ------------------------------------------------------------------------------
PCAJP1:         BIT     5,A                     ; ¿Octava alta?
                JR      Z,PCAJP2                ; Si no, saltar
                LD      E,[IY+0]
                LD      D,[IY+1]
                XOR     A                       ; Limpia carry
                RLC     E                       ; Rotación ? multiplica periodo por 2
                RL      D
                LD      [IY+0],E
                LD      [IY+1],D

; ------------------------------------------------------------------------------
; ¿ORNAMENTO? (bit 4)
; ------------------------------------------------------------------------------
PCAJP2:         LD      A,[HL]                  ; Recuperar Byte1
                BIT     4,A                     ; ¿Ornamento?
                JR      NZ,PCAJP6               ; Si sí ? arpegio

; ------------------------------------------------------------------------------
; PITCH FINO (vibrato / slide)
; ------------------------------------------------------------------------------
                INC     HL                      ; Byte2
                PUSH    HL                      ; Guardar puntero
                LD      E,A                     ; Guardar Byte1
                LD      A,[HL]                  ; Cargar pitch
                LD      L,A                     ; HL = pitch
                OR      A                       ; ¿Pitch = 0?
                LD      A,E                     ; Recuperar Byte1
                JR      Z,ORNMJP1               ; Si 0 ? nada

                LD      A,[IY+0]                ; Si frecuencia = 0 ? nada
                ADD     A,[IY+1]
                OR      A
                LD      A,E
                JR      Z,ORNMJP1

                BIT     7,L                     ; ¿Pitch negativo?
                JR      Z,ORNNEG                ; Si no, positivo
                LD      H,0FFh                  ; Extensión de signo negativa
                JR      PCAJP3
ORNNEG:         LD      H,00h                   ; Extensión de signo positiva

PCAJP3:         LD      E,[IY+0]                ; Cargar frecuencia actual
                LD      D,[IY+1]
                ADC     HL,DE                   ; Aplicar pitch
                LD      [IY+0],L                ; Guardar nueva frecuencia
                LD      [IY+1],H
                JR      ORNMJP1                 ; Continuar

; ------------------------------------------------------------------------------
; ORNAMENTOS (arpegios)
; ------------------------------------------------------------------------------
PCAJP6:         INC     HL                      ; Byte2
                PUSH    HL                      ; Guardar puntero
                PUSH    AF                      ; Guardar Byte1
                LD      A,[IX+REG_NOTA_A-PUNTERO_P_A] ; Nota base
                LD      E,[HL]                  ; Desplazamiento semitonal
                ADD     A,E                     ; Nota final
                CALL    TABLA_NOTAS             ; Convertir a frecuencia
                POP     AF                      ; Recuperar Byte1

; ------------------------------------------------------------------------------
; AVANZAR PAUTA
; ------------------------------------------------------------------------------
ORNMJP1:        POP     HL                      ; Recuperar puntero de pauta
                INC     HL                      ; Avanzar 2 bytes
                LD      [IX+00h],L              ; Guardar puntero actualizado
                LD      [IX+01h],H

; ------------------------------------------------------------------------------
; *** BLOQUE DE VOLUMEN ORIGINAL (NO TOCAR) ***
; ------------------------------------------------------------------------------
                POP     HL                      ; HL = registro de volumen
                AND     0Fh                     ; Volumen de pauta (0..15)
                LD      C,A                     ; Guardar volumen pauta
                LD      A,[IX+VOL_INST_A-PUNTERO_P_A] ; Volumen relativo canal
                BIT     4,A                     ; ¿Envolvente HW?
                JR      Z,PCAJP9                ; Si no, continuar
                OR      0F0h                    ; Mantener bit HW
PCAJP9:         ADD     A,C                     ; Combinar vol pauta + vol canal
                JP      P,PCAJP7                ; Si no negativo
                LD      A,01h                   ; No permitir 0
PCAJP7:         CP      0Fh                     ; ¿>15?
                JP      M,PCAJP8                ; Si no, OK
                LD      A,0Fh                   ; Saturación alta
PCAJP8:         LD      [HL],A                  ; Escribir volumen final
                RET                             ; Fin de PAUTA



; ==============================================================================
; BLOQUE: NOTA - Busca Periodo (Frecuencia) dada una nota (Pitch Index)
; IN: [A] = CODIGO DE LA NOTA (0..127) | [IY] = REGISTROS DE FRECUENCIA
; ==============================================================================
NOTA:           LD      L,C             ; Recupera Puntero de Volumen en HL
                LD      H,B
                BIT     4,[HL]          ; Comprueba bit 4 de volumen (Flag envolvente hw)
                LD      B,A             ; Respaldo de nota
                JR      NZ,EVOLVENTES   ; Si hay envolvente HW, el pitch se calcula distinto
                LD      A,B

TABLA_NOTAS:    ; Rutina externa que puede ser llamada desde ornamentos
                LD      HL,DATOS_NOTAS  ; BUSCA FRECUENCIA en Array de 16 bits
                CALL    EXT_WORD        ; Extrae palabra [HL] -> HL
                LD	[IY+0],L        ; Guarda periodo Bajo en PSG_REG (R0/R2/R4)
                LD      [IY+1],H        ; Guarda periodo Alto en PSG_REG (R1/R3/R5)
                RET

; ==============================================================================
; BLOQUE: EVOLVENTES - Sincronización del Pitch musical con el Periodo del HW Env
; ==============================================================================
; IN: [A] = CODIGO DE LA ENVOLVENTE (y modificadores) | [IY] = REG FREC
; BLOQUE: EVOLVENTES - Sincronización del Pitch musical con el Periodo del HW Env
; Formato del byte de envolvente:
; bit0 = tono ON/OFF | bits1–2 = ratio (divisor periodo env) | bits3–7 = forma HW (8–15)

EVOLVENTES:     LD      HL,DATOS_NOTAS          ; Tabla de periodos base
                RLCA                            ; A = A * 2 (índice word)
                LD      D,0                     ; DE = A * 2
                LD      E,A
                ADD     HL,DE                   ; HL = &periodo nota
                LD      E,[HL]                  ; E = low
                INC     HL
                LD      D,[HL]                  ; D = high (DE = periodo)

                PUSH    DE                      ; Guarda periodo para el HW env

                LD      A,[ENVOLVENTE]          ; Config envolvente canal
                RRA                             ; Bit0 ? carry: tono ON/OFF
                JR      NC,FRECUENCIA_OFF       ; Si 0 ? tono OFF (solo env HW)
                LD      [IY+0],E                ; Aplica periodo al tono
                LD      [IY+1],D
                JR      CONT_ENV                ; Sigue con cálculo de env

FRECUENCIA_OFF: LD      DE,0                    ; Tono puro a 0 (solo env HW)
                LD      [IY+0],E
                LD      [IY+1],D

CONT_ENV:       POP     DE                      ; Recupera periodo original
                PUSH    AF                      ; Guarda A (ENVOLVENTE)
                PUSH    BC                      ; Preserva BC

                AND     00000011B               ; Ratio env (bits 1–0)
                INC     A                       ; Shifts totales = A+1 (antes era 1+B)
                LD      B,A                     ; B = nº de divisiones

CRTBC0:         RR      D                       ; Divide periodo por 2
                RR      E
                DJNZ    CRTBC0                  ; Repite según ratio

                LD      A,E
                LD      [PSG_REG+11],A          ; R11 = periodo env low
                LD      A,D
                AND     00000011B               ; Seguridad bits altos
                LD      [PSG_REG+12],A          ; R12 = periodo env high

                POP     BC                      ; Restaura BC
                POP     AF                      ; Recupera ENVOLVENTE

                				; SELECCION FORMA DE ENVOLVENTE
                RRA                             ; Baja bits 
                AND     00000110B               ; Filtra indices
                ADD     8                       ; Formas válidas 8–14
                LD      B,A                     ; B = nueva forma

                LD      A,[ENVOLVENTE_BACK]     ; A = forma anterior
                CP      B                       ; ¿Es la misma?
                JR      Z,NO_CAMBIO_ENV         ; Si igual ? no reiniciar

                LD      A,B                     ; A = nueva forma
                LD      [PSG_REG+13],A          ; Escribir forma ? reinicia fase
                LD      [ENVOLVENTE_BACK],A     ; Guardar forma actual
                JR      FIN_ENV

NO_CAMBIO_ENV:
                				; No escribir R13 ? no reinicia fase
                				; Pero sí actualizar PSG_REG+13 para ROUT
                LD      A,0
                LD      [PSG_REG+13],A

FIN_ENV:
                RET
  

; ==============================================================================
; BLOQUE: EXT_WORD - Utilidad de extracción de Words (16-bits) desde un array
; IN: [HL] = DIR BASE TABLA | [A] = INDICE
; OUT: [HL] = Palabra/Puntero devuelto
; ==============================================================================
EXT_WORD:       LD      D,0
                RLCA                    ; A = A * 2 (Array indexado por Words de 2 bytes)
                LD      E,A
                ADD     HL,DE           ; HL = HL + (A * 2)
                LD      E,[HL]          ; Carga Byte bajo
                INC     HL
                LD      D,[HL]          ; Carga Byte alto
                EX      DE,HL           ; Intercambia (HL = D:E)
                RET
                
; ==============================================================================
; TABLA DE DATOS DEL SELECTOR DEL CANAL DE EFECTOS DE RITMO
; ==============================================================================
TABLA_DATOS_CANAL_SFX:
                DW      SELECT_CANAL_A,SELECT_CANAL_B,SELECT_CANAL_C

; Formato de subtablas:
; BYTE 0,1 : Puntero indirecto SFX_L (Registro de Tono Fino Canal)
; BYTE 2,3 : Puntero indirecto SFX_H (Registro de Tono Alto Canal)
; BYTE 4,5 : Puntero indirecto SFX_V (Registro de Volumen de Canal)
; BYTE 6   : Máscara SFX_MIX para Registro 7 del AY-3-8910 (Bit 0-5 controlan Tonos y Ruidos)

SELECT_CANAL_A: DW      PSG_REG_SEC+0, PSG_REG_SEC+1, PSG_REG_SEC+8
                DB      10110001B       ; Mixer: Ruido y Tono encendidos selectivamente
                
SELECT_CANAL_B: DW      PSG_REG_SEC+2, PSG_REG_SEC+3, PSG_REG_SEC+9
                DB      10101010B       
                
SELECT_CANAL_C: DW      PSG_REG_SEC+4, PSG_REG_SEC+5, PSG_REG_SEC+10
                DB      10011100B