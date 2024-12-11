; TO BE RAN AT 20,000 CYCLES

[org 0x0100]
    jmp start

; ====== GLOBALS ======r
    
    bgFileName:     db "bg.bmp", 0
    lavaFileName:   db "lava.bmp", 0
    pillarFileName: db "pillar.bmp", 0
    pillarinvFileName: db "rallip.bmp", 0
    gokuFileName:   db "goku.bmp", 0
    introFileName:     db "intro.bmp", 0
    pauseFileName:   db "pause.bmp", 0
    joeverFileName:   db "joever.bmp", 0
    scoreFileName:   db "dig0.bmp", 0

    pcb: times 2 * 2 dw 0  ; space for 2 PCBs
    ; 0:ss 1:sp
    currentPCB: dw 0        ; index of current pcb  buffer: times 4 db 0
	stack: times 256 dw 0
    buffer: times 320 db 0

    currentScreen: db 0
    ; 0: intro   1: game  2: pre-game    3: joever   4: pause   5: exit code

    score: dw 0

    gokuVelocity : dw 2
    gokuHeight: dw 50

    pillars: dw 0xffff, 30    ; posX of right edge, offY
             dw 350, 80       ; same thing for second pillar

    oldISR8: dw 0, 0
    oldISR9: dw 0, 0

; ====== MACROS ======
macros:
    %macro DRAW_IMAGE 7
    push %1 ; file name
    push %2 ; posX
    push %3 ; posY
    push %4 ; sizeX
    push %5 ; sizeY
    push %6 ; offsetX
    push %7 ; offsetY
    call draw
    %endmacro

    %macro DRAW_PILLARSET 3
    push %3 ; offsetY
    push %2 ; offsetX
    push %1 ; posX
    call drawPillarset
    %endmacro

    %macro ERASE_PILLARSET 2
    push %2 ; offY
    push %1 ; posX
    call erasePillarset
    %endmacro

    %macro DRAW_LAVA 1 
    mov ax, 320
    sub ax, %1
    DRAW_IMAGE lavaFileName, %1, 170, ax, 30, 0, 0
    DRAW_IMAGE lavaFileName, 0, 170, %1, 30, ax, 0
    %endmacro

    %macro OPEN_FILE 1
    mov ah, 0x3d
    mov al, 0
    mov dx, %1          ; 0 Terminated String (File Name)
    int 0x21
    ; returns file handle in AX
    %endmacro

    %macro READ_FILE 3
    mov ah, 0x3f        
    mov bx, %1          ; File handle
    mov cx, %2          ; Bytes to read
    mov dx, %3          ; Buffer location
    int 0x21
    %endmacro

    %macro SEEK_FILE 4
    mov ah, 0x42        
    mov al, %1          ; Seek mode (0: start, 1: current, 2: end)
    mov bx, %2          ; File handle
    mov cx, %3          ; High word of offset
    mov dx, %4          ; Low word of offset
    int 0x21
    %endmacro

    %macro CLOSE_FILE 1
    mov ah, 0x3e        
    mov bx, %1          ; File handle
    int 0x21
    %endmacro


; ====== START ======
start:
    ; Change to Graphics Mode
    mov ah, 0x00       ; Function to set video mode
    mov al, 0x13       ; Video Mode
    int 0x10

    ; ====== PALETTE LOADING ======

    mov bp, sp
    push 0              ; local variable, file handle
    push 0              ; local variable, color number

    OPEN_FILE bgFileName
    mov word [bp - 2], ax
    SEEK_FILE 0, word [bp - 2], 0, 0x36 
    
    paletteFillingLoop:
    READ_FILE word [bp - 2], 4, buffer

    ; [0, 255] -> [0, 63]
    shr byte[buffer], 2
    shr byte[buffer + 1], 2
    shr byte[buffer + 2], 2
    
    ; change palette definition
    mov bx, [bp - 4]        ; color number
    mov dh, [buffer + 2]    ; Red
    mov ch, [buffer + 1]    ; Green
    mov cl, [buffer]        ; Blue
    mov ax, 0x1010          ; Video BIOS function to change palette color
    int 0x10                ; Video BIOS interrupt
   
    inc byte [bp - 4]       ; increment color number
    jnz paletteFillingLoop

    ; pop locals and close file
    add sp, 2               
    pop bx
    CLOSE_FILE bx

    ; ====== SAVE DEFAULT ISRs ======
    push 0
    pop es 
    push cs 
    pop ds
    
    mov ax, [es:8*4]
    mov word [oldISR8], ax
    mov ax, [es:8*4 + 2]
    mov word [oldISR8 + 2], ax

    mov ax, [es:9*4]
    mov word [oldISR9], ax
    mov ax, [es:9*4 + 2]
    mov word [oldISR9 + 2], ax

    ; ====== INIT PCBs ======
    ; 0:ax 1:bx 2:cx 3:dx 4:si 5:di 6:bp 7:sp 8:ip 9:cs 10:ds 11:ss 12:es 13:flags 14:next 15:dummy4alignment   

    mov word [pcb+4+0], ds
	mov word [pcb+4+2], stack + 256*2 - 6 - 16 - 4
	mov word [stack+256*2-2], 0x0200
	mov word [stack+256*2-4], cs
	mov word [stack+256*2-6], musicPlayer
	mov word [stack+256*2-6-16-2], ds
	mov word [stack+256*2-6-16-4], ds
	mov word [stack+256*2-6-2*5], stack+256*2-6

    ; ====== HOOK IRS ======
    cli 
    mov word [es:8*4], timer
    mov word [es:8*4+2], cs 

    mov word [es:9*4], kbisr
    mov word [es:9*4+2], cs 
    sti 

    ; ====== GAME START ======

