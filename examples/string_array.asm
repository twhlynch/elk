.ORIG 0x3000

    lea r1, Words       ; base = &Words
    and r2, r2, #0      ; i = 0

Loop_Start              ; while (true) {
    add r6, r1, r2      ;     if (*(base + i) == NUL)
    ldr r6, r6, 0x0     ;
    brz Loop_End        ;         break

    add r6, r2, #0      ;     if (i > 0)
    brnz Delim_End      ;
    lea r0, Delim       ;         print(Delim)
    puts                ;
    Delim_End           ;

    add r0, r1, r2      ; print(base + i)
    puts                ;

    add r2, r2, 0x8     ;     i += 8

    br Loop_Start       ; }
Loop_End

    halt

Delim .STRINGZ ", "

Words  ; Each [word + null block] takes up 8 WORDS
    .STRINGZ "this"
    .BLKW #3
    .STRINGZ "is"
    .BLKW #5
    .STRINGZ "some"
    .BLKW #3
    .STRINGZ "words"
    .BLKW #2
    .STRINGZ "in"
    .BLKW #5
    .STRINGZ "array"
    .BLKW #2
    .FILL 0x0000 ; Equivalent to an empty null-terminated string

.END