intro:
    cmp byte[currentScreen], 0
    jne game

    DRAW_IMAGE introFileName, 0, 0, 320, 200, 0, 0

    jmp intro
game:
    cmp byte[currentScreen], 1
    jne gameOver

    call gameLoop
    jmp intro
gameOver:
    cmp byte[currentScreen], 3
    jne exit

    call joeverScreen
    awaitInput:
    cmp byte[currentScreen], 3
    je awaitInput
    jmp intro
exit:
    ; Reset video mode to Text Mode
    mov ah, 0x00
    mov al, 0x02
    int 0x10         
    
    ; Unhook Custom ISRs
    push 0
    pop es
    push cs
    pop ds

    mov ax, [oldISR8]
    mov word [es:8*4], ax
    
    mov ax, [oldISR8 + 2]
    mov [es:8*4 + 2], ax

    mov ax, [oldISR9]
    mov word [es:9*4], ax

    mov ax, [oldISR9 + 2]
    mov [es:9*4 + 2], ax
   
    ; Terminate program
    mov ax, 0x4c00     
    int 0x21    

; ====== GAME LOOP ======
gameLoop:
    push bp
    mov bp, sp
    push 320    ; lava offset
    
    push cs
    pop ds

    DRAW_IMAGE bgFileName, 0, 0, 320, 200, 0, 0
    DRAW_IMAGE gokuFileName, 30, word[gokuHeight], 60, 32, 0, 0	
	DRAW_LAVA 320
	
	mov byte[currentScreen], 2
	awaitInput2:
	cmp byte[currentScreen], 2
	je awaitInput2
	
    DRAW_IMAGE bgFileName, 0, 0, 320, 200, 0, 0
	

mainGameLoop:
    cmp byte[currentScreen], 2
    je pauseScreen
    cmp byte[currentScreen], 1
    jne exitGameLoop
    mov ax, [score]
    mov cx, 2
    mov dx, 0
    div cx
    cmp dx, 0
    jne mainGameLoop

    ; ====== PILLAR GENERATION ======
    mov si, pillars
    
    cmp word [pillars], 0
    jg pillar1Set      ; skip if pillar#1 already exists
    cmp word [pillars + 4], 100
    jg pillar1Set       ; skip if pillar#2 is too close

    mov ax, [score]

    mov cx, 70          
    mov dx, 0
    div cx              ; generate pseudo-random number from 0 - 69
    add dx, 10
    mov word [pillars], 320 + 38 - 2
    mov word [pillars + 2], dx

    pillar1Set:         
    ; same code here just the other way around
    cmp word [pillars + 4], 0
    jg pillarDrawingLoop
    cmp word [pillars], 100
    jg pillarDrawingLoop

    mov ah, 0x00
    int 0x1a             

    mov ax, [score]
    mov cx, ax
    mul cx
    shr ax, 2
    mov cx, 70          
    mov dx, 0
    div cx              ; generate pseudo-random number from 0 - 69
    add dx, 10
    mov word [pillars + 4], 320 + 38 - 1
    mov word [pillars + 6], dx

    ; ====== PILLAR DRAWING ======

    mov si, pillars
    pillarDrawingLoop:
    cmp si, pillars + 8
    je pillarsDrawn

    cmp word [si], 0
    jl pillarLoopControl

    mov cx, 0           ; offX
    mov ax, [si]
    sub ax, 38          ; posX of upper left corner

    cmp ax, 0
    jnl pillarParamsCalculated

    mov cx, ax          ; for pillar contact with left edge of screen
    not cx
    inc cx
    mov ax, 8

    pillarParamsCalculated:
    ERASE_PILLARSET word[si], word[si + 2]

    sub word[si], 8     ; set New Position
    cmp word[si], 8
    jl pillarLoopControl

    sub ax, 8
    DRAW_PILLARSET ax, cx, word [si + 2]

    pillarLoopControl:
    add si, 4
    jmp pillarDrawingLoop

    pillarsDrawn:

    ; ====== GOKU PHYSICS ======

    DRAW_IMAGE bgFileName, 30, word[gokuHeight], 60, 32, 30, word [gokuHeight]
    
    mov ax, [gokuVelocity]
    add word [gokuHeight], ax
        
    cmp word [gokuHeight], 170 - 32     ; floor - characterSize
    jl gokuAboveLava
    mov byte[currentScreen], 3          ; declare game over
    mov word [gokuHeight], 170 - 32
    jmp gokuPositionSet
    
    gokuAboveLava:
    cmp word [gokuHeight], 0
    jg gokuPositionSet
    mov word [gokuHeight], 0

    gokuPositionSet:
    DRAW_IMAGE gokuFileName, 30, word[gokuHeight], 60, 32, 0, 0
    add word [gokuVelocity], 1

    ; ====== COLLISION DETECTION ======

    mov si, pillars

    collisionDetectorLoop:
    cmp si, pillars + 8
    je endDetection

    ; check collider-A
    cmp word [si], 30 + 39
    jl checkColliderB
    cmp word [si], 30 + 39 + 16
    jg checkColliderB

    mov ax, 101        ; pillar length
    sub ax, [si + 2]   ; - offset
    ; ax = depth of safe area
    mov bx, [gokuHeight]
    add bx, 8               ; y of start of collider
    cmp bx, ax
    jl collisionDetected
    add ax, 70              ; start of second pillar
    add bx, 16              ; collider height
    cmp bx, ax
    jg collisionDetected

    checkColliderB:
    cmp word [si], 30 + 8
    jl noCollisionDetected
    cmp word [si], 30 + 8 + 40
    jg noCollisionDetected

    mov ax, 101        ; pillar length
    sub ax, [si + 2]   ; - offset
    ; ax = depth of safe area
    mov bx, [gokuHeight]
    add bx, 17               ; y of start of collider
    cmp bx, ax
    jl collisionDetected
    add ax, 70              ; start of second pillar
    add bx, 14              ; collider height
    cmp bx, ax
    jg collisionDetected
    
    noCollisionDetected:
    add si, 4
    jmp collisionDetectorLoop

    collisionDetected:
    mov byte[currentScreen], 3
    endDetection:

    ; ====== LAVA FLOW ======
    sub word[bp - 2], 2
    cmp word[bp - 2], 0
    jg lavaOffsetCorrect
    mov word[bp - 2], 318
    lavaOffsetCorrect:
    DRAW_LAVA word[bp - 2]

    jmp mainGameLoop
pauseScreen:
    jmp mainGameLoop
exitGameLoop:
    add sp, 2   ; pop local variable
    pop bp
    ret    

; ====== MENUS ======

joeverScreen:
    DRAW_IMAGE joeverFileName, 0, 0, 320, 200, 0, 0

    mov ax, [score]    
    xor cx, cx              ; Clear digit counter

    mov di, 300             ; init printing location
    mov bx, 10
    scorePrintingLoop:
    xor dx, dx              ; Clear DX for division
    div bx             
    add dl, '0'             ; Convert remainder to ASCII character
    mov byte [scoreFileName + 3], dl

    DRAW_IMAGE scoreFileName, di, 180, 14, 16, 0, 0 
    sub di, 14
    cmp ax, 0
    jne scorePrintingLoop   ; Continue if not zero

    ret


; ====== HELPERS ======
drawPillarset:
    ; [bp + 8] offY    
    ; [bp + 6] offX
    ; [bp + 4] posX
    push bp 
    mov bp, sp
    pusha

    mov ax, 101
    sub ax, [bp + 8] ; upper pillar length

    mov dx, 38
    sub dx, [bp + 6] ; pillar width

    DRAW_IMAGE pillarinvFileName, word [bp + 4], 0, dx, ax, word [bp + 6], word [bp + 8]

    mov cx, ax   
    add cx, 70  ; starting point for lower pillar = height of top + gap size

    mov bx, 200 - 30
    sub bx, cx  ; lower pillar length 
    
    DRAW_IMAGE pillarFileName, word [bp + 4], cx, dx, bx, word [bp + 6], 0
    
    popa
    pop bp
    ret 6

erasePillarset:
    ; [bp + 4] posX
    ; [bp + 6] offY
    push bp 
    mov bp, sp
    push ax
    push bx
    push cx

    mov cx, 14
    sub word [bp + 4], 13
    cmp word [bp + 4], 0
    jnl pillarErasingPositionSet
    mov cx, 38
    mov word [bp + 4], 0
    pillarErasingPositionSet:

    mov ax, 101
    sub ax, [bp + 6] ; upper pillar length

    DRAW_IMAGE bgFileName, word [bp + 4], 0, cx, ax, word [bp + 4], 0
    
    add ax, 70
    mov bx, 170
    sub bx, ax

    DRAW_IMAGE bgFileName, word[bp + 4], ax, cx, bx, word [bp + 4], ax

    pop cx
    pop bx
    pop ax
    pop bp
    ret 4
draw:
    ; [bp + 16] file
    ; [bp + 14] posX
    ; [bp + 12] posY
    ; [bp + 10] sizeX
    ; [bp + 8]  sizeY
    ; [bp + 6]  offsetX
    ; [bp + 4]  offsetY
    push bp 
    mov bp, sp
    sub sp, 6
    ; [bp - 6] height
    ; [bp - 4] width 
    ; [bp - 2] padding
    pusha

    ; ====== INITIALIZING LOCALS ======

    push cs
    pop ds

    OPEN_FILE word [bp + 16]
    mov word [bp + 16], ax      ; file handle stored inplace of filename

    ; store width
    SEEK_FILE 0, word [bp + 16], 0, 0x12
    READ_FILE word [bp + 16], 4, buffer
    mov ax, [buffer]
    mov word [bp - 4], ax       

    ; calculate and store padding per row
    mov word [bp - 2], 0
    mov cx, 4   
    mov dx, 0        
    div cx
    
    cmp dx, 0
    je paddingSet
    mov word [bp - 2], 4
    sub word [bp - 2], dx

    paddingSet:
    ; store height
    READ_FILE word [bp + 16], 4, buffer
    mov ax, [buffer]
    mov word [bp - 6], ax

    ; ====== SETTING READER LOCATION ======

    mov ax, [bp - 4]
    add ax, [bp - 2]    ; width + padding
    
    mov cx, [bp + 4]
    add cx, [bp + 8]    ; offY + sizeY

    mul cx
    not ax
    inc ax              ; minus (rowLength)(offY + sizeY)
    
    add ax, [bp + 6]
    mov dx, ax          ; offX - (rowLength)(offY + sizeY)


    sub dx, 2           ; 2 byte offset at end of all files
    SEEK_FILE 0x02, word [bp + 16], 0xffff, dx

    ; ====== SETTING WRITER LOCATION ======
    
    mov ax, 0xa000
    mov es, ax

    mov ax, [bp + 8]
    add ax, [bp + 12]
    dec ax
    mov cx, 320
    mul cx
    add ax, [bp + 14]   ; posX + (posY + sizeY - 1) * 320
    mov di, ax

    ; ====== WRITING ======

    mov dx, [bp + 8]    ; rows
    outerDrawingLoop:
    cmp dx, 0
    je outterDrawingLoopExit

    push dx
    READ_FILE word [bp + 16], word [bp + 10], buffer

    mov si, buffer
    push di
    
    mov cx, 0
    innerDrawingLoop:           ; iterates through different pixels in a given row
    lodsb
    cmp al, 0x15                ; Bright Green, Used As a Placeholder for Transparency in my BMPs
    je pixelDrawn
    mov byte [es:di], al
    
    pixelDrawn:
    inc di
    inc cx
    cmp cx, [bp + 10]
    je innerDrawingLoopExit     ; sizeX pixels drawn

    ; check for row overflow
    push cx
    mov ax, di
    mov dx, 0
    mov cx, 320
    div cx
    pop cx
    cmp dx, 0                   
    jz innerDrawingLoopExit

    jmp innerDrawingLoop
    innerDrawingLoopExit:
    mov dx, [bp - 2]
    add dx, [bp - 4]
    sub dx, cx
    SEEK_FILE 0x01, [bp + 16], 0, dx
    
    ; move writer to start of upper row
    pop di              
    sub di, 320

    pop dx
    dec dx
    jmp outerDrawingLoop

    outterDrawingLoopExit:

    CLOSE_FILE [bp + 16]
    popa
    add sp, 6
    pop bp
    ret 14



; ====== CUSTOM ISRs ======
timer:		    
    cmp byte[cs:currentScreen], 1
    jne scheduler
    inc word [cs:score]
    
    scheduler:
    ; ; push ds
    ; ; push cs
    ; ; pop ds                  ; initialize ds to cs
    
    ; pusha
	; push ds
	; push es
	
	; push cs
	; pop ds
	
    ; mov bx, [currentPCB]    ; read index of current in bx
    ; shl bx, 2               ; multiply by 32 for pcb start
    
    ; ; 0:ax 1:bx 2:cx 3:dx 4:si 5:di 6:bp 7:sp 8:ip 9:cs 10:ds 11:ss 12:es 13:flags 14:next 15:dummy4alignment   
    ; mov word [pcb+bx+0],  ss 
    ; mov word [pcb+bx+2],  sp
    
	; add word [currentPCB], 1
	; and word [currentPCB], 1
	
    ; mov bx, [currentPCB]
    ; shl bx, 2           ; multiply by 32 for pcb start
    
    ; mov sp, [pcb+bx+2]
    ; mov ss, [pcb+bx+0]
	
    mov al, 0x20
    out 0x20, al        ; send EOI to PIC    
	
	; pop es
    ; pop ds     
	; popa
    ; mov ax, [cs:pcb+bx+0] 
    iret                ; return to new process 
kbisr:
    push ax
    push es

    mov ax, 0xb800
    mov es, ax				
    in al, 0x60     ; read scancode		
    
    ; ======= MAIN MENU CONTROLS =======
    cmp byte[currentScreen], 0
    jne notInMode0

    cmp al, 57     ; space
    je setModeTo1
    cmp al, 1      ; escape
    jne kbisrEnd 
    mov byte[currentScreen], 4
    jmp kbisrEnd

    ; ======= IN GAME CONTROLS =======
    notInMode0:
    cmp byte[currentScreen], 1	
    jne notInMode1
    
    cmp al, 1 
    jne noPause
    DRAW_IMAGE pauseFileName, 0, 0, 320, 200, 0, 0
    mov byte[currentScreen], 2
    jmp kbisrEnd
    noPause:
    cmp al, 57	; scan code of space				
    jne kbisrEnd				  
    mov word [cs:gokuVelocity], -8
    jmp kbisrEnd					

    ; ======= PAUSE CONTROLS =======
    notInMode1:
    cmp byte[currentScreen], 2
    jne notInMode2

    cmp al, 1
    jne pausedButNotQuit
    mov byte[currentScreen], 0
    jmp kbisrEnd
    pausedButNotQuit:
    cmp al, 57
    jne kbisrEnd
    DRAW_IMAGE bgFileName, 0, 0, 320, 200, 0, 0
    mov byte[currentScreen], 1
    jmp kbisrEnd

    ; ======= GAME OVER SCREEN CONTROLS =======
    notInMode2: 
    ; necessarily in mode 3
    cmp al, 19	; 'r'/'R'
    je setModeTo1 
    cmp al, 1   ; escape
    jne kbisrEnd
    mov byte[currentScreen], 0
    jmp kbisrEnd

    setModeTo1:
    mov word[score], 0
    mov word[gokuHeight], 50
    mov word[gokuVelocity], 0
    mov word[pillars], 0
    mov word[pillars + 4], 0
    mov byte[currentScreen], 1
    jmp kbisrEnd

    
    kbisrEnd:	
	mov al, 0x20
    out 0x20, al					; send EOI to PIC
    
    pop es
    pop ax
    iret

; ====== MUSIC ======

musicPlayer:
    mov si, 0 
	nextNote:
    mov dx, 388h
    mov al, [si + music + 0]
    out dx, al

    mov dx, 389h
    mov al, [si + music + 1]
    out dx, al
    
    mov bx, [si + music + 2]

    add si, 4

	songLoopDelay:	
    mov cx, 1000 ; <- change this value according to the speed
                    ;    of your computer / emulator
	songDelay:
    mov ah, 1
    int 16h
    jnz songExit
    
    loop songDelay
    
    dec bx
    jg songLoopDelay
    
    cmp si, [musicLength]
    jb nextNote
		
	songExit:	
    jmp $

    musicLength: dw 18644
    music: incbin "music.imf"

debuggingGOAT:
    pusha
    push 0xa000
    pop es
    mov si, 0
    mov cx, 320 * 200
    mov ax, 14h
    rep stosb
    popa
    ret