\ ______________________________________________________________________ 
\
.( v-Forth 1.52 NextZXOS version ) CR
.( build 20220508 ) CR
.( Direct Threaded - NextZXOS version ) CR
\ ______________________________________________________________________ 
\
\ This work is available as-is with no whatsoever warranty.
\ Copying, modifying and distributing this software is allowed 
\ provided that the copyright notice is kept.  
\ ______________________________________________________________________ 
\
\ by Matteo Vitturi, 1990-2022
\
\ https://sites.google.com/view/vforth/vforth15-next
\ https://www.oocities.org/matteo_vitturi/english/index.htm
\  
\ This is the complete compiler for v.Forth for SINCLAIR ZX Spectrum Next.
\ Each line of this source list mustn't exceed 510 bytes.
\ Z80N (ZX Spectrum Next) extension is available.
\
\ This list has been tested using the following configuration:
\     - CSpect emulator V.2.12.36
\
\ There are a few modifications to keep in mind since previous v. 1.2
\  '      (tick) returns CFA, instead of PFA as previously was
\  -FIND         returns CFA, instead of PFA as previously was
\  SP!           must be passed with the address to initialize SP register
\  RP!           must be passed with the address to initialize RP.
\  WORD          now returns address HERE: a few blocks must be corrected
\  CREATE        now creates a definition that returns its PFA.
\ ______________________________________________________________________
\
\ Z80 Registers usage map
\
\ AF 
\ BC - Instruction Pointer: it must be preserved during ROM/OS calls
\ DE -         (Low  word when used for 32-bit manipulations)
\ HL - Working (High word when used for 32-bit manipulations)
\
\ AF'- Sometime used for backup purpose
\ BC'- Sometime used in tricky definitions
\ DE'- Sometime used in tricky definitions
\ HL'- Sometime used in tricky definitions
\
\ SP - Calc Stack Pointer
\ IX - Inner interpreter next-address pointer. This is 2T-state faster than JP
\      it must be preserved during ROM/OS calls
\ IY - (ZX System: must be preserved)

\ From this version vForth is a "direct-thread" instead of an "indirect-thread" 
\ Forth system. It brings a +25% speed improvement. 
\ Any Low-Level definition saves two bytes, but any non Low-Level definitions 
\ needs one additional byte because CFA does not contain an address anymore, 
\ instead CFA contains the real machine-code to be executed. 
\ For non Low-level definitions CFA is a three byte instruction "CALL aaaa" to 
\ the ;CODE part routine that handles that kind of definition.
\
\ ______________________________________________________________________

\ _________________
\
  FORTH DEFINITIONS
\ _________________

NEEDS RENAME
NEEDS VALUE
NEEDS TO
NEEDS ASSEMBLER

CASEON      \ we must be in Case-sensitive option to compile this file.
0 WARNING ! \ avoid verbose messaging

\ The following word makes dynamic the location of "Origin", so that we can
\ compile this Forth *twice* to rebuild it completely in itself.
\ At second run, it forces DP to re-start at a lower-address such as the 
\ following. (N.B. an open microdrive channel requires 627 bytes)
HEX
: SET-DP-TO-ORG
    0 +ORIGIN 08000 U< 0=
    IF
        \ 6100 \ 24832 \ = origin of v1.2. it allows 1 microdrive channel
        \ 6400 \ 25600 \ = origin of v1.413. it allows 2 microdrive channels
          6363 \ 25443 \ = origin of v1.5. Allow 64 bytes of OS-call stack.
        \ 6500 \ 25856 \ = plus another 256 page to host TIB/RP/User vars.
        \ 6A00 \ 27136 \ = room for 3 buffers below ORIGIN
        \ 8000 \ 32768 \ = final
        DP !
    THEN
    ;


\ _________________
\
.( Key & Emit table-pointer )
\ This table is used later to insert a value in a conversion table for EMIT 
\ that is a two areas table, EMIT-A are vector of address and EMIT-C are 
\ characters. If you scan EMIT-C for a matching character you can get an 
\ address to be used as a conversion subroutine 
DECIMAL
     8  CONSTANT  EMIT-N   \ EMIT table length
     0  VALUE     EMIT-C^  \ char table
     0  VALUE     EMIT-A^  \ addr table
     0  VALUE     EMIT-2^  \ comodo
     0  VALUE     KEY-1^   \ KEY decode table
     0  VALUE     KEY-2^

\ \ this gives the "end" of EMIT-table
\ : EMIT-Z^
\    EMIT-C^ EMIT-N + 1 -
\    ;

\
.( Forward Pointers )
\ These __ forward __ pointers are used to keep track of things we are compiling
\
     0  VALUE     org^          \ ptr to origin of Forth
     0  VALUE     cold^         \ ptr to cold start routine
     0  VALUE     warm^         \ ptr to warm start routine
     0  VALUE     vars^         \ ptr to user's vars ptr
     0  VALUE     rp^           \ ptr to RP register
     0  VALUE     next^         \ ptr to NEXT in inner interpreter
     0  VALUE     exec^         \ ptr to exec xt
     0  VALUE     branch^       \ PFA of BRANCH
     0  VALUE     branch^^      \ ptr to be patched with PFA of BRANCH
     0  VALUE     loop^         \ entry-point for compiled (+LOOP)
     0  VALUE     do^           \ entry-point for compiled (DO)
     0  VALUE     emitc^        \ entry-point for EMITC
     0  VALUE     upper^        \ entry-point for UPPER

\ some pointers are used to patch words later... 
\ Since we need to define a word using "forward" definitions 
\ we simply use the previous definitions with the promise
\ we'll patch the just created word using the forward definitions
\ as soon as we have them available (later during the compilation)
     0  VALUE     lit~          \ some CFA
        \ at the *end*, zero has to be put at   lit~ - 2 
        \ to cut-off older dictionary :       0 lit~   2  -  !
     0  VALUE     branch~       \ CFA of BRANCH
     0  VALUE     0branch~      \ CFA of 0BRANCH
     0  VALUE     (loop)~       \ CFA of (LOOP)
     0  VALUE     (do)~         \ CFA of (DO)
     0  VALUE     (?do)~        \ CFA of (?DO)
     0  VALUE     msg1^         \ patch of ERROR
     0  VALUE     msg2^         \ patch of CODE/MCOD (CREATE)
     0  VALUE     enter^        \ resolved within : definition.
     0  VALUE     error^        \ patch of ?ERROR with ERROR
     0  VALUE     asm^          \ patch of ;CODE with ASSEMBLER
     0  VALUE     block^        \ patch of WORD with BLOCK
     0  VALUE     block2^       \ patch of WORD with (LINE)
     0  VALUE     quit^         \ patch of ERROR with QUIT
     0  VALUE     abort^        \ patch of (ABORT)
   \ 0  VALUE     xi/o^         \ patch of XI/O and WARM in COLD
     0  VALUE     xi/o2^        \ patch of BLK-INIT in WARM 
     0  VALUE     y^            \ patch of COLD/WARM start
     0  VALUE     splash^       \ patch of SPLASH in WARM
     0  VALUE     autoexec^     \ patch of NOOP in ABORT
     0  VALUE     .^            \ patch of .    in MESSAGE

.( Psh2 Psh1 Next )

\ compile CODE words for Jump to the Psh2, Psh1 or Next addresses.
\ : Psh2     ASSEMBLER  JP next^  2-   AA, ;
\ : Psh1     ASSEMBLER  JP next^  1-   AA, ;
\ : Next     ASSEMBLER  JP next^       AA, ;

: Psh2     ASSEMBLER  PUSH DE|   PUSH HL|   JPIX ;
: Psh1     ASSEMBLER             PUSH HL|   JPIX ;
: Next     ASSEMBLER                        JPIX ;

\ macro of "RP" virtual register emulation
: LDHL,RP  ASSEMBLER  LDHL()     rp^      AA, ;
: LDRP,HL  ASSEMBLER  LD()HL     rp^      AA, ;
: LDSP,RP  ASSEMBLER  LDX() SP|  rp^      AA, ;
: LDRP,SP  ASSEMBLER  LD()X SP|  rp^      AA, ;

\ at the end, we need to patch every reference to RP-address.
\ we ALLOT some area to keep track of them whenever we need.
     0  VARIABLE rp# DECIMAL 42 ALLOT    0  rp# !
    rp# VARIABLE rp#^                  rp# rp#^ !
    rp# DECIMAL 44 ERASE

\ accumulate pointers to be patched at the end using final_rp_patch
: !rp^ ( address -- )
    1+
    rp#^ @ !
    2 rp#^ +!
    ;

 
\ ______________________________________________________________________
\
\  These words are immediate words used to compile forward definitions 
\  relying on some pointers defined above.
\  We use a peculiar notation with First Capital Letter.
\  At the end of this listing, there is an all-lowercase version.
\ _________________

.( LITERAL , DLITERAL )
\
: Literal   ( n -- )
    STATE @
    IF
        \ COMPILE LIT ,
        lit~ , ,
    THEN
    ; 
    IMMEDIATE

: Dliteral   ( d -- )
    STATE @
    IF
        SWAP
        [COMPILE] Literal
        [COMPILE] Literal
    THEN
    ; 
    IMMEDIATE
    
.( IF ... THEN )
.( IF ... ELSE ... THEN )
\ 
: If    (   -- a 2 ) \ compile-time
        ( f --     ) \ run-time   
    ?COMP 
    0branch~ ,     \ COMPILE 0BRANCH
    HERE 0 , 
    2 
    ; 
    IMMEDIATE
    
: Then ( a 2 -- ) \ compile-time
        (     -- ) \ run-time    
    ?COMP
    2 ?PAIRS  
    HERE OVER - SWAP ! 
    ; 
    IMMEDIATE
    
\ : Endif ( a 2 -- ) \ compile-time 
\        (     -- )  \ run-time
\     [COMPILE] Then 
\     ; 
\     IMMEDIATE

: Else ( a1 2 -- a2 2 ) \ compile-time    
       (      --      ) \ run-time
    ?COMP
    2 ?PAIRS  
    branch~ ,  \ COMPILE BRANCH
    HERE 0 , 
    SWAP 2 [COMPILE] Then \ Then
    2 
    ; 
    IMMEDIATE

.( Loops structure words )
\ BEGIN ...   AGAIN
\ BEGIN ... f UNTIL
\ BEGIN ... f WHILE ... REPEAT
\ 
: Begin     ( -- a 1 ) \ compile-time  
            ( --     ) \ run-time
    ?COMP 
    HERE 
    1 
    ; 
    IMMEDIATE
    
: Again     ( a 1 -- ) \ compile-time
            (     -- ) \ run-time
    ?COMP
    1 ?PAIRS 
    branch~ , \ COMPILE BRANCH
    BACK 
    ; 
    IMMEDIATE
    
: Until     ( a 1 -- ) \ compile-time
            (   f -- ) \ run-time
    ?COMP
    1 ?PAIRS
    0branch~ , \ COMPILE 0BRANCH
    BACK 
    ; 
    IMMEDIATE
    
: While     ( a1 1 -- a1 1 a2 4 ) \ compile-time
            (    f -- ) \ run-time
    [COMPILE] If 2+
    ; 
    IMMEDIATE
    
: Repeat    ( a1 1 a2 4 -- ) \ compile-time
            (           -- ) \ run-time
    2SWAP
    [COMPILE] Again
    2- 
    [COMPILE] Then \ Then
    ; 
    IMMEDIATE


.( DO ... LOOP )
\
: Do        (     -- a 3 ) \ compile-time
            ( n m --     ) \ run-time
    ?COMP 
    (do)~ ,
    CSP @ !CSP
    HERE 3
    ; 
    IMMEDIATE

: Loop      ( a 3 -- ) \ compile-time    
            (     -- ) \ run-time
    3 ?PAIRS 
    ?COMP 
    (loop)~ , 
    ?DO-
    ; 
    IMMEDIATE

: ?Do       (     -- a 3 ) \ compile-time
            ( n m --     ) \ run-time
    ?COMP 
    (?do)~ ,
    CSP @ !CSP
    HERE 0 , 0
    HERE 3
    ; 
    IMMEDIATE



\ ______________________________________________________________________
\ \ 
\ HERE     U.
\ HERE HEX U. 
\ KEY  DROP

\ force origin to an even address?
\ HERE 1 AND ALLOT
SET-DP-TO-ORG

\
\ ______________________________________________________________________
\

\ Interrupt vector 6363
       ASSEMBLER
       JP HEX 0038 AA,      \ 6363h
                            \ 6366h
\
.( Origin )
\
\ ______________________________________________________________________

     
HERE TO org^
\ 6100h or 6366h or 8000h depending on which version is compiling
\ this addresses simply are a "remind" for myself.

\ +000
        ASSEMBLER

        ANDA     A|
        JP       HERE TO cold^
                 HEX 7530  AA,

        SCF
        JP       HERE TO warm^
                 HEX 7530  AA,

\ +008
                 HEX 0101    ,  \ saved Basic SP
\ +00A                    
                 HEX 0E00    ,  \ ?

\ 610Ch
\ +00C
                 0           ,  \ LATEST word used in COLD start

\ +00E
                 HEX 000C    ,  \ "DEL" character

\ +010
                 DECIMAL 36 BASE ! Z80 , DECIMAL

\ start of data for COLD start
\ +012
       S0 @ ,  \ HEX EA40    ,  \ S0 
\ +014
       R0 @ ,  \ HEX EAE0    ,  \ R0
\ +016
       TIB @ , \ HEX EA40    ,  \ TIB
\ +018
                 DECIMAL 31  ,  \ WIDTH
\ +01A
                 1           ,  \ WARNING
\ +01C
                 0           ,  \ FENCE
\ +01E
                 0           ,  \ DP
\ +020
                 0           ,  \ VOC-LINK
\ +022
                 FIRST @     , 
\ +024
                 LIMIT @     ,
\ end of data for COLD start

\ +026
                 HEX 8F C, 8C C,    \ Cursor faces used by KEY
\ +028
                 HEX 5F C, 00 C,    \ Used by KEY
\ +02A   ( Echoed IX after NextZXOS call )
                 0           ,
\ +02C   ( Saved SP during NextZXOS call )
                 0           ,
\ +02E   (User Variable Pointer)
HERE TO vars^       R0 @ ,       \ HEX EAE0    ,


\ +030  (Return Stack Pointer)
HEX 030 +ORIGIN TO rp^     
 
       R0 @ , \ 2  - \ was HEX EADE    ,  


 
\ from this point we can use LDHL,RP and LDRP,HL Assembler macros
\ instead of their equivalent long sequences.


\ 6126h
\ hook for Psh2

        ASSEMBLER
\       PUSH    DE|   no more used since we use JP (IX)

\ 6127h
\ hook for Psh1
         
\       PUSH    HL|   no more used since we use JP (IX)

\ 6128h
\ hook for Next - inner interpreter
    HERE TO next^ 
         
        LDA(X)  BC|
        INCX    BC|
        LD      L'|    A|
        LDA(X)  BC|
        INCX    BC|
        LD      H'|    A|


\ 612Eh
\ Execute "xt" i.e. CFA held in HL
    HERE TO exec^





        JPHL


\ 6133h 
.( LIT )
\ puts on top of stack the value of the next location. 
\ it is compiled in colon definition before a literal number
CODE lit ( -- n )
         
        LDA(X)  BC|
        INCX    BC|
        LD      L'|    A|
        LDA(X)  BC|
        INCX    BC|
        LD      H'|    A|
        PUSH    HL|
        Next
        C;

        ' lit TO lit~


\ 6144h
.( EXECUTE )
\ execution token. usually xt is given by CFA
CODE execute ( xt -- )
         
        RET
\     \ JP      exec^  AA,
\       JR      exec^  HERE 1 + - D,

\ in general, we use JR within the same definition, JP to go beyond.
\ but it can be useful using JR in some closest words to save a few bytes
        C;


\ 6181h
." (+LOOP) "
\ compiled by +LOOP. it uses the top two values of return-stack to
\ keep track of index and limit, they are accessed via I and I'
CODE (+loop) ( n -- )

    HERE TO loop^
    
        EXX

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin
        
        POP     BC|         \ BC is increment
        
        LD      E'| (HL)|   \ DE keeps index before increment
        LD      A'|    E|   \ index is incremented in memory.
        ADDA     C|
        LD   (HL)'|    A|
        INCX    HL|
        LD      D'| (HL)|
        LD      A'|    D|
        ADCA     B|
        LD   (HL)'|    A|
        INCX    HL|

        LD      A'|    E|
        SUBA  (HL)|   
        LD      E'|    A|
        INCX    HL|
        LD      A'|    D|
        SBCA  (HL)|   
        LD      D'|    A|   \ DE is index - limit : limit is the "new zero"

        EXDEHL  
        ADDHL   BC|         \ HL is index - limit + increment
        BIT      7|    B|    \ doesn't affect carry flag
        JRF     Z'|    HOLDPLACE \ if increment is negative then
            CCF                  \ complement carry flag
        HERE DISP, \ THEN,
        JRF    CY'|    HOLDPLACE
            \ stay in loop, increment index
            EXX
            JR      HERE  TO  branch^^    26  D,
          \  JP         branch^  AA,
        HERE DISP, \ THEN,

        EXDEHL  
        INCX    HL|

        HERE !rp^
        LDRP,HL              \ macro 30h +Origin

        EXX
        INCX    BC|
        INCX    BC|
        Next
        C;


\ 61BAh
." (LOOP) "
\ same as (+LOOP) but index is incremented by 1 
CODE (loop)    ( -- )
         
        PUSHN   1  LH,
      \ JP      loop^  AA,
        JR      loop^  HERE 1 + - D,
        C;

        ' (loop) TO (loop)~


\ 6153h
.( BRANCH )
\ unconditional branch in colon definition
\ compiled by ELSE, AGAIN and some other immediate words
CODE branch ( -- )
\ 615E
         
    HERE TO branch^
    
        LD      H'|    B|
        LD      L'|    C|
        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        DECX    HL|
        ADDHL   DE|
        LD      C'|    L|
        LD      B'|    H|
        Next
        C;
        
        ' branch TO branch~

        branch^  branch^^  1+ -  branch^^ C!


\ 616Ah
.( 0BRANCH )
\ conditional branch if the top-of-stack is zero.
\ compiled by IF, UNTIL and some other immediate words
CODE 0branch ( f -- )
         
        POP     HL|
        LD      A'|    L|
        ORA      H|
      \ JPF      Z|    branch^  AA,
        JRF     Z'|    branch^  HERE 1 + - D,
        INCX    BC|
        INCX    BC|
        Next
        C;
        
        ' 0branch TO 0branch~


CODE (leave) ( -- )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin
        
        LDX     DE|  4  NN,  \ UNLOOP index & limit from Return Stack      
        ADDHL   DE|

        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
      \ JP      branch^  AA, \ jump out of loop
        JR      branch^  HERE 1 + - D,
        Next
        C;       


\ new
." (?DO) "
\ compiled by ?DO to make a loop checking for lim == ind first
\ at run-time (?DO) must be followed by a BRANCH offset
\ used to skip the loop if lim == ind
CODE (?do)      ( lim ind -- )
         
        \ copy lim to HL and ind to DE.
        POP     DE|        \ ind
        POP     HL|        \ lim
        PUSH    HL|
        PUSH    DE|
        ANDA     A|
        SBCHL   DE|        \  lim - ind
        JRF    NZ'| HOLDPLACE \ if lim == ind
            POP     DE|
            POP     HL|
          \ JP      branch^  AA,
            JR      branch^  HERE 1 + - D,
        HERE DISP, \ THEN,
        
    HERE TO do^

        \ prepares return-stack-pointer
        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        DECX    HL|          \ this is 1T faster than
        DECX    HL|          \ ld de,-4 (10T)
        DECX    HL|          \ add hl,de (15T)
        DECX    HL|          \ since dec hl is 6T.
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        \ stores ind as top RP
        POP     DE|
        LD   (HL)'|    E|
        INCX    HL|
        LD   (HL)'|    D|
        INCX    HL|
        \ stores lim as second 
        POP     DE|
        LD   (HL)'|    E|
        INCX    HL|
        LD   (HL)'|    D|
        
        \ skips 0branch offset 
        INCX    BC|
        INCX    BC|
        Next
        C;

        ' (?do) TO (?do)~


\ 61CAh
." (DO) "
\ compiled by DO to make a loop checking for lim == ind first
\ this is a simpler version of (?DO)
CODE (do) ( lim ind -- )
         
        DECX    BC|     \ balance the two INC BC at end of (?DO)
        DECX    BC|
      \ JP      do^  AA,
        JR      do^  HERE 1 +  - D, 
        C;

        ' (do) TO (do)~


\ 61E9h
.( I )
\ used between DO and LOOP or between DO e +LOOP to copy on top of stack
\ the current value of the index-loop
CODE i ( -- ind )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin
HERE
        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        PUSH    DE|
        Next
        C;


.( I' )
\ used between DO and LOOP or between DO e +LOOP to copy on top of stack
\ the limit of the index-loop
CODE i' ( -- lim )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin
        INCX    HL|
        INCX    HL|
        JR      BACK,        \ jump to "HERE" on I 
        C;


\ 61F9h
.( DIGIT )
\ convert a character c using base n
\ returns a unsigned number and a true flag 
\ or just a false flag if the conversion fails
CODE digit ( c n -- u 1  |  0 )
         
        POP     HL|            \ base
        POP     DE|            \ char
        LD      A'|    E|
        
        CPN     HEX 60 N,      \ if lowercase
        JRF    CY'| HOLDPLACE
            SUBN HEX 20 N,     \ quick'n'dirty uppercase
        HERE DISP, \ THEN, 
        
        SUBN     HEX 30 N,
        JRF    CY'|  HOLDPLACE    \ good when greater than 30
            CPN      HEX 0A N,
            JRF    CY'| HOLDPLACE \ if >= 10 try to subtract 7
                SUBN    7 N,       
                CPN     HEX 0A N,  \ fail if now it is < 10 
                JRF    CY'| HOLDPLACE  SWAP \  hide this holdplace... (!!)
            HERE DISP, \ THEN,
            CPA      L|        \ compare with base
            JRF    NC'| HOLDPLACE \ if less than base, good
                LD      E'|    A|
                LDX     HL|    1 NN,
                PUSH    DE|
                PUSH    HL|
                Next

            HERE DISP, \ THEN,
        HERE DISP, HERE DISP, \ THEN, THEN, \ ... (!!) 
        LDX     HL| 0 NN,
        PUSH    HL|
        Next
        C;


\ uppercase routine
\ character in A is forced to Uppercase.
\ no other register is altered
    ASSEMBLER
    HERE TO upper^
        RET                 \ This location is patched
                            \ at runtime by CASEON and CASEOFF
        CPN     HEX 61 N,   \ lower-case "a"
        RETF    CY|
        CPN     HEX 7B N,   \ lower-case "z" + 1
        RETF    NC|
        SUBN    HEX 20 N,   \ substract 20h if lowercase [a-z]
        RET


.( CASEON )
\ set case-sensitivity on
\ it patches a RET at the beginning of the uppercase-routine
CODE caseon
        LDN     A'|  HEX C9 N,   \ patch for RET at upper^ location
        LD()A   upper^ AA,    
        Next
        C;


.( CASEOFF )
\ set case-sensitivity off
\ it patches a NOP at the beginning of the uppercase-routine
CODE caseoff
        LDN     A'|  HEX 00 N,   \ patch for NOP at upper^ location
        LD()A   upper^ AA,    
        Next
        C;


.( UPPER )
\ character on top of stack is forced to Uppercase.
CODE upper ( c1 -- c2 )
        POP     HL|            \ char
        LD      A'|    L|
        CALL    upper^  1+  AA,
        LD      L'|    A|
        PUSH    HL|
        Next
        C;


\ 6228h
." (FIND) "
\ vocabulary search, 
\ - voc is starting word's NFA
\ - addr is the string to be searched for
\ On success, it returns the CFA of found word, the first NFA byte
\ (which contains length and some flags) and a true flag.
\ On fail, a false flag  (no more: leaves addr unchanged)
CODE (find) ( addr voc -- addr 0 | cfa b 1  )
         
        POP     DE|        \ dictionary
        HERE
            POP     HL|    \ text to search
            PUSH    HL|
            LDA(X)  DE|    \ save NFA length byte 
            EXAFAF         \ for later use  (!)      
            LDA(X)  DE|
            XORA  (HL)|
            ANDN    HEX 3F N,
            JRF    NZ'| HOLDPLACE \ if same length then

                HERE  \ BEGIN,
                    INCX    HL|
                    INCX    DE|
                    LDA(X)  DE|

\ case   sensitive option  
\                   XORA  (HL)|

\ case insensitive option  
                    PUSH    BC|
                    ANDN    HEX 80 N,   \ split A in msb and the rest.
                    LD      B'|      A| \ store msb in B and the rest in C
                    LDA(X)  DE|
                    ANDN    HEX 7F N,
                    CALL    upper^ AA,  \ uppercase routine
                    LD      C'|      A|  
                    LD      A'|   (HL)|
                    CALL    upper^ AA,  \ uppercase routine
                    XORA     C|         
                    XORA     B|         
                    POP     BC|
\ case option - end

                    ADDA     A|         \ ignore msb in compare
                    JRF    NZ'| HOLDPLACE SWAP \ didn't match, jump (*)

                JRF    NC'| HOLDPLACE SWAP DISP, 
                \ loop until last byte msb is found set 
                \ that bit marks the ending char of this word

                \ match found!
                \   LDX     HL|    5 NN,  \ 5 for PFA (was before)
                    LDX     HL|    3 NN,  \ 3 for CFA
                    ADDHL   DE|
                    EX(SP)HL
                    EXAFAF                \ retrieve NFA byte (!)
                    LD      E'|    A|
                    LDN     D'|    0 N,
                    LDX     HL|    1 NN,
                    PUSH    DE|
                    PUSH    HL|
                    Next

                HERE DISP, \ THEN,  \ didn't match (*)
                JRF    CY'| HOLDPLACE SWAP \ not the end of word, jump (**) 

            HERE DISP, \ THEN, 

            HERE \ BEGIN, \ find LFA
                INCX    DE| 
                LDA(X)  DE|
                ADDA     A|
            JRF    NC'|  HOLDPLACE SWAP DISP, 
            \ loop until last byte msb is set 
            \ consume chars until the end of the word
            
            HERE DISP, \ THEN,     \ (**)

            \ take LFA and use it
            INCX    DE|
            EXDEHL
            LD      E'| (HL)|
            INCX    HL|
            LD      D'| (HL)|
            
            LD      A'|    D|
            ORA      E|
        JRF    NZ'|  HOLDPLACE SWAP DISP,
        \ loop until end of vocabulary 

        POP     HL|         \ with this, it leaves addr unchanged

        LDX     HL| 0 NN,
        PUSH    HL|
        Next
        C;


\ 6276h
.( ENCLOSE )
\ starting from a, using delimiter c, determines the offsets:
\   n1   the first character non-delimiter
\   n2   the first delimiter after the text 
\   n3   the first character non enclosed.
\ This procedure does not go beyond a 'nul' ASCII (0x00) that represents
\ an uncoditional delimiter. 
\ Examples:
\   i:	c  c  x  x  x  c  x	 -- 2  5  6
\  ii:	c  c  x  x  x  'nul' -- 2  5  5
\ iii:	c  c  'nul'          -- 2  3  2
CODE enclose    ( a c -- a  n1 n2 n3 )
HEX         
        POP     DE| ( char )        
        POP     HL| ( addr )
        PUSH    HL|
        LD      A'|      E| 

        LDX     DE|    HEX FFFF NN,
        DECX    HL|
        HERE \ BEGIN, 
            INCX    HL|
            INCX    DE|
            CPA   (HL)|
        JRF     Z'|  HOLDPLACE SWAP DISP, ( 1st non-delimiter )
        \ UNTIL,

        PUSH    DE|

        PUSH    BC|                \ save BC

        LD      C'|      A|        \ save  a ( char )

        LD      A'|   (HL)|
        ANDA     A|             ( stops if null )
        JRF    NZ'| HOLDPLACE ( iii. no more character in string )
            POP     BC|         \ retrieve BC
            INCX    DE|
            PUSH    DE|
            DECX    DE|
            PUSH    DE|
            Next
        HERE DISP, \ THEN,
        HERE  \ BEGIN, 
            LD      A'|      C|     
            INCX    HL|
            INCX    DE|
            CPA   (HL)|

            JRF    NZ'| HOLDPLACE  ( separator )
                POP     BC|         \ retrieve BC
                PUSH    DE|         ( i. first non enclosed )
                INCX    DE|
                PUSH    DE|
                Next
            HERE DISP, \ THEN,
            LD      A'| (HL)|
            ANDA     A|
        JRF    NZ'| HOLDPLACE SWAP DISP,
                                   ( ii. separator & terminator )
        POP     BC|         \ retrieve BC
        PUSH    DE|
        PUSH    DE|
        Next
        C;


." (MAP) "
\ translate character c1 using mapping string a2 and a2
\ if c1 is not present within string a1 then 
\ c2 = c2 if it is not translated. n is the length of both a1 and a2.
CODE (map) ( a2 a1 n c1 -- c2 )
        EXX
        POP     HL|
        LD      A'|    L|
        POP     BC|
        POP     HL|
        LD      D'|    B|
        LD      E'|    C|
        CPIR 
        POP     HL|
        JRF    NZ'| HOLDPLACE
            ADDHL   DE|
            DECX    HL|
            SBCHL   BC|
            LD      A'| (HL)|
        HERE DISP,
        LD      L'|    A|
        LDN     H'|  HEX 00 N,
        PUSH    HL|
        EXX
        Next
        C;


." (COMPARE) "
\ this word performs a lexicographic compare of n bytes of text at address a1 
\ with n bytes of text at address a2. It returns numeric a value: 
\  0 : if strings are equal
\ +1 : if string at a1 greater than string at a2 
\ -1 : if string at a1 less than string at a2 
\ strings can be 256 bytes in length at most.
CODE (compare) ( a1 a2 n -- b )
        EXX
        POP     HL| 
        LD      A'|    L|
        POP     HL|         \ string a2
        POP     DE|         \ string a1
        \ PUSH    BC|
        LD      B'|    A|
        HERE                \ begin
\           LDA(X)  DE| 
\           CPA   (HL)|
            LD      A'|   (HL)|
            CALL    upper^ AA,  \ uppercase routine
            LD      C'|      A|
            LDA(X)  DE|
            CALL    upper^ AA,  \ uppercase routine
            CPA      C|         \ compare both uppercased chars
            INCX    DE| 
            INCX    HL|
            JRF Z'| HOLDPLACE   \ match
                JRF CY'| HOLDPLACE
                      LDX   HL|     1   NN,
                JR   HOLDPLACE  SWAP HERE DISP, \ ELSE,
                      LDX   HL|    -1   NN,
                HERE DISP, \ THEN,
                PUSH    HL|
                EXX  \ POP     BC| 
                Next

            HERE DISP, \ THEN,

        DJNZ BACK,          \ until
        LDX     HL|     0   NN,
        PUSH    HL|
        EXX  \ POP     BC| 
        Next
        C; 


\ 62BDh 
.( EMITC )
\ low level emit, calls ROM routine at #10 to send a character to 
\ the the current channel (see SELECT to change stream-channel)
CODE emitc     ( c -- )
        POP     HL|
        LD      A'|    L|
    HERE TO emitc^    
        PUSH    BC|
        PUSH    IX|
        RST     10|             \ standard ROM current-channel print routine
        POP     IX|
        POP     BC|
        LDN     A'|  HEX FF N,
        LD()A   HEX 5C8C AA,    \ SCR-CT system variable
        Next
        C;


\ 6396h
.( CR )
\ sends a CR via EMITC.
CODE cr  ( -- )
         
        LDN     A'|     HEX 0D N,
        JR      emitc^  HERE 1 +  - D, 
        C;


\ conversion table for (?EMIT)
HERE TO EMIT-A^   
EMIT-N  EMIT-N +  ALLOT
HERE TO EMIT-C^   
HEX 06 C, \ comma
HEX 07 C, \ bel
HEX 08 C, \ bs
HEX 09 C, \ tab
HEX 0D C, \ cr --> cr
HEX 0A C, \ lf Unix newline
HEX 20 C, \ not used
HEX 20 C, \ not used


\ new
." (?EMIT) " ( ++BC++ possible improvement )
\ it decodes a character to be sent via EMIT
\ search first the EMIT-C^ table, if found jump to the routine in vector
\ the routine should resolve anything and convert the character anyway.
CODE (?emit) ( c1 -- c2 )
         
        POP     DE|
        LD      A'|    E|
        ANDN    HEX    7F N,  \ 7-bit ascii only
        PUSH    BC|            \ saves program counter
        LDX     BC|  EMIT-N  NN,
        LDX     HL|  EMIT-C^ EMIT-N + 1- NN, \ EMIT-Z^
        CPDR    \ search for c1 in EMIT-C table, backward
        
        JRF    NZ'|  HOLDPLACE    \ Found, decode it
            LDX     HL|   EMIT-A^ NN,
            ADDHL   BC|
            ADDHL   BC|
            LD      E'| (HL)|
            INCX    HL|
            LD      D'| (HL)|
            EXDEHL

            POP     BC| \ restore program-counter
            JPHL        \ jump to decoder-routine
                        \ routine must end with Psh1
                        \ that is the chraracter decoded
                        \ or zero to signal a false-flag
        HERE DISP, \ THEN,   
        POP     BC|     \ restore program-counter

        CPN     HEX 20 N,     
        JRF    NC'|     HOLDPLACE  \ non printable control character
            LDN     A'|    0 N,
        HERE DISP, \ THEN,   

    HERE TO EMIT-2^
        LD      L'|    A|
        LDN     H'| 0 N,
        PUSH    HL|
        Next
        C;

\ 06 comma-tab 
EMIT-2^ EMIT-A^ 00 +  ! 

\ 07 bel 
HERE    EMIT-A^ 02 +  ! 
        ASSEMBLER 
        PUSH    BC|
        LDX     DE| HEX 0100 NN,
        LDX     HL| HEX 0200 NN,
        PUSH    IX|
        CALL    HEX 03B6 AA,       \ bleep routine without "Disable Interrupt"
        POP     IX|
        POP     BC|
        LDX     HL| 0 NN,          \ don't print anything
        PUSH    HL|
        Next
\       C;

\ 08 tab        
EMIT-2^ EMIT-A^ 04 +  ! 

\ 09 tab        
HERE    EMIT-A^ 06 +  ! 
        ASSEMBLER 
        LDX     HL| 6 NN,
        PUSH    HL|
        Next
\       C;

\ 0D cr        
EMIT-2^ EMIT-A^ 08 +  !

\ 0A nl --> cr
HERE    EMIT-A^ 0A +  ! 
        ASSEMBLER 
        LDX     HL| 0D NN,
        PUSH    HL|
        Next
\       C;

EMIT-2^ EMIT-A^ 0C +  !
EMIT-2^ EMIT-A^ 0E +  !


\ new 
\ BLEEP
\ CODE bleep  ( n1 n2 -- )
\ ( n1 = dur * freq )
\ ( n2 = 437500/freq -30.125 )
\          
\         POP     HL|
\         POP     DE|
\         PUSH    BC|
\         CALL    HEX 03B5 AA,
\         POP     BC|
\         Next
\         C;


\ KEY decode table
HEX 
HERE TO KEY-1^
    E2   C,   \  0: STOP  --> SYMBOL+A : ~
    C3   C,   \  1: NOT   --> SYMBOL+S : |
    CD   C,   \  2: STEP  --> SYMBOl+D : \
    CC   C,   \  3: TO    --> SYMBOL+F : {
    CB   C,   \  4: THEN  --> SYMBOL+G : }
    C6   C,   \  5: AND   --> SYMBOL+Y : [
    C5   C,   \  6: OR    --> SYMBOL+U : ]
    AC   C,   \  7: AT    --> SYMBOL+I : (C) copyright symbol
    C7   C,   \  8: <=    --> SYMBOL+Q : same as SHIFT-1 [EDIT]
    C8   C,   \  9: >=    --> SYMBOL+E : same as SHIFT-0 [BACKSPACE]
    C9   C,   \ 10: <>    --> SYMBOL+W is the same as CAPS (toggle) SHIFT+2 
\ _________________

HERE TO KEY-2^  \ same table in reverse order, sorry, I am lazy
    06   C,   \ 10: SYMBOL+W is the same as CAPS (toggle) SHIFT+2 
    0C   C,   \  9: SYMBOL+E : same as SHIFT-0 [BACKSPACE]
    07   C,   \  8: SYMBOL+Q : same as SHIFT-1 [EDIT]
    7F   C,   \  7: SYMBOL+I : (C) copyright symbol
    5D   C,   \  6: SYMBOL+U : ]
    5B   C,   \  5: SYMBOL+Y : [
    7D   C,   \  4: SYMBOL+G : }
    7B   C,   \  3: SYMBOL+F : {
    5C   C,   \  2: SYMBOl+D : \
    7C   C,   \  1: SYMBOL+S : |
    7E   C,   \  0: SYMBOL+A : ~


\ new
.( KEY )
\ display a flashing cursor then
\ reads one character from keyboard stream and leaves it on stack
CODE key ( -- c )
         
        PUSH    BC|
        PUSH    IX|

        LD()X   SP|    HEX 02C org^ +  AA, \ saves SP
        LDX     SP|    HEX  -5 org^ +  NN, \ temp stack just below ORIGIN

        RES      5| (IY+ 1 )|
        HERE  \ BEGIN, 

            HALT

            LDN     A'| HEX 02 N,   \ select channel #2
            CALL    HEX 1601 AA,

            \ software-flash: flips face every 320 ms
            LDN     A'| HEX 10 N,             \ Timing  
            ANDA    (IY+ HEX 3E )|            \ FRAMES (5C3A+3E)

\           LDN     A'| HEX 8F N,             \ block character
            LDA()   HEX 026 org^ +   AA,
            JRF    NZ'| HOLDPLACE \ IF,
\               LDN     A'| HEX 88 N,         \ lower-half-block character
                LDA()   HEX 027 org^ +   AA,
                BIT      3| (IY+ HEX 30 )|    \ FLAGS2 (5C3A+30)                
                JRF     Z'| HOLDPLACE \ IF,
\                   LDN     A'| 5F N,         \ upper-half-block character 
                    LDA()   HEX 028 org^ +   AA,
                HERE DISP, \ THEN, 
            HERE DISP, \ THEN, 

            RST     10|
            LDN     A'| HEX 08 N,   \ backspace
            RST     10|

            BIT      5| (IY+ 1 )|         \ FLAGS (5C3A+1)
        JRF     Z'| HOLDPLACE SWAP DISP,  \ UNTIL, 

        HALT

        LDN     A'| HEX 20 N,   \ space to blank cursor
        RST     10|
        LDN     A'| HEX 08 N,   \ backspace
        RST     10|
        
        LDA()  HEX 5C08 AA,    \ LAST-K to get typed character

        \ Decode characters from above table
        LDX     HL|  KEY-1^    NN,
        LDX     BC|  HEX 000B  NN,
        CPIR
        JRF NZ'|  HOLDPLACE  \ -IF,
            LDX     HL|  KEY-2^    NN,
            ADDHL   BC|
            LD      A'| (HL)|
        HERE DISP, \ THEN, 

        \ CAPS LOCK management
        CPN    6 N,
        JRF NZ'|  HOLDPLACE  \ -IF,
            LDX     HL|   HEX 5C6A NN,
            LD      A'| (HL)|
            XORN         08 N,   \ toggle FLAGS2 
            LD   (HL)'|    A|
            LDN     A'|  00 N,   \ NUL will be ignored
        HERE DISP, \ THEN, 
        
        LD      L'|    A|
        LDN     H'|    0 N,

        LDA()  HEX 5C48 AA,    \ BORDCR system variable
        RRA
        RRA
        RRA
        ORN     18 N,           \ quick'n'dirty click 
        OUTA    HEX FE P,
        LDN     B'|    0 N,
        HERE \ BEGIN,
        DJNZ    HOLDPLACE SWAP DISP, \ Wait loop
        XORN    18 N,           \ click ?
        OUTA    HEX FE P,

        LDX()   SP|    HEX 02C org^ +  AA, \ restore SP

        POP     IX|
        POP     BC|
        PUSH    HL|
        Next
        C;


\ 637Bh
.( ?TERMINAL )
\ Tests the terminal-break. Leaves tf if [SHIFT-SPACE/BREAK] is pressed, or ff.
CODE ?terminal ( -- 0 | -1 ) ( true if BREAK pressed )
         
        LDX     HL| 0 NN,
        LD()X   SP|    HEX 02C org^ +  AA, \ saves SP
        LDX     SP|    HEX  -5 org^ +  NN, \ temp stack just below ORIGIN
        CALL    HEX 1F54 AA,
        LDX()   SP|    HEX 02C org^ +  AA, \ restore SP
        JRF    CY'| HOLDPLACE
            DECX     HL|
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


\ 7734h >>>
.( INKEY )
\ calls ROM inkey$ routine, returns c or "zero".
CODE inkey ( -- c )
         
        PUSH    BC|
        LD()X   SP|    HEX 02C org^ +  AA, \ saves SP
        LDX     SP|    HEX  -5 org^ +  NN, \ temp stack just below ORIGIN
        PUSH    IX|
        CALL    HEX  15E6  AA,  ( instead of 15E9 )
        POP     IX|
        LDX()   SP|    HEX 02C org^ +  AA, \ restore SP
        LD      L'|    A|
        LDN     H'|    0 N,
        POP     BC|
        PUSH    HL|
        Next
        C;


\ 7749h >>>
.( SELECT )
\ selects the given channel number
\ #2 is keyboard or video
\ #3 is printer or rs-232 i/o port (it depends on OPEN#3 from BASIC)
\ #4 is depends on OPEN#4 from BASIC
CODE select ( n -- )
         
        POP     HL|
        PUSH    BC|
        LD      A'|    L|
        LD()X   SP|    HEX 02C org^ +  AA, \ saves SP
        LDX     SP|    HEX  -5 org^ +  NN, \ temp stack just below ORIGIN
        PUSH    IX|
        CALL    HEX  1601 AA,
        POP     IX|
        LDX()   SP|    HEX 02C org^ +  AA, \ restore SP
        POP     BC|
        Next 
        C;


\ ______________________________________________________________________ 
\ 
\ NextZXOS calls
\

.( F_SEEK )
\ Seek to position d in file-handle u.
\ Return a false-flag 0 on success, True flag on error
CODE f_seek ( d u -- f )
        POP     HL|     
        LD      A'|     L|
        LD      H'|     B|
        LD      L'|     C|
        POP     BC|
        POP     DE|
        PUSH    IX|
        PUSH    HL|
        LDX     IX|     0 NN,
        RST     08|     HEX  9F  C,
HERE DUP       
        POP     BC|
        POP     IX|
        SBCHL   HL|
        PUSH    HL|
        Next
        C;        
    
    
.( F_CLOSE )
\ Close file-handle u.
\ Return 0 on success, True flag on error
CODE f_close ( u -- f )
        POP     HL|
        LD      A'|   L|
        PUSH    IX|
        PUSH    BC|
        RST     08|   HEX  9B  C,
        JR      BACK,
\       POP     BC|
\       POP     IX|
\       SBCHL   HL|
\       PUSH    HL|
\       Next
        C;        
    
    
.( F_SYNC )
\ Sync file-handle u changes to disk.
\ Return 0 on success, True flag on error
CODE f_sync ( u -- f )
        POP     HL|
        LD      A'|     L|
        PUSH    IX|
        PUSH    BC|
        RST     08|   HEX  9C  C,
        JR      BACK,
\       POP     BC|
\       POP     IX|
\       SBCHL   HL|
\       PUSH    HL|
\       Next
        C;        


.( F_FGETPOS )
\ Get current position d of file-handle u.
\ Return d and a false-flag 0 on success, or True flag on error
CODE f_fgetpos ( u -- d f )
        POP     HL|     
        LD      A'|     L|
        PUSH    IX|
        PUSH    BC|
        RST     08|     HEX  0A0  C,
        POP     HL|     \ Program Pointer to be kept in BC
        POP     IX|
        PUSH    DE|
        PUSH    BC|
        LD      B'|     H|
        LD      C'|     L|
        SBCHL   HL|
        PUSH    HL|
        Next
        C;        
    
    
.( F_READ )
\ Read b bytes from file-handle u to address a
\ Return the actual number n of bytes read 
\ Return 0 on success, True flag on error
CODE f_read ( a b u -- n f )
        LD      D'|     B|
        LD      E'|     C|
        POP     HL|         \ file handle number
        LD      A'|     L|
        POP     BC|         \ bytes to read
        EX(SP)IX
        PUSH    DE|
        RST     08|   HEX  9D  C,
HERE        
        POP     BC|
        POP     IX|
        PUSH    DE|
        SBCHL   HL|
        PUSH    HL|
        Next
        C;        
    
    
.( F_WRITE )
\ Write bytes currently stored at address a to file-handle u.
\ Return the actual n bytes written and 0 on success, True flag on error.
CODE f_write ( a b u -- n f )
        LD      D'|     B|
        LD      E'|     C|
        POP     HL|         \ file handle number
        LD      A'|     L|
        POP     BC|         \ bytes to read
        EX(SP)IX
        PUSH    DE|
        RST     08|     HEX  9E  C,
        JR      BACK,
\       POP     BC|
\       POP     IX|
\       PUSH    DE|
\       SBCHL   HL|
\       PUSH    HL|
\       Next
        C;        
    
    
.( F_OPEN )
\ open a file 
\ a1 (filespec) is a null-terminated string, such as produced by ," definition
\ a2 is address to an 8-byte header data used in some cases.
\ b is access mode-byte, that is a combination of:
\ any/all of:
\   esx_mode_read          $01 request read access
\   esx_mode_write         $02 request write access
\   esx_mode_use_header    $40 read/write +3DOS header
\ plus one of:
\   esx_mode_open_exist    $00 only open existing file
\   esx_mode_open_creat    $08 open existing or create file
\   esx_mode_creat_noexist $04 create new file, error if exists
\   esx_mode_creat_trunc   $0c create new file, delete existing
\ Return file-handle u and 0 on success, True flag on error
CODE f_open ( a1 a2 b -- fh f )
        LD      H'|     B|
        LD      L'|     C|
        POP     BC|         \ mode
        LD      B'|     C|
        POP     DE|         \ 8-byte buffer if any
        EX(SP)IX            \ filespec nul-terminated
        PUSH    HL|         \ this pushes original bc
        LDN     A'|     CHAR  *  N,
        RST     08|     HEX  9A  C,
HERE DUP        
        POP     BC|
        POP     IX|
        SBCHL   HL|
        LD      E'|     A|
        LDN     D'|     0  N,
        PUSH    DE|
        PUSH    HL|
        Next
        C;
    \ CREATE FILENAME ," test.txt"   \ new Counted String zero-padded
    \ FILENAME 1+ PAD 1 F_OPEN
    \ DROP
    \ F_CLOSE


.( F_OPENDIR )
\ given a z-string address, open a file-handle to the directory
\ Return 0 on success, True flag on error
CODE f_opendir ( a -- fh f )
        EX(SP)IX            \ filespec nul-terminated
        PUSH    BC|
        LDN     B'|   HEX 10   N,
        LDN     A'|   CHAR C   N,
        RST     08|   HEX  A3  C,
        JR      BACK,
        C;
        

.( F_READDIR )
\ Given a pad address a1, a filter z-string a2 and a file-handle fh
\ fetch the next available entry of the directory.
\ Return 1 as ok or 0 to signal end of data then 
\ return 0 on success, True flag on error
CODE f_readdir ( a1 a2 fh -- n f )
        POP     HL|
        LD      A'|     L|
        POP     DE|
        EX(SP)IX            \ wildcard spec nul-terminated
        PUSH    BC|
        RST     08|   HEX  A4  C,
        JR      BACK,
        C;
        

\ ______________________________________________________________________ 
\ 

\ 63A2h
.( CMOVE )
\ If n > 0, moves memory content starting at address a1 for n bytes long
\ storing then starting at address addr2. 
\ The content of a1 is moved first. See CMOVE> also.
CODE cmove ( a1 a2 nc -- )
         
        EXX
        POP     BC|
        POP     DE|
        POP     HL|
        LD      A'|    B|
        ORA      C|    
        JRF     Z'| HOLDPLACE
            LDIR  
        HERE DISP, \ THEN,
        EXX
        Next 
        C;


\ 63BBh
.( CMOVE> )
\ If n > 0, moves memory content starting at address a1 for n bytes long
\ storing then starting at address addr2. 
\ The content of a1 is moved last. See CMOVE.
CODE cmove> ( a1 a2 nc -- )
         
        EXX
        POP     BC|
        POP     DE|
        POP     HL|
        LD      A'|    B|
        ORA      C|
        JRF     Z'| HOLDPLACE
            EXDEHL
            ADDHL   BC|
            DECX    HL|
            EXDEHL 
            ADDHL   BC|
            DECX    HL|
            LDDR  
        HERE DISP, \ THEN,
        EXX
        Next 
        C;


\ 63DAh
.( UM* ) 
\ this once was named U*
\ A double-integer is kept in CPU registers as HLDE then pushed on stack.
\ On the stack a double number is treated as two single numbers
\ where HL is on the top of the stack and DE is the second from top,
\ so in the stack memory it appears as LHED.
\ Instead, in 2VARIABLE a double number is stored as EDLH.
\ this definition could use "MUL" Z80N new op-code.
\ This is the concept:
\    HL 
\    DE
\  ----  
\    Yy      Yy := E*L   
\   Ww      Ww := E*H      
\   Xx      Xx := D*L   sTt := Ww+Xx   rq := t+Y = w+x+Y  
\  Zz      Zz := D*H    uU:=Zz+sT+r
\  ----
\  Uuqy
CODE um* ( u1 u2 -- ud )
                                \ cf  a  hl  de  bc    tos
        EXX                     \ --  -  --  --  --    ---
        POP     DE|             \            DE        
        POP     HL|             \        HL  DE        
        LD      B'|    L|       \        HL  DE  L     
        LD      C'|    E|       \        HL  D.  LE     
        LD      E'|    L|       \        H.  DL  LE    
        LD      L'|    D|       \        HD  DL  LE    
        PUSH    HL|             \        ..  DL  LE    HD
        LD      L'|    C|       \        HE  DL  LE    HD
        MUL                     \        HE  Xx  LE    HD
        EXDEHL                  \        Xx  HE  LE    HD
        MUL                     \        Xx  Ww  LE    HD
        XORA     A|             \     0  Xx  Ww  LE    HD
        ADDHL   DE|             \  s  0  Tt  ..  LE    HD
        ADCA     A|             \  .  s  Tt      LE    HD
        LD      E'|    C|       \     s  Tt   E  L.    HD
        LD      D'|    B|       \     s  Tt  LE  .     HD
        MUL                     \     s  Tt  Yy        HD
        LD      B'|    A|       \     .  Tt  Yy  s     HD
        LD      C'|    H|       \        .t  Yy  sT    HD
        LD      A'|    D|       \     Y   t  .y  sT    HD
        ADDA     L|             \  r  q   .   y  sT    HD
        LD      H'|    A|       \  r  .  q.   y  sT    HD
        LD      L'|    E|       \  r     qy   .  sT    HD
        POP     DE|             \  r     qy  HD  sT    
        MUL                     \  r     qy  Zz  sT    
        EXDEHL                  \  r     Zz  qy  sT    
        ADCHL   BC|             \  .     Uu  qy  ..    
        PUSH    DE|
        PUSH    HL|
        EXX
        Next
        C;


\ 640Dh
.( UM/MOD ) 
\ this was U/
\ it divides ud into u1 giving quotient q and remainder r
\ algorithm takes 16 bit at a time starting from msb
\ DE grows from lsb upward with quotient result
\ HL keeps the remainder at each stage of division
\ each loop 'lowers' the next binary digit to form the current dividend
CODE um/mod ( ud u1 -- r q )
         
        EXX
        POP     BC|        \ divisor
        POP     HL|        \ high part
        POP     DE|        \ low part
        LD      A'|    L|  \ check without changing arguments
        SUBA     C|        \ if divisor is greater than high part
        LD      A'|    H|  \ then quotient won't be in range
        SBCA     B|

        JRF    NC'| HOLDPLACE
            LDN     A'| DECIMAL 16 N,
            
            HERE \ BEGIN, 
                SLA      E|
                RL       D|
                ADCHL   HL|

                JRF    NC'| HOLDPLACE
                    ANDA     A|
                    SBCHL   BC|
                JR        HOLDPLACE  SWAP HERE DISP, \ ELSE,
                    ANDA     A|
                    SBCHL   BC|
                    JRF    NC'| HOLDPLACE
                        ADDHL   BC|
                        DECX    DE|
                    HERE DISP, \ THEN,
                HERE DISP, \ THEN,

                INCX    DE|
                DEC     A'|
            JRF     NZ'| HOLDPLACE SWAP DISP, \ -UNTIL,  
            \ until zero
            EXDEHL
        HERE SWAP                    \ strange jump here
            PUSH    DE|
            PUSH    HL|
            EXX
            Next 
        HERE DISP, \ THEN,
        LDX     HL|    HEX FFFF NN,
        LD      D'|    H|
        LD      E'|    L|
        JR      HOLDPLACE SWAP DISP, \ strange jump there 
        C;


\ 644Eh
.( AND )
\ bit logical AND. Returns n3 as n1 AND n2
CODE and ( n1 n2 -- n3 )
         
        POP     DE|
        POP     HL|
        LD      A'|    E|
        ANDA     L|     
        LD      L'|    A|
        LD      A'|    D|
        ANDA     H|     
        LD      H'|    A|
        PUSH    HL|
        Next
        C;


\ 6461h
.( OR )
\ bit logical OR. Returns n3 as n1 OR n2
CODE or  ( n1 n2 -- n3 )
         
        POP     DE|
        POP     HL|
        LD      A'|    E|
        ORA      L|     
        LD      L'|    A|
        LD      A'|    D|
        ORA      H|     
        LD      H'|    A|
        PUSH    HL|
        Next
        C;


\ 6473h
.( XOR )
\ bit logical XOR. Returns n3 as n1 XOR n2
CODE xor ( n1 n2 -- n3 )
         
        POP     DE|
        POP     HL|
        LD      A'|    E|
        XORA     L|     
        LD      L'|    A|
        LD      A'|    D|
        XORA     H|     
        LD      H'|    A|
        PUSH    HL|
        Next
        C;


\ 6486h
.( SP@ )
\ returns on top of stack the value of SP before execution
CODE sp@ ( -- a )
         
        LDX     HL|    0 NN,
        ADDHL   SP|
        PUSH    HL|
        Next
        C;


\ 6495h
.( SP! )
\ restore SP to the initial value passed
\ normally it is S0, i.e. the word at offset 6 and 7 of user variabiles area.
CODE sp! ( a -- )
         
        POP     HL|        
        LDSPHL

        Next
        C;


\ 64ABh
.( RP@ )
\ returns on top of stack the value of Return-Pointer
CODE rp@ ( -- a )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        PUSH    HL|
        Next
        C;


\ 64B9h
.( RP! )
\ restore RP to the initial value passed
\ normally it is R0 @, i.e. the word at offset 8 of user variabiles area.
CODE rp! ( a -- )

        POP     HL|        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        Next
        C;


\ 64D1h
.( EXIT )
\ exits back to the caller word
CODE exit ( -- )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        LD      C'| (HL)|
        INCX    HL|
        LD      B'| (HL)|
        INCX    HL|
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        Next
        C;       


\ 64E5h
\ .( lastl aka old LEAVE )
\ set the limit-of-loop equal to the current index
\ this forces to leave from loop at the end of the current iteration
\ CODE lastl ( -- )
\ 
\         HERE !rp^ 
\         LDHL,RP              \ macro 30h +Origin
\ 
\         LD      E'| (HL)|  
\         INCX    HL|
\         LD      D'| (HL)|  
\         INCX    HL|
\         LD   (HL)'|    E|  
\         INCX    HL|
\         LD   (HL)'|    D|
\         Next
\         C;       


\ 64FCh
.( >R )
\ pop from calculator-stack and push into return-stack
CODE >r ( n -- )
         
        POP     DE|

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        DECX    HL|
        LD   (HL)'|    D|
        DECX    HL|
        LD   (HL)'|    E|
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        Next
        C;


\ 6511h
.( R> )
\ pop from return-stack and push into calculator-stack
CODE r> ( -- n )

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        INCX    HL|
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        PUSH    DE|
        Next
        C;


\ 6526h
.( R@ )
\ return on top of stack the value of top of return-stack
\ Since this is the same as I, we alter R's CFA to jump there
CODE r@ ( -- n )         
         
        \ this way we will have a real duplicate of I
        JP
        ' i  \ >BODY  LATEST PFA CELL- ! 
        AA,
        C;

\ CODE r  ( -- n )         
\          
\         \ this way we will have a real duplicate of I
\         JP
\         ' i  \ >BODY  LATEST PFA CELL- ! 
\         AA,
\         C;


\ 652Ch
.( 0= )
\ true (-1) if n is zero, false (0) elsewere
CODE 0= ( n -- f )
         
        POP     HL|
        LD      A'|    L|
        ORA      H|
        LDX     HL|    0 NN,
        JRF    NZ'|    HOLDPLACE
            DECX      HL|           \ true
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


.( NOT )
CODE not  ( n -- f )         
         
        \ this way we will have a real duplicate of 0=
        JP
        ' 0=  \ >BODY  LATEST PFA CELL- ! 
        AA,
        C;


\ 6540h
.( 0< )
\ true (-1) if n is less than zero, false (0) elsewere
CODE 0< ( n -- f )
         
        POP     HL|
        ADDHL   HL|
        LDX     HL|    0 NN,
        JRF    NC'|    HOLDPLACE
            DECX      HL|           \ true
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


\ 6553h
.( 0> )
\ true (-1) if n is greater than zero, false (0) elsewere
CODE 0> ( n -- f )
         
        POP     HL|
        LD      A'|    L|
        ORA      H|
        ADDHL   HL|
        LDX     HL|    0 NN,
        JRF    CY'|    HOLDPLACE    
        ANDA     A|
        JRF     Z'|    HOLDPLACE
            DECX      HL|           \ true
        HERE DISP, HERE DISP, \ THEN, THEN,
        PUSH    HL|
        Next
        C;


\ 6569h
.( + )
\ returns the unsigned sum of two top values
CODE + ( n1 n2 -- n3 )
         
        POP     HL|
        POP     DE|
        ADDHL   DE|
        PUSH    HL|
        Next
        C;


\ 6575h
.( D+ )
\ returns the unsigned sum of two top double-numbers
\      d2  d1
\      h l h l
\ SP   LHEDLHED
\ SP  +01234567
CODE d+ ( d1 d2 -- d3 )

        EXX
        POP     BC|            \ BC  = hd2
        POP     DE|            \ DE  = ld2 
        POP     HL|            \ HL  = hd1
        EX(SP)HL               \ HL  = ld1
        ADDHL   DE|            \ HL  = ld1+ld2
        EX(SP)HL               \ HL  = hd1
        ADCHL   BC|            \ HL  = hd1+hd2
        PUSH    HL|
        EXX
        Next
        C;


\ 68F8h >>>
.( 1+ )
\ increment by 1 top of stack
CODE 1+ ( n1 -- n2 )
         
        POP     HL|
        INCX    HL|
        PUSH    HL|
        Next
        C;
        

\ 8072h >>> def
.( 1- )
\ decrement by 1 top of stack
CODE 1-  ( n1 -- n2 )
         
        POP     HL|
        DECX    HL|
        PUSH    HL|
        Next
        C;


\ 6904h >>>
.( 2+ )
\ increment by 1 top of stack
\ MSG#4 this gives MSG#4
CODE 2+ ( n1 -- n2 )
         
        POP     HL|
        INCX    HL|
        INCX    HL|
        PUSH    HL|
        Next
        C;


.( CELL+ )
\ increment by 1 top of stack 
CODE cell+ ( n1 -- n2 )
         
        \ this way we will have a real duplicate of 2+
        JP
        ' 2+  \ >BODY  LATEST PFA CELL- ! 
        AA,
        C;


\ .( ALIGN )
\ CODE align ( a1 -- a2 )
\         Next
\         C;


.( CELL- )
\ decrement by 2 top of stack 
CODE cell- ( n1 -- n2 )

        POP     HL|         \ address 
        DECX    HL|
        DECX    HL|
        PUSH    HL|
        Next
        C;


.( 2- )
\ decrement by 2 top of stack 
CODE 2- ( n1 -- n2 )

        \ this way we will have a real duplicate of 2+
        JP
        ' cell-  \ >BODY  LATEST PFA CELL- ! 
        AA,
        C;


\ 658Bh
.( NEGATE   ( or MINUS )
\ change the sign of number
CODE negate ( n1 -- n2 )
         
        LDX     HL|    0 NN,
        POP     DE|
        ORA      A|
        SBCHL   DE|
        PUSH    HL|
        Next
        C;


\ 659Fh
.( DNEGATE   ( or DMINUS )
\ change the sign of a double number
\ SP : LHED
\ SP :+0123
CODE dnegate ( d1 -- d2 )

        EXX
        POP     BC|            \ hd1
        POP     DE|            \ ld1
        XORA     A|
        LD      H'|    A|
        LD      L'|    A|
        SBCHL   DE|
        PUSH    HL|
        LD      H'|    A|
        LD      L'|    A|
        SBCHL   BC|
        PUSH    HL|
        EXX
        Next
        
        C;



\ 65BCh
.( OVER )
\ copy the second value of stack and put on top.
CODE over ( n m -- n m n )
         
        POP     DE|   \  DE <-- m
        POP     HL|   \  HL <-- n
        PUSH    HL|
        PUSH    DE|
        PUSH    HL|
        Next
        C;


\ 65CBh
.( DROP )
\ drops the top of stack
CODE drop ( n -- )
        
        POP     HL|
        Next
        C;


.( NIP )
\ Drop the second element on the stack.
CODE nip  ( n1 n2 -- n2 )

        POP     HL|
        EX(SP)HL
        Next
        C;


.( TUCK )
\ Copies the top element after the second.
CODE tuck  ( n1 n2 -- n2 n1 n2 )

        POP     HL|     \ HL <-- n2
        POP     DE|     \ DE <-- n1
        PUSH    HL|
        PUSH    DE|
        PUSH    HL|
        Next
        C;


\ 65D8h
.( SWAP )
\ swaps the two values on top of stack
CODE swap ( n1 n2 -- n2 n1 )
         
        POP     HL|
        EX(SP)HL
        PUSH    HL|
        Next
        C;


\ 65E6h
.( DUP )
\ duplicates the top value of stack
CODE dup ( n -- n n )
         
        POP     HL|
        PUSH    HL|
        PUSH    HL|
        Next
        C;


\ 69A9h >>>
.( ROT )
\ Rotates the 3 top values of stack by picking the 3rd in access-order
\ and putting it on top. The other two are shifted down one place.
CODE rot ( n1 n2 n3  -- n2 n3 n1 )
         
        POP     DE|  \ n3
        POP     HL|  \ n2
        EX(SP)HL     \ n1 <-> n2
        PUSH    DE|  \ n3, n2
        PUSH    HL|
        Next
        C;


.( -ROT )
\ Rotates the 3 top values of stack by picking the 1st in access-order
\ and putting back to 3rd place. The other two are shifted down one place.
CODE -rot ( n1 n2 n3  -- n3 n1 n2 )
         
        POP     HL|  \ n3
        POP     DE|  \ n2
        EX(SP)HL     \ n1 <-> n3
        PUSH    HL|  \ n1
        PUSH    DE|  \ n2
        Next
        C;


.( PICK )
\ Duplicate the nth item on the stack to the top of the stack.
\ Zero based, that is the top item on the stack is the zeroth item,
\ the one below that is the first item and so on. (O PICK has the
\ same effect as DUP, 1 PICK the same as OVER).
CODE pick ( n -- v )

        POP     HL| 
        ADDHL   HL|
        ADDHL   SP|
        LD      A'| (HL)|
        INCX    HL|
        LD      H'| (HL)|
        LD      L'|    A|
        PUSH    HL|
        Next
        C;


\ .( ROLL )
\ Roll the nth item to the top of the stack, moving the others
\ down. Also zero based, (eg., 1 ROLL is SWAP, 2 ROLL is ROT).
\        N0 N1 N2 N3
\ SP    +01 23 45 67
\         HL DE
\ CODE roll ( n1 n2 n3 ... n -- n2 n3 ... n1  )
\ 
\         EXX                     \ we need all registers free
\         POP     HL|             \ number of cells to roll
\         LD      A'|    H|
\         ORA      L|
\         JRF     Z'|  HOLDPLACE  \ skip if ZERO
\             ADDHL   HL|             \ number of bytes to move
\             LD      B'|    H|
\             LD      C'|    L|
\             ADDHL   SP|             \ address of n1
\             LD      A'| (HL)|       \ take n1 into A and A'
\             INCX    HL|
\             EXAFAF
\             LD      A'| (HL)|       \ take n1 into A and A'
\             LD      D'|    H|
\             LD      E'|    L|
\             DECX    HL|
\             DECX    HL|
\             LDDR
\             EXDEHL
\             LD   (HL)'|    A|
\             DECX    HL|
\             EXAFAF
\             LD   (HL)'|    A|
\         HERE DISP,
\         EXX
\         Next
\         C;


\ \ 6E8Bh >>>
\ .( 2OVER )
\ CODE 2over ( d1 d2 -- d1 d2 d1 )
\          
\         LDX     HL| 0007 NN,
\         ADDHL   SP|
\         LD      D'| (HL)|
\         DECX    HL|
\         LD      E'| (HL)|
\         PUSH    DE|
\         DECX    HL|
\         LD      D'| (HL)|
\         DECX    HL|
\         LD      E'| (HL)|
\         PUSH    DE|
\         Next
\         C;


\ 6E66h >>>
.( 2DROP )
CODE 2drop ( d -- )
         
        POP     HL|
        POP     HL|
        Next
        C;


\ 6E75h >>>
.( 2SWAP )
CODE 2swap  ( d1 d2 -- d2 d1 )
         
        POP     AF|     \ d2-H
        POP     HL|     \ d2-L

        POP     DE|     \ d1-H
        EX(SP)HL        \ swaps d1-L and d2-L
        PUSH    AF|     \ d2-H

        PUSH    HL|     \ d1-L (!)
        PUSH    DE|     \ d1-H

        Next
        C;


\ 65F3h
.( 2DUP )
CODE 2dup  ( d -- d d )
         
        POP     HL|
        POP     DE|
        PUSH    DE|
        PUSH    HL|
        PUSH    DE|
        PUSH    HL|
        Next
        C;


\ \ 6EA9h >>>
\ \ 2ROT
\ \      d3  |d2  |d1  |
\ \      h l |h l |h l |
\ \ SP   LHED|LHED|LHED|
\ \ SP  +0123|4567|89ab|
\ CODE 2rot  ( d1 d2 d3 -- d2 d3 d1 )
\         
\         LDX     HL|  HEX 000B NN,
\         ADDHL   SP|
\         LD      D'| (HL)|
\         DECX    HL|
\         LD      E'| (HL)|
\         DECX    HL|
\         PUSH    DE|
\         LD      D'| (HL)|
\         DECX    HL|
\         LD      E'| (HL)|
\         DECX    HL|
\         PUSH    DE|
\ 
\ \      d1  |d3  |d2  |d1  |
\ \      h l |h l |h l |h l |
\ \ SP   LHED|LHED|LHED|LHED|
\ \ SP       +0123|4567|89ab|
\ 
\         LD      D'|    H|
\         LD      E'|    L|
\         INCX    DE|
\         INCX    DE|
\         INCX    DE|
\         INCX    DE|
\         PUSH    BC|
\         LDX     BC|  HEX 000C NN,
\         LDDR        
\         POP     BC|
\         POP     DE|
\         POP     DE|
\         Next
\         C;


\ 6603h
.( +! )
\ Sums to the content of address a the number n.
\ It is the same of  a @ n + a !
CODE +! ( n a -- )
         
        POP     HL|
        POP     DE|
        LD      A'| (HL)|
        ADDA     E|
        LD   (HL)'|    A|
        INCX    HL|
        LD      A'| (HL)|
        ADCA     D|
        LD   (HL)'|    A|
        Next
        C;


\ 6616h
.( TOGGLE )
\ Complements the byte at addrress a with the model n.
CODE toggle ( a n -- )
         
        POP     DE|
        POP     HL|
        LD      A'| (HL)|
        XORA     E|
        LD   (HL)'|    A|
        Next
        C;


\ 6629h
.( @ )
\ fetch 16 bit number n from address a.
\ Z80 keeps high byte is in high memory
CODE @ ( a -- n )
         
        POP     HL|
        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        PUSH    DE|
        Next
        C;


\ 665Bh
.( ! )
\ store 16 bit number n to address a.
\ Z80 keeps high byte is in high memory
CODE ! ( n a -- )
         
        POP     HL|
        POP     DE|
        LD   (HL)'|    E|
        INCX    HL|
        LD   (HL)'|    D|
        Next
        C;


\ 6637h
.( C@ )
\ single character fetch
CODE c@ ( a -- c )
         
        POP     HL|
        LD      L'| (HL)|
        LDN     H'|    0 N,
        PUSH    HL|
        Next
        C;


\ 6669h
.( C! )
\ single character store
CODE c! ( c a -- )
         
        POP     HL|
        POP     DE|
        LD   (HL)'|    E|
        Next
        C;


\ 6645h
.( 2@ )
\ fetch a 32 bits number d from address a and leaves it on top of the 
\ stack as two single numbers, high part as top of the stack.
\ A double number is normally kept in CPU registers as HLDE.
\ On stack a double number is treated as two single numbers
\ where HL is on the top of the stack and DE is the second from top,
\ so the sign of the number can be checked on top of stack
\ and in the stack memory it appears as LHED.
CODE 2@ ( a -- d )
         
        POP     HL|
        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        INCX    HL|
        LD      A'| (HL)|
        INCX    HL|
        LD      H'| (HL)|
        LD      L'|    A|
        PUSH    HL|
        PUSH    DE|
        Next
        C;


\ 6676h
.( 2! )
\ stores a 32 bits number d from address a and leaves it on top of the 
\ stack as two single numbers, high part as top of the stack.
\ A double number is normally kept in CPU registers as HLDE.
\ On stack a double number is treated as two single numbers
\ where HL is on the top of the stack and DE is the second from top,
\ so in the stack memory it appears as LHED.
\ and the sign of the number can be checked on top of stack.
CODE 2! ( d a -- )

        EXX
        POP     HL|        \ address
        POP     BC|        \ higher
        POP     DE|        \ lower
        LD   (HL)'|    C|
        INCX    HL|
        LD   (HL)'|    B|
        INCX    HL|
        LD   (HL)'|    E|
        INCX    HL|
        LD   (HL)'|    D|
        EXX
        Next
        C;


\ new
.( P@ )
\ Read one byte from port ap and leave the result on top of stack
CODE p@ ( p -- b )
         
        EXX
        POP     BC|
        LDN     H'|  0 N,
        IN(C)   L'|
        PUSH    HL|
        EXX
        Next
        C;



\ new
.( P! )
\ Send one byte (top of stack) to port ap 
CODE p! ( b p -- )
         
        EXX
        POP     BC|
        POP     HL|
        OUT(C)  L'|
        EXX
        Next
        C;


\ new
.( 2* )
\ doubles the number at top of stack 
CODE 2* ( n1 -- n2 )
         
        POP     HL|
        ADDHL   HL|
        PUSH    HL|
        Next
        C;


\ new
.( 2/ )
\ halves the top of stack, sign is unchanged
CODE 2/ ( n1 -- n2 )
         
        POP     HL|
        SRA      H|
        RR       L|
        PUSH    HL|
        Next
        C;


\ new
.( LSHIFT )
\ bit left shift of u bits
CODE lshift ( n1 u -- n2 )
         
        POP     DE|
        POP     HL|
        LD      A'|    E|
        ORA      A|
        JRF     Z'| HOLDPLACE
            HERE
                ADDHL   HL|
                DEC     A'|
            JRF    NZ'| HOLDPLACE SWAP DISP,
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


\ new
.( RSHIFT )
\ bit right shift of u bits
CODE rshift ( n1 u -- n2 )
         
        POP     DE|
        POP     HL|
        LD      A'|    E|
        ORA      A|
        JRF     Z'| HOLDPLACE
            HERE
                SRL      H|
                RR       L|
                DEC     A'|
            JRF    NZ'| HOLDPLACE SWAP DISP,
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


.( CELLS )
CODE cells ( n2 -- n2 )
        \ this way we will have a real duplicate of 2*
        JP
        ' 2*  \ >BODY  LATEST PFA CELL- ! 
        AA,
        C;


\ 668Ah
.( : ) \ ___ late-patch ___ 
\ Colon-definition
: : 
    ?EXEC     
    !CSP      
    CURRENT  @ 
    CONTEXT  ! 
    CREATE 
    SMUDGE 
    ] 
    ;CODE

        HERE TO enter^ 

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        DECX    HL| 
        LD   (HL)'|    B|
        DECX    HL| 
        LD   (HL)'|    C|
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        POP     BC|          \ this depends on how inner interpreter works
                             \ Direct-Thread version

        Next
        C;
    IMMEDIATE
    
    \ we defined this peculiar word using "old" colon definition 
    \ behaviour. Now we want to use the ;CODE just coded.
    
    enter^  LATEST PFA CELL- !  \ patch to the correct ;CODE

     
\ 66B2h
.( ; ) \ ___ late-patch ___ 
: ; 
    ?CSP
    COMPILE   exit   
    SMUDGE    
    [COMPILE] [    \ previous version
    ;
    IMMEDIATE


\ 66C4h
.( NOOP )
CODE noop ( -- )
        Next
        C;


\ 66CFh
.( CONSTANT ) \ ___ late-patch ___ 
: constant ( n ccc --   )
           (       -- n )
    CREATE , 
    \ SMUDGE
    ;CODE

        POP     HL|
        LD      E'| (HL)|
        INCX    HL|
        LD      D'| (HL)|
        PUSH    DE|
        Next
        C;


\ 66EDh
.( VARIABLE ) \ ___ late-patch ___ only for ;CODE
: variable (   ccc --   )
           (       -- n )
    0 constant
    ;CODE


        Next
        C;


\ 6703h
.( USER ) \ ___ late-patch ___ 
: user ( n ccc --   )
       (       -- n )
    CREATE  C, 
    \ SMUDGE
    ;CODE

        POP     HL|
        LD      E'| (HL)|
        LDN     D'|    0 N,
    \   LDX     HL| vars^ @ NN,
        LDHL()  vars^ AA,       \ this is more dynamic...
        ADDHL   DE|
        PUSH    HL|
        Next
        C;


\ 675Ah
.(  0  )
   0    constant 0


\ 6762h
.(  1  )
   1    constant 1


\ 676Ah
.(  2  )
   2    constant 2


\ 6772h
.(  3  )
   3    constant 3


\ new
.( -1  )
  -1    constant -1


\ 677Ah
\ PI
\ HEX 0 4080              \ FLOATING 1.0 
\ >W DECIMAL 36 FOP W>    \ ARCTAN 
\ HEX 100 +               \ 4.0 F*
\ HEX 0FDA 4149 
\       2constant pi


\ 6786h
.( BL )
BL  constant bl


\ 678Eh
.( C/L )
C/L constant c/l


\ 6798h
.( B/BUF )
B/BUF constant b/buf


\ 67A4h
.( B/SCR )
B/SCR constant b/scr


.( L/SCR )
\ b/scr b/buf c/l */ constant l/scr
L/SCR constant l/scr


\ 67B0h
.( +ORIGIN )
\ : +origin
\     [ org^ ] Literal + ;
CODE +origin ( n1 -- n2 )
        POP     HL|
        LDX     DE|  org^  NN,
        ADDHL   DE|
        PUSH    HL|
        Next
        C;

    
." (NEXT) "
next^     constant (next)


\ 67C4h  
.( USER VARIABILES: )
.( S0 R0 TIB WIDTH ... )


DECIMAL
\ 00     user    unused    \ for safety reason. RP could spill over here.
\ 02     user    unused    \ for safety reason. RP could spill over here.
\ 04     user    unused    \ for safety reason. RP could spill over here.
  06     user    s0        \ starting value of Stack-Pointer
  08     user    r0        \ starting value of Return-Pointer
  10     user    tib       \ input terminal buffer address
  12     user    width     \ maximum number of characters for a word name
  14     user    warning   \ error reporting method: 0 base, 1 verbose
  16     user    fence     \ minimum address where FORGET can work
  18     user    dp        \ Dictionary Pointer 
  20     user    voc-link  \ pointer to the latest vocabulary
  22     user    first     \ address of first buffer
  24     user    limit     \ address of last buffer
  26     user    exp       \ keeps the exponent in number conversion
  28     user    nmode     \ number mode: 0 integer, 1 floating point 
  30     user    blk       \ block number to be interpreted. 0 for terminal
  32     user    >in       \ incremented when consuming input buffer
  34     user    out       \ incremented when sending to output
  36     user    scr       \ latest screen retreieved by LIST
  38     user    offset    \ 
  40     user    context   \ pointer to the vocabulary where search begins
  42     user    current   \ pointer to the vocabulary where search continues
  44     user    state     \ compilation status. 0 interpreting.
  46     user    base      \ 
  48     user    dpl       \ number of digits after decimal point in conversion
  50     user    fld       \ output field width
  52     user    csp       \ used to temporary store Stack-Pointer value
  54     user    r#        \ location of editing cursor
  56     user    hld       \ last character during a number conversion output
  58     user    use       \ address of last used block
  60     user    prev      \ address of previous used block
  62     user    lp        \ Case Pointer...    
  64     user    place     \ number of digits after decimal point in output
  66     user    source-id \ data-stream number in INCLUDE and LOAD-
  68     user    span      \ number of character of last ACCEPT
  70     user    handler   \ throw-catch handler
  72     user    hp        \ heap-pointer address
  
  
\ 1+  has moved backward
\ 2+  has moved backward


\ 6911h
.( HERE )
: here  ( -- a )
    dp @
    ;


\ 6920h    
.( ALLOT )
: allot  ( n -- )
    dp +!
    ;


\ 6930h
.( , )
: ,  ( n -- )
    here     !
    2 allot
    ;


\ 6940h    
.( C, )
: c,  ( c -- )
    here    c!
    1 allot
    ;


\ 754Ch
.( S>D )
\ converts a single precision integer in a double precision
CODE s>d   ( n -- d )
        POP     DE|
        LDX     HL|    0 NN,
        LD      A'|    D|
        ANDN    HEX    80  N, DECIMAL 
        JRF     Z'|    HOLDPLACE \ IF,
        DECX    HL|
        HERE DISP, \ THEN, 
        PUSH    DE|
        PUSH    HL|
        Next
        C;



\ 6951h
.( - )
\ subtraction
CODE - ( n1 n2 -- n3 )
        POP     DE|
        POP     HL|
        ANDA     A|
        SBCHL   DE|
        PUSH    HL|
        Next
        C;


\ 695Fh
.( = )
: =   ( n1 n2 -- f )
    - 0= 
    ;


\ 6987h
.( U< )
\ true (-1) if unsigned u1 is less than u2.
CODE u< ( u1 u2 -- f )
        POP     DE|
        POP     HL|
        ANDA     A|
        SBCHL   DE|
        LDX     HL| -1 NN,          \ true
        JRF    CY'| HOLDPLACE
            INCX     HL|
        HERE DISP, \ THEN,
        PUSH    HL|
        Next
        C;


\ 696Bh
.( < )
\ true (-1) if n1 is less than n2
CODE <  ( n1 n2 -- f )
        POP     DE|
        POP     HL|
        LD      A'|   H|
        XORN    HEX 80   N,  DECIMAL
        LD      H'|   A|
        LD      A'|   D|
        XORN    HEX 80   N,  DECIMAL
        LD      D'|   A|
        SBCHL   DE|     \ set carry-flag if n1 < n2
        SBCHL   HL|     \ HL is zero or -1 depending on carry-flag
        PUSH    HL|
        Next
        C;
        


\ 699Dh
.( > )
\ true (-1) if n1 is greater than n2
: >   ( n1 n2 -- f )
    swap < 
    ; 


.( MIN )
: min
    2dup 
    > If 
        swap
    Then \ Then
    drop
    ;


.( MAX )
: max
    2dup
    < If 
        swap
    Then \ Then
    drop
    ;


\ ROT moved backward near other stack manipulators
\ SPACE  moved few lines below after EMIT


\ 69C7h
.( ?DUP )
\ ?DUP 
\ duplicate if not zero
CODE ?dup ( n -- 0 | n n )
        POP     HL|
        LD      A'|    H|
        ORA      L|
        JRF Z'|   HOLDPLACE \ IF,
            PUSH    HL|
        HERE DISP, \ THEN, 
        PUSH    HL|
        Next
        C;


.( -DUP ) \ is as -DUP
CODE -dup ( n -- 0 | n n )
        \ This way we will have a real duplicate of ?DUP.
        JP
        ' ?dup \ >BODY   LATEST  PFA CELL- !
        AA,
        C;


\ 62CFh <<< moved here because of OUT
.( EMIT )
: emit  ( c -- )
    (?emit)
    ?dup If 
        emitc
        1 out +!
    Then
    ;


\ 69B7
.( SPACE )
: space  ( -- )
    bl emit
    ;

    
\ Dictionary word is structured as follows
\ NFA: +0   one byte of word-length (n) plus some flags (immediate, smudge)
\      +1   word name, last character is toggled with 80h
\ LFA: +1+n link to previous NFA 
\ CFA: +3+n routine address. Colon definitions here have a CALL aa
\ PFA: +6+n "is_code", definitions have no PFA. // +5
\
\ 69DAh
.( TRAVERSE )
: traverse ( a n -- a )
    swap
    Begin
        over +
        [ DECIMAL 127 ] Literal
        over c@ <
    Until
    nip
    ;


\ 6A01h
.( LATEST )
: latest ( -- nfa )
    current @ @
    ;


\ 6A14h
.( LFA )
: lfa ( pfa -- lfa )
    [ 5 ] Literal -
    ;


\ 6A24h
.( CFA )
: cfa ( pfa -- cfa )
    3 -
    ;


\ 6A32h 
.( NFA )
: nfa ( pfa -- nfa )
    [ 6 ] Literal -
    -1 traverse 
    ;


\ 6A48h
.( PFA )
: pfa ( nfa -- pfa )
    1 traverse
    [ 6 ] Literal +
    ;


\ new
.( >BODY )
: >body ( cfa -- pfa )
    3 +
    ;


\ new
.( <NAME )
: <name ( cfa -- nfa )
    >body  \ cfa->pfa
    nfa    
    ;


\ 6A5C
.( !CSP )
: !csp    ( -- )
    sp@ csp ! 
    ;


\ 6A6D
.( ?ERROR ) \ ___ forward ___ because of ERROR
: ?error    ( f n -- )
    swap
    If 

        [ HERE TO error^ ]

        ERROR   \ forward 
    Else
        drop
    Then \ Then
    ;


\ 6A88
.( ?COMP )
: ?comp ( -- ) ( Can't be executed )
    state @ 0=
    [ DECIMAL 17 ] Literal 
    ?error 
    ;


\ 6AA0
.( ?EXEC )
: ?exec ( -- ) ( Can't be compiled )
    state @ 
    [ DECIMAL 18 ] Literal 
    ?error 
    ;


\ 6AB6
.( ?PAIRS )
: ?pairs ( m n -- )  ( Syntax error )
    -
    [ DECIMAL 19 ] Literal 
    ?error 
    ;


\ 6ACB
.( ?CSP )
: ?csp ( -- )  ( Bad end )
    sp@ csp @ - 
    [ DECIMAL 20 ] Literal 
    ?error 
    ;


\ 6AE4
.( ?LOADING )
: ?loading ( -- )  ( Aren't loading now )
    blk @ 0= 
    [ DECIMAL 22 ] Literal 
    ?error 
    ;


\ 6AFF
.( COMPILE )
: compile ( -- )
    ?comp
    r> dup cell+ >r
    @ ,
    ;


.( COMPILE, )
: compile, ( xt -- )
    ?comp 
    ,
    ;


\ 6b1b
.( [ )
: [ ( -- )  
    0 state !
    ;
    IMMEDIATE


\ 6b29
.( ] )
: ] ( -- )  
    [ DECIMAL 192 ] Literal
    state !
    ;


\ 6B39h
.( SMUDGE )
: smudge ( -- )  
    latest
    [ DECIMAL 32 ]  Literal
    toggle
    ;


\ 73C9h >>>
.( IMMEDIATE )
: immediate
    latest 
    [ DECIMAL 64 ] Literal 
    toggle
    ;


\ 6b4e
.( HEX )
: hex ( -- )  
    [ DECIMAL 16 ]  Literal
    base !
    ;


\ 6b60
.( DECIMAL )
: decimal ( -- )  
    [ DECIMAL 10 ]  Literal
    base !
    ;


\ 6b9f
." (;CODE) "
: (;code)  ( -- )
    r>
    latest pfa cfa 
    [ HEX CD ] Literal      \ At Latest CFA put "call" op-code 
    over c! \ why can't use comma? because CFA was already ALLOTted by create? 
    1+      \ At Latest CFA+1 put address for call. 
    !
    ;
    DECIMAL


\ 6bb7
.( ;CODE ) \ ___ forward ___ because of ASSEMBLER vocabulary.
: ;code  ( -- )   
    ?csp
    compile   (;code)
    [COMPILE] [             \ new version of [

    [ HERE TO asm^ ]        \ cannot patch until we'll defined ASSEMBLER     

    [COMPILE] ASSEMBLER     \ previous vocab    
    \ will be changed this NOOP to ASSEMBLER as soon we have it.
    \ in reality, we need to define this way  <BUILD  only.
    ;
    immediate


\ 6BCDh
.( <BUILDS )
: <builds    ( -- ) 
    0 
    constant
    ;


\ .( RECURSE )
\ : recurse
\     ?comp
\     latest pfa cfa ,
\     ; 
\     immediate


\ 6BDFh
.( DOES> )
: does>    ( -- ) 
    r>                       \ at compile-time, address of word after DOES>
    latest pfa !             \ is put in PFA of LATEST defined word 
    ;code 

        HERE !rp^ 
        LDHL,RP              \ macro 30h +Origin

        DECX    HL|          \ save current IP just like an ENTER
        LD   (HL)'|    B|
        DECX    HL|
        LD   (HL)'|    C|
        
        HERE !rp^
        LDRP,HL              \ macro 30h +Origin
        
        POP     HL|          \ this is PFA of defined word that keeps the
                             \ address of words after DOES> part
        LD      C'| (HL)|    \ Use it as new IP to execute DOES> part
        INCX    HL|
        LD      B'| (HL)|
        INCX    HL|          \ now this is PFA+2 which is passed to DOES> part. 
        PUSH    HL|          \ Puts on TOS the PFA+2 of LATEST defined word    
        Next
        
    smudge


\ 6C06h         
.( COUNT )
CODE count ( a1 -- a2 n )   

        POP     HL|
        LD      E'| (HL)|
        LDN     D'|     0   N,
        INCX    HL|
HERE        
        PUSH    HL|
        PUSH    DE|
        Next
        C;


.( BOUNDS )
CODE bounds  ( a n -- a+n a )
\ given an address and a length ( a n ) calculate the bound addresses
\ suitable for DO-LOOP
        POP     HL|          \ hl := n
        POP     DE|          \ de := a
        ADDHL   DE|          \ hl := a+n
        JR      BACK,        \ jump to "HERE" on COUNT 
        C;


\ 6C1Ah
.( TYPE )
\ Sends to current output channel n characters starting at address a.
: type   ( a n -- )
    bounds
    ?Do
        i c@ emit
    Loop
    ;


.( LEAVE )
: leave ( -- )
    compile (leave)         \ unloop and branch
    here >r 0 ,             \ save HERE and compile placeholder
    0 0                     \ dummy stack entry.
                            \ rotate stack from csp to sp.
    sp@ dup cell+ cell+     ( csp h 0 h 3 h 2 x x sp sp+4 )
    tuck                    
    csp @ swap -            ( csp h 0 h 3 h 2 x x sp+4 sp csp-sp+4 )
    cmove                   ( csp x x h 0 h 3 h 2 )
    csp @ cell-             
                            \ put saved HERE at csp-2 
    r> over !               ( csp H x h 0 h 3 h 2 )
    cell- 0 swap !          ( csp H 0 h 0 h 3 h 2 )
; immediate    


\ 6C43h
.( -TRAILING )
\ Assumes that an n1 bytes-long string is stored at address a 
\ and the string contains a space delimited word,
\ Finds n2 as the position of the first character after the word.
: -trailing ( a n1 -- a n2 )
    dup 0
    ?Do
        2dup + 1-
        c@ bl -
        If
            leave
        Else
            1-
        Then \ Then
    Loop 
    ;


\ 6CC3h new
.( ACCEPT )
\ Accepts at most n1 characters from terminal and stores them at address a 
\ CR stops input. A 'nul' is added as trailer.
\ n2 is the string length. n2 is kept in span user variable also.
: accept ( a n1 -- n2 )
    over + over   ( a  n1+a a       ) 
    0 -rot        ( a  0    a+n1  a ) 
    ?Do           ( a  0 ) 
        drop key  ( a  c ) 
        dup       ( a  c  c )
        [ hex 0E ] Literal +origin 
        @         ( a  c  c  del ) 
        =         ( a  c  c=del  )
        If

            drop        ( a )
            dup i =     ( a a=i )
            1 and
            dup         ( a a=i a=i )
            r> 2- + >r  \ decrement i by 1 or 2.
            If
                [ decimal 7 ] Literal  ( a 7 )
            Else
                [ decimal 8 ] Literal  ( a 8 )
            Then

        Else

            dup         ( a  c  c )
            [ decimal 13 ] Literal 
            =           ( a  c  c=CR )
            If 
                drop bl ( a  bl )
                0       ( a  c  0 )
                \ lastl
            Else 
                dup     ( a  c  c )
            Then

            i c!        ( a  c )
            dup bl <    ( a  c  c<BL )  \ patch ghost word
            If
                r> 1- >r  
            Then

        Then

        emit
        
        0 i 1+ ! \ zero pad
        i 
        i c@ 0= If leave Then
    Loop 
    swap - 1+ 
    dup span ! 
    ;


\ \ 6CC3h
\ .( EXPECT )
\ : expect ( a n -- )
\     accept drop
\     ;


\ 6D40h
.( QUERY )
\ Accept at most 80 character from console. CR stops. 
\ Text is stored in TIB. Variable IN is zeroed.
: query ( -- )
    tib @ 
    [ decimal 80 ] Literal
    accept drop  
    0 >in ! 
    ;


\ 6D5Ch 
.( FILL )
\ If n > 0, fills n locations starting from address a with the value c.
CODE fill ( a n c -- )
         
        EXX

        POP     DE|       \ we need E register only
        POP     BC|
        POP     HL|
        HERE  \ BEGIN, 
            LD      A'|    B|
            ORA      C|
        JRF     Z'|   HOLDPLACE  \ WHILE, 
            LD   (HL)'|    E|
            DECX    BC|
            INCX    HL|
        \ REPEAT     
        JR HOLDPLACE ROT DISP, HERE DISP, 
        EXX
        Next
        C;


\ 6D78
.( ERASE )
\ If n > 0, fills n locations starting from address a with 'nul' characters.
: erase ( a n -- )
    0 fill
    ;


\ 6D88h
.( BLANKS )
\ If n > 0, fills n locations starting from address a with SPACE characters.
: blanks ( a n -- )
    bl fill
    ;


\ 6D99
.( HOLD )
\ Used between <# and #> to insert a character c in numerico formatting.
: hold ( c -- )
\    [ decimal -1 ] Literal
    -1
    hld +!
    hld @ c! 
    ;


\ 6DB2
.( PAD )
\ leaves the buffer text address 
\ This is at a fixed distance over HERE.
: pad  ( -- a )
    here 
    [ decimal 68 ] Literal
    + 
    ;


\ 6DC4h
.( WORD ) \ ___ forward ___ because of BLOCK 
\ reads characters from input streams until it encouners a c delimiter.
\ Stores that packet so it starts from HERE
\ WORD leaves a counter as first byte and ends the packet with two spaces.
\ Other occurrences of c are ignored.
\ If BLK is zero, text is taken from terminal buffer TIB.
\ Otherwise text is taken from the disk-block given by BLK.
\ ">in" variable is incremented of the number of character read.
\ The number of characters read is given by ENCLOSE.
: word  ( c -- a )
    blk @ 
    If
        blk @ 
        
        [ HERE TO block^ ]
        
        BLOCK
    Else
        tib @
    Then \ Then
    >in @ + 
    swap enclose
    here [ decimal 34 ] Literal blanks
    >in +!
    over - >r
    r@ here c!
    +
    here 1+ r> cmove 
    here  \  bl word
    ;


\ 6C79h
.( (.") 
\ Direct procedure compiled by ." and  .(
\ It executes TYPE.
: (.")
    r@ count dup 1+
    r> + >r
    type
    ;


\ new
.( CHAR )
\ get first character from next input word
: char ( -- c )
    bl word
\   here 1+ c@
         1+ c@
    ;


\ new
.( ," )
\ read text from input stream until a " in encontered and 
\ compiles a string as a "counted string" appending a trailing 0x00
: ," ( -- )
    [ CHAR " ] Literal word
    c@ 1+ allot
    0 c,
    ;


\ new
.( .C )
\ intermediate general purpose string builder, used by ." and .(
: .c ( c -- )
    state @ 
    If
        compile (.")
\       word here c@ 
        word      c@ 
        1+ allot
    Else
\       word here count type
        word      count type
    Then \ Then
    ; 
    immediate


\ 6C94h
.( ." )
: ."
    [ CHAR " ] Literal
    [COMPILE] .c 
    ; 
    immediate


\ 6C94h new
.( .( )
: .(
    [ CHAR ) ] Literal
    [COMPILE] .c 
    ; 
    immediate
\ )


\ \ ______________________________________________________________________
\ 
\ \ A floating point number is stored in stack in 4 bytes (HLDE) 
\ \ instead of the usual 5 bytes, so there is a little precision loss
\ \ Maybe in the future we'll be able to extend and fix this fact.
\ \
\ \ Sign is the msb of H, so you can check for sign in the integer-way.
\ \ Exponent +128 is stored in the following 8 bits of HL
\ \ Mantissa is stored in L and 16 bits of DE. B is defaulted.
\ \ 
\ \ A floating point number is stored in Spectrum's calculator stack as 5 bytes.
\ \ Exponent in A, sign in msb of E, mantissa in the rest of E and DCB.
\ \  H   <->  A    # 0   -> a
\ \  LDE <->  EDC  # 0DE -> eCD
\ \  0   <->  B    # 0
\ 
\ \ 6E11h
\ \ >W    ( d -- )
\ \ takes a double-number from stack and put to floating-pointer stack 
\ \ When A is zero, then the float repressent a whole positive number 
\ CODE >w
\         POP     HL|     
\         POP     DE|     
\         PUSH    BC|     
\         RL       L|         \ To keep sign as the msb of H,   
\         RL       H|         \ so you can check for sign in the
\         RR       L|         \ integer-way. Sorry.
\         LDN     B'|    hex FC N,  
\ \       LD      B'|    E|    \ maybe a better fit than C0h
\         LD      C'|    E|    
\         LD      E'|    L|    
\         LD      A'|    H|    
\         ANDA     A|
\         JRF    NZ'|   HOLDPLACE
\             LD      H'|    D|  \ swap C and D 
\             LD      D'|    C|
\             LD      C'|    H|
\         HERE DISP, \ THEN,       
\         CALL    hex 2AB6 AA,
\         POP     BC|
\         Next
\         C;
\ 
\ 
\ \ 6E33h
\ \ W>    ( -- d )
\ \ takes a double-number from stack and put to floating-pointer stack 
\ CODE w>
\         PUSH    BC|     
\         CALL    hex 2BF1 AA,
\         ANDA     A|
\         JRF    NZ'|   HOLDPLACE
\             LD      H'|    D|   \ Swap C and D
\             LD      D'|    C|
\             LD      C'|    H|
\         HERE DISP, \ THEN,       
\         LD      H'|    A|
\         LD      L'|    E|
\         LD      E'|    C|    \ B is lost precision
\         RL       L|         \ To keep sign as the msb of H,
\         RR       H|         \ so you can check for sign in the 
\         RR       L|         \ integer-way. Sorry.
\         POP     BC|
\         PUSH    DE|
\         PUSH    HL|
\         Next
\         C;
\ 
\ 
\ \ 6E51h
\ \ FOP    ( n -- )
\ \ Floating-Point-Operation
\ CODE fop
\         POP     HL|     
\         LD      A'|    L|
\         LD()A   HERE 0 AA,
\         PUSH    BC|
\         RST     28|
\                 HERE SWAP !
\                 hex 04 C, \ this location is patched each time
\                 hex 38 C, \ end of calculation
\         POP     BC|
\         Next
\         C;
\ 
\ 
\ \ ______________________________________________________________________


\ 6F4A
." (SGN) "
\ determines if char in addr a is a sign (+ or -), and in that case increments
\ a flag. Returns f as the sign, true for negative, false for positive.
\ called by NUMBER and (EXP)
: (sgn)  ( a -- a f )
    dup 1+ c@ 
    dup [ CHAR - ] Literal =
    If
        drop 
        1+  
        1 dpl +!
        1
    Else
        [ CHAR + ] Literal =
        If
            1+
            1 dpl +!
        Then
        0
    Then
    ;


\ 6F8C            
." (NUMBER) "
\ using the current BASE parse characters stored in address a 
\ accumulating a double precision integer d
\ the process stops at the first not-convertible character
\ A double-number is kept in CPU registers as HLDE.
\ On the stack a double number is treated as two single numbers
\ where HL is on the top of the stack and DE is the second from top,
\ so in the stack memory it appears as LHED.
\ Instead, in 2VARIABLE a double number is stored as EDLH.
: (number)  ( d a -- d1 a1 )
    Begin
        1+          ( d a ) 
        dup >r      ( d a )   
        c@          ( d c )
        base @      ( d c b )
        digit       ( d n 1 | d 0 )
    While
        swap        ( dL n dH )  
        base @      ( dL n dH b )
        um*         ( dL n d )
        drop rot    ( n dH dL )
        base @      ( n dH dL b )
        um*         ( n dH d )
        d+          ( d )
        dpl @ 1+    ( d m )
        If
            1 dpl +!
        Then
        r>          ( d a )
    Repeat
    r>              ( d a )
    ;


\ 70C1h
.( NUMBER )
: number  ( a -- d )
    0 0 
    rot
    (sgn) >r
    -1 dpl !

    (number)    
    dup c@
    [ decimal 46 ] Literal =
    If
        0 dpl !
        (number)
    Then
    c@ bl - 0 ?error
    r> If
        dnegate
    Then
    ;


\ 7178h
.( -FIND )
\ used in the form -FIND "cccc"
\ searches the dictionary giving CFA and the heading byte 
\ or zero if not found
: -find ( "ccc" -- cfa b 1 | 0 )
    bl word 
\ \ here            \ addr  
    context @ @     \ addr voc
    (find)          \ cfa b 1   |  0
    
    ?dup            \ cfa b 1 1 |  0
    0=              \ cfa b 1 0 |  1
    If  
        here        \ addr
        latest      \ addr voc
        (find)      \ cfa b 1   |  0 
    Then   
    ;

\   dup 0=
\   If
\       drop  \ drops 0
\       here latest (find) \ cfa b f 
\   Then
\   ;


\ 71A2h
." (ABORT) " \ ___ forward ___ because of ABORT
: (abort)  ( -- )

    [ HERE TO abort^ ]

    ABORT  \ we will patch this ABORT with the new abort
    ;


\ 71B2h
.( ERROR ) \ ___ forward ___ because of QUIT
\ raise an error 
\ if WARNING is 0, prints "MSG#n".
\ if WARNING is 1, prints line n of screen 4.
\ if WARNING is -1 does (ABORT) that normally does ABORT
\ value can be negative or beyond block 4.
: error  ( n -- )
    warning @ 0<
    If
        (abort)
    Then

    here count type 
    .( ? )
    [ HERE TO msg1^ ] MESSAGE  \ ___ forward ___
    s0 @ sp!
    blk @ ?dup
    If 
        >in @ swap
    Then \ Then

    [ HERE TO quit^ ]

    QUIT \ we well patch this QUIT with the new quit
    ;
    
    ' error error^ ! \ patch ?error

\   -2 ALLOT \ we can save two bytes because QUIT stops everything.


\ 71E9h
.( ID. )
: id.  ( nfa -- )
    pad [ decimal 32 ] Literal [ decimal 96 ] Literal
    fill
    dup pfa lfa 
    over - 
    pad swap
    cmove
    pad count [ hex 1F ] Literal and 
    type
    space
    ;


\ 721Dh
.( CODE )
: mcod  ( -- cccc )
    -find  \ cfa b f
    If
        drop
        <name   \ now it is CFA, once it was NFA
        id.
        [ 4 ] Literal 
        [ HERE TO msg2^ ] MESSAGE \ ___ forward ___
        space
    Then
    
    here 
    dup c@ width @ min 1+ allot
    dup [ decimal 160 ] Literal toggle
    here 1- [ decimal 128 ] Literal toggle
    latest ,
    current @ !
\   here cell+ ,    \ in direct-thread there is no CFA to point PFA
\                   \ but machine code is directly at CFA.
;


.( CREATE )
: create ( -- cccc )
         ( -- n )
    mcod smudge 
    [ hex CD ] Literal c,
    [ ' variable >BODY \ 0       
        CELL+          \ constant
        CELL+          \ ;code   
        CELL+    
      ] Literal ,
    ;code


        Next
        C;


\ Late-Patch for : colon-definition
    ' :  
        >body ' ?exec     over ! 
        cell+ ' !csp      over !
        cell+ ' current   over !
        cell+ ' @         over !
        cell+ ' context   over !
        cell+ ' !         over !
        cell+ ' create    over !
        cell+ ' smudge    over !
        cell+ ' ]         over !
        cell+ ' (;code)   over !
    drop


\ Late-Patch for ; end-colon-definition
    ' ; 
        >body ' ?csp      over !
        cell+ ' compile   over !
        cell+ ' exit      over !
        cell+ ' smudge    over !
        cell+ ' [         over !
        cell+ ' exit      over !
    drop


\ Late-Patch for CONSTANT
    ' constant  
        >body ' create    over ! 
        cell+ ' ,         over ! 
        cell+ ' (;code)   over ! 
    drop


\ Late-Patch for VARIABLE
    ' variable  
        >body ' 0         over ! 
        cell+ ' constant  over !
        cell+ ' (;code)   over !  
    drop


\ \ Late-Patch for 2CONSTANT
\     ' variable  
\         >body ' constant  over ! 
\         cell+ ' ,         over ! 
\         cell+ ' (;code)   over !  
\     drop


\ Late-Patch for USER
    ' user  
        >body ' create    over ! 
        cell+ ' c,        over ! 
        cell+ ' (;code)   over !  
    drop


\ 7272h 
.( [COMPILE] )
: [compile]   ( -- cccc ) 
    -find  \ cfa b f 
    0= 0 ?error 
    drop  \ already CFA  
    ,
    ;
    immediate


\ 7290h
.( LITERAL )
: literal  ( n -- )
    state @
    If
        compile lit ,
    Then
    ;
    immediate

    
\ 72ACh    
.( DLITERAL )
: dliteral  ( d -- )
    state @
    If
        swap 
        [compile] literal 
        [compile] literal
    Then
    ;
    immediate


\ new
.( [CHAR] )
\ inside colon definition, gets first character from next input word 
\ and compiles it as literal.
: [char]
    char
   [compile] literal
    ; immediate


\ 7306h    
.( 0x00 ) \ i.e. nul word
: ~             \ to be RENAME'd via patch
    blk @ 
    1 >         \ BLOCK #1 is special and exploited by F_GETLINE
    If 
        1 blk +!  
        0  >in !  
        blk @ b/scr 1- and 0= 
        If 
            ?exec 
            r> drop 
        Then
    Else
        r> drop
    Then \ Then
    ; 
    immediate
    
    \ 'nul' PATCH
    hex 80 ' ~  <name  1+  c!
    

\ 7342h    
.( ?STACK )
\ Raise error #1 if stack is empty and you pop it
\ Raise error #7 if stack is full.
\ This means SP must always stay between HERE and FFFF 
\ For 128K BANK paging purpose SP must be <= BFE0 and 50 words room
: ?stack  ( -- )
    sp@ 
    s0 @ swap u< 1 ?error
    here 
    s0 @ < If
        sp@
        here [ decimal 128 ] Literal + u< 
             [ decimal   7 ] Literal ?error
    Then
    ;


\ 736Fh
.( INTERPRET )
\ This is the text interpreter.
\ It executes or compiles, depending on STATE, the text coming from
\ current input stream.
\ If the word search fails after parsing CONTEXT and CURRENT vocabulary,
\ the word is interpreted as numeric and converted, using current BASE,
\ leaving on top of stack a single or double precision number, depending 
\ on the presence of a decimal point.
\ If the number conversion fails, the terminal is notified with ? followed
\ by the offending word.
: interpret  ( -- )
    Begin
        -find \ cfa b f
        If
            state @ <
            If 
                \ already cfa aka xt
                compile, 
            Else
                \ already cfa aka xt
                execute 
                noop            \ need this to avoid LIT to crash the system
            Then
        Else
            here number 
            dpl @ 1+ 
            If 
\               nmode @ 
\               If 
\                   1 0
\                   2drop       \ Integer option
\                   \ f/        \ Floating point option
\               Then \ Then 
                [compile] dliteral 
            Else
                drop
                [compile] literal 
            Then 
        Then 
        ?stack 
        ?terminal If (abort) Then
    Again
    ;

\   -2 ALLOT \ we can save two bytes because the infinite loop


\ 73E1h
.( VOCABULARY )
\ Defining word used in the form   VOCABULARY cccc
\ creates the word  cccc  that gives the name to the vocabulary.
\ Giving  cccc  makes the vocabulary CONTEXT so its words are executed first
\ Giving  cccc DEFINITIONS makes  the vocabulary  CURRENT 
\ so new definitions can be inserted in that vocabulary.
: vocabulary  ( -- cccc )
    <builds
        [ hex A081 ] literal , 
        current @ cell- , 
        here voc-link @ ,       
        voc-link !
    does>
        cell+ context !
    ;


\ 7416h
.( FORTH )
\ Name of the first vocabulary. 
\ It makes FORTH the CONTEXT vocabulary. 
\ Until new user vocabulary are defined, new colon-definitions becomes
\ part of FORTH. It is immediate, so it will executed during the creation
\ of a colon definition to be able to select the vocabulary.
vocabulary forth 
immediate
\ possible patch for first FORTH vocabulary is
    -2 ALLOT 0 ,
\ this should set to ZERO the voc-link-chain, so this "forth" vocabulary
\ will be the only vocabulary available after cut-off.

\ Any new vocabulary is structured as follow:
\ PFA+0 points to DOES> part of VOCABULARY to perform CELL+ CONTEXT !
\ PFA+2 is 81,A0 i.e. a null-word used as LATEST in the new vocabulary
\ PFA+4 always contains the LATEST word of this VOCABULARY.
\       at creations it points to the null-word of its parent vocabulary
\       that is normally FORTH, For example ASSEMBLER points FORTH's null-word
\ PFA+6 is the pointer that builds up the vocabulary linked list.
\       FORTH has 0 here to signal the end of the list and user's variable
\       VOC-LINK points to PFA+6 of the newest vocabulary created.
\       While FORTH is the only vocabulary, VOC-LINK points to FORTH's PFA+6
\       When ASSEMBLER is created, its PFA+6 points to FORTH's PFA+6, and so on


\ 7428h
.( DEFINITIONS )
\ Used in the form  cccc DEFINITIONS
\ set the CURRENT vocabulary at CONTEXT to insert new definitions in 
\ vocabulary cccc.
: definitions  ( ccc -- )
    context @
    current !
    ;


\ 7442h
.( ( )
\ the following text is interpreted as a comment until a closing ) 
: ( 
    [ char ) ] Literal 
    word     \ +drop
    drop
    ;
    immediate


\ 746Ah
.( QUIT )
\ Erase the return-stack, stop any compilation and give controlo to 
\ the console. No message is issued.
: quit  ( -- )
    source-id @ f_close drop  
    0 source-id !
    0 blk !
    [compile] [
    Begin
        r0 @ rp!
        cr
        query interpret
        state @ 0=
        If
            .( ok)
        Then
    Again
    ;        
    
    ' quit quit^ ! 
    
\   -2 ALLOT \ we can save two bytes because the infinite loop


\ \ 7e61 >>>
\ \ .CPU
\ : .cpu
\     .( Z80 )
\     ;


\ 7496h
.( ABORT )
\ Clean stack. Go to command state.
\ Gives control to console via QUIT.
: abort  ( -- )
    s0 @ sp!
    decimal
    \ .cpu
    [compile] forth 
    definitions
    [ here TO autoexec^ ]
    noop
    quit
    ;

    ' abort abort^ ! \ patch

\   -2 ALLOT \ we can save two bytes because QUIT


\ 74AEh 
.( WARM )
: warm 

    [ here TO xi/o2^ ]    
    BLK-INIT                 \ ___ forward ___

    [ here TO splash^ ]
    SPLASH                   \ ___ forward ___

    [ decimal      7 ] Literal emit
    
    abort
    ;

\   -2 ALLOT \ we can save two bytes because COLD starts

    
\ 74C3h
.( COLD )
: cold  ( -- )
    [ hex 12 +origin ] Literal    \ source for COLD start
    [ vars^          ] Literal @  
    [ decimal    6   ] Literal +    
    [ decimal   20   ] Literal    \ this includes voc-link, first and limit
    cmove
    
    [ hex 0C +origin ] Literal @  \ Latest
    [ ' forth >body 4 + ] Literal !  \

\ included in initial cmove
\   [ first @        ] Literal first !
\   [ limit @        ] Literal limit !

    0 nmode !

\   [ first @        ] Literal use   !
\   [ first @        ] Literal prev  !
    first @ dup
    use   !
    prev  !

    [ decimal      4 ] Literal place !

\   [ decimal      8 ] Literal     \ caps-lock on !
\   [ hex       5C6A ] Literal c!  \ FLAGS2       !
    
    2 hp !

    \ [ here TO xi/o^ ]      
    
    \ XI/O                   \ ___ forward ___
    
    [ here TO y^ ]
    warm
    noop
    ;

\    -2 ALLOT    \ we can save two bytes because COLD starts
 
    ' cold  y^ CELL+ !  \ this goes just after WARM ...
\                       \ ... so we can inc bc twice to get it later


\ 7530h
here cold^ ! \ patch
here warm^ ! \ patch

        ASSEMBLER 

        LDX     IX|    (next)   NN, 

        EXX
        PUSH    HL|                   \ saves HL' (of Basic)
        EXX

        LD()X   SP|    hex  08 +origin AA, \ saves SP
        LDX()   SP|    hex  12 +origin AA, \ forth's SP
        
\       LDN     A'|    1 N,
\       LD()A   hex 5C6B AA,   \ DF_SZ system variable

        LDHL()  hex  14 +origin AA, \ forth's RP
        LD()HL  hex 030 +origin AA,
        LDX     BC|    y^              NN, \ ... so BC is WARM, quick'n'dirty
        JRF    CY'|    HOLDPLACE \ IF,

        INCX    BC|
        INCX    BC|    \ ... so BC is COLD
        HERE DISP, \ THEN, 
        Next



\ 7450h
.( BASIC )
\ immediately quits to Spectrum BASIC 
\ see BYE 
CODE basic ( n -- )
        POP     BC|

\       LDN     A'|    2 N,
\       LD()A   hex 5C6B AA,   \ DF_SZ system variable

        LDX     HL|    0 NN,
        ADDHL   SP|
        LDX()   SP|    hex  08 +origin AA, \ retrieve SP just before...
        LD()HL  hex  08 +origin AA, \ ...saving Forth SP.

        EXX
        POP     HL|    \ retrieve Basic HL'
        EXX

        RET
        C;


\ copy the previously stored SP the new location (valid only once?!)
08 +ORIGIN @ 08 +origin !


\ 7563h
.( +- )
\ leaves n1 with the sign of n2 as n3.
: +-  ( n1 n2 -- n3 )
    0<
    If
        negate
    Then
    ;


\ 7574h
.( D+- )
\ leaves d1 with the sign of n as d2.
: d+-  ( d1 n -- d2 )
    0<
    If
        dnegate
    Then
    ;


\ 7586h
.( ABS )
: abs   ( n -- |n| )
    dup +-
    ;
    

\ 7594h
.( DABS )
: dabs   ( d -- |d| )
    dup d+-
    ;


\ 75A3h, 75B9h
\ MIN and MAX moved <<<


\ 75CFh
.( M* )
\ multiply two integer giving a double
: m*  ( n1 n2 -- d )
    2dup xor >r
    abs swap
    abs um*
    r> d+-
    ;


\ 75EAh
\ Symmetric division
\ divides a double into n giving quotient q and remainder r 
\ the remainder has the sign of dividend d.
.( SM/REM )
: sm/rem  ( d n -- r q ) 
    over >r >r              \ d     R: h n
    dabs r@ abs um/mod      \ r q
    r>                      \ r q n
    r@ xor +- swap          \ +q r
    r>     +- swap          \ +r +q
    ;


.( FM/MOD )
\ Floored division
\ divides a double into n giving quotient q and remainder r 
\ the remainder has the sign of the divisor n.
: fm/mod  ( d n -- r q ) 
    dup >r                    \ d n      R: n
    sm/rem                    \ r q
    over dup                  \ r q r r
    0= 0= swap 0<             \ r q  r!=0  r<0
    r@ 0< xor and             \ r q  (r!=0 & r<0^n<0)
    If 
        1- swap r> + swap     \ r+n q-1  
    Else 
        r> drop               \ r q
    Then
    ;


.( M/MOD )
\ Mixed operation. It leaves the remainder n2 and the quotient n3 of the 
\ integer division of a double integer d by the divisor n1. 
: m/mod 
    sm/rem
    \ if you want floored division use fm/mod instead of sm/rem
    \ if you want simmetric division use sm/rem instead of fm/mod
    ;


.( M/ )
\ Mixed operation. It leaves the quotient n2 of the integer division 
\ of a double integer d by the divisor n1.
: m/ ( d n -- n )
    m/mod nip 
    ;


\ 7611h
.( * )
\ multiply two integer
: *  ( n1 n2 -- n3 )
    m* drop
    ;
    

\ 761Dh
.( /MOD )
\ leaves quotient n4 and remainder n3 of the integer division n1 / n2.
\ the remainder has the sign of n1.
: /mod  ( n1 n2 -- n3 n4 )
    >r s>d r>
    m/mod 
    ;


\ 7630h
.( / )
\ quotient 
: /  ( n1 n2 -- n3 )
    /mod nip
    ; 


\ 763Eh
.( MOD )
\ remainder of n1 / n2 with the sign of n1.
: mod ( n1 n2 -- n3 )
    /mod drop
    ;
            

\ 764Ch
.( */MOD )
\ leaves the quotient n5 and the remainder n4 of the operation
\ (n1 * n2) / n3. The intermediate passage through a double number
\ avoids loss of precision
: */mod  ( n1 n2 n3 -- n4 n5 )
    >r  m*  r>  m/mod 
    ;
    

\ 7660h    
.( */ )
\ (n1 * n2) / n3. The intermediate passage through a double number
\ avoids loss of precision
: */  ( n1 n2 n3 --	n4 )
    */mod nip
    ;


\ 766Fh
\ .( #/MOD )
\ mixed operation: it leaves the remainder u3 and the quotient ud4 of ud1 / u1.
\ used by # during number representation.
\ : #/mod  ( ud1 u2 -- u3 ud4 )
\     >r           \ ud1
\     0 r@ um/mod  \ l rem1 h/r
\     r> swap >r   \ l rem1
\     um/mod       \ rem2 l/r
\     r>           \ rem2 l/r h/r
\     ;
    

\ 768Dh
." (LINE) " \ ___ forward ___ because of BLOCK
\ sends the line n1 of block n2 to the disk buffer.
\ it returns the address a and ca counter b = C/L meaning a whole line.
: (line)  ( n1 n2 -- a b )
    >r 
    noop
    c/l 
    b/buf */mod 
    r> 
    b/scr * + 

    [ here TO block2^ ]

    BLOCK          \ ___ forward ___
    + 
    noop 
    c/l 
    ;


\ 76B4h
.( .LINE )
\ Sends to output line  n1  of screen n2.
: .line  ( n1 n2 -- )
    (line) -trailing type 
    ;
    

\ 76C6h
.( MESSAGE )
\ prints error message to current channel.
\ if WARNING is 0, prints "MSG#n".
\ if WARNING is 1, prints line n of screen 4.
\ if WARNING is -1, see ERROR
\ value can be negative or beyond block 4.
\ RENAME message Message
: message
    warning @
    If
        \ ?dup
        \ If
            [ decimal 4 ] literal
            offset @
            b/scr / -
            .line
            space
        \ Then
    Else
        .( msg#)
        
        [ here TO .^ ]
        
        .             \ ___ forward ___
    Then
    ;
    
    ' message msg1^  !   \ patch error
    ' message msg2^  !   \ patch code / mcod

    
\ ______________________________________________________________________ 


\ \ 7824h
.( DEVICE )
\ used to save current device stream number (video or printer)
2 variable device        device !

\ 
\ ______________________________________________________________________ 


\ ______________________________________________________________________ 
\
\ NextZXOS option.


.( REG@ )
\ reads Next REGister n giving byte b
\ : reg@ ( n -- b )
\     [ hex 243B ] literal p!
\     [ hex 253B ] literal p@
\ ;

CODE reg@ ( n -- b )
        EXX
        LDX     BC| HEX 243B NN, 
        POP     HL|
        OUT(C)  L'|
        INC     B'|
        IN(C)   L'|
        PUSH    HL|
        EXX
        Next
        C;


.( REG! )
\ write value b to Next REGister n 
\ : reg! ( b n -- )
\     [ hex 243B ] literal p!
\     [ hex 253B ] literal p!
\ ;

CODE reg! ( b n -- )
        EXX
        LDX     BC| HEX 243B NN, 
        POP     HL|
        OUT(C)  L'|
        INC     B'|
        POP     HL|
        OUT(C)  L'|
        EXX
        Next
        C;


.( MMU7@ )
\ query current page in MMU7 8K-RAM : 0 and 223
: mmu7@ ( -- n )
    [ decimal 87 ] literal reg@
;


.( MMU7! )
\ set MMU7 8K-RAM page to n given between 0 and 223
\ optimized version that uses NEXTREG n,A Z80n op-code.
CODE mmu7! ( n -- )
        POP     HL|
        LD      A'|      L|
        NEXTREGA DECIMAL 87 P,   \ nextreg 87,a
        Next 
        C;


\ .( >FAR )
\ \ decode bits 765 of H as one of the 8K-page between 32 and 63 (20h-27h)
\ \ take lower bits of H and L as an offset from E000h
\ \ then return address  a  between E000h-FFFFh 
\ \ and page number n  between 64-71 (40h-47h)
\ \ For example, in hex: 
\ \   0000 >FAR  gives  20.E000
\ \   1FFF >FAR  gives  20.FFFF
\ \   2000 >FAR  gives  21.E000
\ \   3FFF >FAR  gives  21.FFFF
\ \   EFFF >FAR  gives  27.EFFF
\ \   FFFF >FAR  gives  27.FFFF
\ CODE >far ( ha -- a n )
\         POP     DE|
\         LD      A'|      D|
\         ANDN   HEX E0 N,
\         RLCA
\         RLCA
\         RLCA
\         ADDN    HEX 20 N,
\         LD      L'|      A|
\         LDN     H'|    HEX 00 N,
\         LD      A'|      D|
\         ORN    HEX E0 N,
\         LD      D'|      A|
\         PUSH    HL|
\         PUSH    DE|
\         Next
\         C;
\         
\ 
\ .( <FAR )
\ \ given an address E000-FFFF and a page number n (64-71 or 40h-47h)
\ \ reverse of >FAR: encodes a FAR address compressing
\ \ to bits 765 of H, lower bits of HL address offset from E000h
\ CODE <far ( a n -- ha )
\         POP     DE|         \ page number in E
\         POP     HL|         \ address in HL
\         LD      A'|      E|
\         SUBN    HEX   40 N,
\         RRCA
\         RRCA
\         RRCA
\         LD      D'|      A| \ bits 765 are saved on D 
\         LD      A'|      H| \ drops
\         ANDN   HEX   1F  N,
\         ORA      D|
\         LD      H'|      A|
\         PUSH    HL|
\         Next
\         C;        
        

.( M_P3DOS )
\ NextZXOS call wrapper.
\  n1 = hl or ix register parameter value
\  n2 = de register parameter value 
\  n3 = bc register parameter value
\  n4 =  a register parameter value
\   a = routine address in ROM 3
\ ---- 
\  n5 = hl returned value
\  n6 = de returned value 
\  n7 = bc returned value
\  n8 =  a returned value
\   f
\
CODE m_p3dos ( n1 n2 n3 n4 a -- n5 n6 n7 n8  f )
        POP     DE|         \ dos call entry address
        POP     HL|         \ a register argument
        LD      A'|    L|

        EXX
        POP     BC|         \ bc argument
        POP     DE|         \ de argument
        POP     HL|         \ hl argument
        EXX

        PUSH    BC| 
        PUSH    IX| 

\       LD()X   SP|    HEX 02C org^ +  AA, \ saves SP
\       LDX     SP|    HEX  -5 org^ +  NN, \ temp stack just below ORIGIN
        LDN     C'|    7   N,              \ use 7 RAM bank
        
        RST     08|    HEX 094  C,

\       LDX()   SP|    HEX 02C org^ +  AA, \ restore SP

\       PUSH    IX|
\       POP     HL|
\       LD()HL         HEX 02A org^ +  AA, \ saves away IX 
        LD()IX         HEX 02A org^ +  AA, \ saves away IX 

        POP     IX|         \ retrieve ix
        EX(SP)HL            \ hl argument and retrieve BC
        PUSH    DE|         \ de argument
        PUSH    BC|         \ bc argument

        LD      C'|    L|   \ restore BC register
        LD      B'|    H|

        LDN     H'|    0  N,  
        LD      L'|    A|
        PUSH    HL|
        
        SBCHL   HL|         \ -1 for OK ;  0 for KO but now
        INCX    HL|         \  0 for OK ;  1 for KO  
        PUSH    HL|
        Next
        C;        

\ file-handle to Block's file !Blocks-64.bin  
BLK-FH @ variable blk-fh         blk-fh !


\ create blk-fname ," test.bin"  
create blk-fname ," !Blocks-64.bin"  
here 18 dup allot erase


.( BLK-SEEK )

\ seek block n  within blocks!.bin  file
: blk-seek  ( n -- )
    b/buf m*
    blk-fh @
    f_seek
    [ hex 2D ]   Literal ?error
;


.( BLK-READ )
\ read block n to address a
: blk-read  ( a n -- )
    blk-seek
    b/buf
    blk-fh @
    f_read
    [ hex 2E ]   Literal ?error
    drop
;


.( BLK-WRITE )
\ write block n from address a
: blk-write  ( a n -- )
    blk-seek
    b/buf
    blk-fh @
    f_write 
    [ hex 2F ]   Literal ?error
    drop
;


.( BLK-INIT )
\ initialize block system
: blk-init  ( -- )
    blk-fh @ f_close drop  \ ignore error
    blk-fname 1+
    here 3 f_open          \ open for update  (read+write)
    [ hex 2C ]   Literal ?error
    blk-fh !
;

    ' blk-init  xi/o2^ !   \ patch 


\ ______________________________________________________________________ 


\ 7946h    
\  number of blocks available
decimal #SEC constant #sec


\ 7951h
.( R/W )
\ read/write block n depending on flag f
\ true-flag means read, false-flag means write.
: r/w  ( a n f -- )
    >r
    1-  dup 0<           
           over #sec  1-  > 
        or [ decimal 6 ] Literal ?error
    r> 
    If
            blk-read
    Else
            blk-write
    Then
    ;


\ 7985h
.( +BUF )
\ advences to next buffer, cyclical rotating along them
: +buf  ( a1 -- a2 f )
    [ decimal 516 ] Literal +
    dup limit @ =
    If
        drop first @ 
    Then
    dup prev @ -
    ;


\ 79b0h
.( UPDATE )
\ mark the last block to be written to disk
: update  ( -- )
    prev @ @ 
    [ hex 8000 ] Literal or
    prev @ !
    ;


\ 79cfh
.( EMPTY-BUFFERS )
: empty-buffers
    first @ limit @ over - erase
    ;


\ 79f1h
.( BUFFER )
\ read block n and gives the address to a buffer 
\ any block previously inside the buffer, if modified, is rewritten to
\ disk before reading the block n.
: buffer  ( n -- a )
    use @   
    dup >r   
    Begin 
        +buf 
    Until 
    use !  
    r@ @ 0< 
    If  
        r@ cell+  
        r@ @ [ hex 7FFF ] Literal and  
        0 r/w  
    Then
    r@ !  
    r@ prev !  
    r>  cell+ 
    ;


\ 7a3ah
.( BLOCK )
\ Leaves the buffer address that contains the block n. 
\ If the block is not already present, it will be loaded from disk
\ The block previously inside the buffer, if modified, is rewritten to
\ disk before reading the block n.
\ See also BUFFER, R/W, UPDATE, FLUSH.
: block  ( n -- a )
    offset @ + >r 
    prev @  
    dup @  r@ - dup +   \ check equality without most significant bit
    If  
        Begin  
            +buf 0=  
            If  
                drop 
                r@ buffer dup 
                r@ 1  r/w  2- 
            Then
            dup @ r@ - dup +  0= 
        Until
        dup prev ! 
    Then
    r> drop cell+
    ;  
    
    ' block block^  !  \ patch
    ' block block2^ !  \ patch


\ 7a9ah
.( #BUFF )
LIMIT @ FIRST @ - decimal 516 / constant #buff


\ 7aa6h
.( FLUSH )
: flush
    #buff 1+ 0 
    Do
        0 buffer drop
    Loop
    blk-fh @ f_sync drop
    ;
    

.( F_GETLINE )
\ Given an open filehandle read at most  m  characters to get next line
\ terminated with $0D or $0A.
\ n is the actual number of byte read, that is the length of line.
\ Buffer must be m bytes long to accommodate a trailing 0x00 at m-th byte.
decimal
: f_getline ( a m fh -- n )
    >r tuck                                     \ m a m         R: fh
    r@ f_fgetpos [ 44 ] Literal ?error          \ m a m  d
    2swap                                       \ m  d  a m
    over 1+                                     \ m  d  a m a+1
    swap                                        \ m  d  a a+1 m 
    r@ f_read [ 46 ] Literal ?error             \ m  d  a k 
    If \ at least 1 chr was read                \ m  d  a k
        [ 10 ] Literal enclose                  \ m  d  a n1 b n3
        drop nip swap                           \ m  d  b a 
        [ 13 ] Literal enclose                  \ m  d  b a n1 c n3  
        drop nip rot                            \ m  d  a c b
        min                                     \ m  d  a n
        dup span !                              \ m  d  a
        dup >r                                  \ m  d  a n       R: fh n
        2swap r>                                \ m a n  d   n    R: fh
        0 d+                                    \ m a n d+n
        r> f_seek [ 45 ] Literal ?error         \ m a n
    Else                                        \ m  d  a
        r> 2swap                                \ m a fh  d 
        2drop drop                              \ m a 
        0                                       \ m a 0
    Then
    >r                                          \ m a             R: n|0
    dup dup 1+ swap                             \ m a a+1 a
    r@ cmove                                    \ m a
    2dup +                                      \ m a m+a
    0 swap cell- !                              \ m a
    r@ + 1-                                     \ m a+n-1
    swap r@ -                                   \ a+n-1 m-n
    blanks 
    r>                                          \ n|0
;


.( F_INCLUDE )
\ Given a filehandle includes the source from file
decimal
: f_include  ( fh -- )
    \ it first saves current loading status (BLK, >IN, SOURCE-ID)
    blk @ >r  
    >in @ >r  
    source-id @ >r 

    \ if SOURCE-ID was non zero (i.e. this is a recursed F_INCLUDE)
    \ try to save its position and close the file-handle.
    r@ 
    If 
        r@ f_fgetpos [ 44 ] Literal ?error 
        \ must rewind to the beginning of the current line
        >in @ 2-  span @  -  s>d d+
    Else 
        0 0         \ 0 0 fake handle-position
    Then 
    >r >r           \ save previous (double) handle-position if any...
    
    source-id !     \ this use the  fh  passed parameter (at last)

    \ read text from file using  block #1 as a temporary buffer.
    Begin
        1 block 
        b/buf 2dup blanks           
        swap 1+ 
        swap cell-
        source-id @ 
        f_getline     \ a source text line can be up to 510 characters
      \ cr 1 block over type  \ during code-debugging phase
    While             \ stay in loop while there is text to be read
        1 blk ! 0 >in !  
        interpret
    Repeat

    \ close current file
    source-id @  
    0 source-id !  
    f_close [ 42 ] Literal ?error

    \ restore previous Handle-position
    r> r> 
    \ restore SOURCE-ID
    r>   
    dup source-id !
    If 
        source-id @ f_seek [ 43 ] Literal ?error 
    Else 
        2drop       \ ignore 0 0 fake handle-position.
    Then
    \ restore >IN, BLK
    r> >in !  
    r> blk !
;


.( OPEN< )
\ Open the following filename and return it file-handle
\ Used in the form OPEN CCCC
decimal
: open< ( -- fh )
    bl
    word count over + 0 swap !
    pad 1 f_open [ 43 ] Literal ?error
;


.( INCLUDE )
\ Include the following filename
decimal
: include  ( -- cccc )
    open<
    dup f_include
    f_close drop
;


.( NEEDS )
\ check for cccc exists in vocabulary
\ if it doesn't then  INCLUDE  inc/cccc.F
decimal
\ temp filename cccc.f as counted string zero-padded
create   needs-w     35 allot   \ 32 + .f + 0x00 = len 35
needs-w 35 erase
\ temp complete path+filename
create   needs-fn    40 allot
needs-fn 40 erase
\ constant paths
create   needs-inc   ," inc/"
create   needs-lib   ," lib/"


\ Concatenate path at a and filename and include it
\ No error is issued if filename doesn't exist.
decimal
: needs/  ( a -- )              \ a is address of Path passed
    count tuck                    \ n a n
    needs-fn swap cmove           \ n       \ Path
    needs-fn +                    \ a1+n    \ concat
    needs-w 1+ swap [ 35 ] Literal  
    cmove                         \         \ Filename
    needs-fn                      \ a3
    pad 1 f_open
    0=
    If 
        f_include
    Else 
    \   needs-w count type space
    \   [ 43 ] Literal message 
        drop
    Then
;

( map-into )
(   \ : ? / * | \ < > "    )
(   \ _ ^ % & $ _ { } ~    )

\ create ndom hex    (   \ : ? / * | \ < > "   )
\     3A C,  3F C,  2F C,  2A C,  7C C,  5C C,  3C C,  3E C,  22 C,
create ndom hex    (   : ? / * | \ < > "   )
    char : c,  char ? c,  char / c,  char * c, 
    char | c,  char \ c,  char < c,  char > c,  char " c,

\ create ncdm hex    (   \ _ ^ % & $ _ { } ~   )
\     5F C,  5E C,  25 C,  26 C,  24 C,  5F C,  7B C,  7D C,  7E C,
create ncdm hex    (   _ ^ % & $ _ { } ~   )
    char _ c,  char ^ c,  char % c,  char & c,  
    char $ c,  char _ c,  char { c,  char } c,  char ~ c,


\ Replace illegal character in filename 
decimal
: needs-ch ( a -- )
    count bounds
    Do
        ncdm ndom [ 9 ] Literal i c@ (map) i c!
    Loop
;


\ include  "path/cccc.f" if cccc is not defined
\ filename cccc.f is temporary stored at NEEDS-W
decimal 
: needs-f  ( a -- )
    -find If
        drop 2drop
    Else
        needs-w    [ 35 ] literal  
        erase                           \ a
        here c@ 1+ here over            \ a n here n
        needs-w    swap cmove           \ a n
        needs-w    needs-ch
        needs-w    +                    \ a a1+n
        [ hex 662E decimal ] literal    \ a a1+n ".F"
        swap !                          \ a
        needs/
    Then 
;


\ check for cccc exists in vocabulary
\ if it doesn't then  INCLUDE  inc/cccc.f searching in inc subdirectory
\ when file is not found, gives a 2nd chance with  lib/cccc.f
decimal
: needs
    >in @ dup
    needs-inc needs-f     \ search in "inc/"
    >in !                 \ re-feed it
    needs-lib needs-f     \ 2nd chance at "lib/"
    >in !                 \ re-feed it
    -find If
        2drop
    Else 
        needs-w count type space
        [ 43 ] Literal message 
    Then 
;


\ 7ac4h    
.( LOAD+ )
: load+  ( n -- )
    blk @  >r  
    >in  @  >r
    
    0 >in ! 
    b/scr * blk ! 
    interpret
    
    r> >in !
    r> blk !
    ;


\ 7af7h    
.( --> )
: -->  ( -- )
    ?loading 
    0 >in ! 
    b/scr   \ z
    blk @   \ z b
    over    \ z b z
    mod     \ z (b mod z)
    -       \ z - (b mod z)
    blk +!
    ;
    immediate


\ 7b19h
.( ' )
: '  ( -- cfa )  ( N.B. no more pfa )
    -find \ cfa b f 
    0= 0 ?error
    drop 
    ;


\ 7b2dh
.( FORGET )
: forget  ( -- )
    current @ 
    context @ 
        - [ decimal 23 ] Literal ?error
    '   >body
        dup fence @ u< 
        [ decimal 21 ] Literal ?error
    dup nfa dp ! 
    lfa @ context @ !
    ;


.( MARKER )
: marker ( -- ccc )
    <builds
        voc-link        @ ,
        current         @ ,
        context         @ ,
        latest            , \ dp
        latest pfa lfa  @ ,
    does>
        dup @ voc-link  ! cell+ 
        dup @ current   ! cell+
        dup @ context   ! cell+
        dup @ dp        ! cell+
            @ current @ !
; immediate


\ 7c8fh
.( SPACES )
: spaces  ( n -- )
    0 max 
    0 ?Do space Loop
    ;


\ 7cb0h
.( <# )
: <#    ( -- ) 
    pad hld !
    ;


\ 7cbf
.( #> )
: #>    
    2drop
    hld @ pad over -
    ;


\ 7cd4
.( SIGN )
: sign    ( n d -- d )
    rot 0<
    If
        [ decimal 45 ] Literal hold
    Then
    ;


\ 7ced
.( # )
: #   ( d1 -- d2 )
    base @ 

    \ #/mod 
    >r           \ ud1
    0 r@ um/mod  \ l rem1 h/r
    r> swap >r   \ l rem1
    um/mod       \ rem2 l/r
    r>           \ rem2 l/r h/r

    rot  
    [ 9 ] Literal over <
    If [ 7 ] Literal + Then    
    [ decimal 48 ] Literal 
    + hold
    ;


\ 7d17
.( #S )
: #s  ( d1 -- d2 )
    Begin
        #
        2dup
        or 0=
    Until    
    ;


\ 7d2c
.( D.R )
: d.r    ( d n -- )
    >r
    tuck dabs 
    <# #s sign #> 
    r>
    over - spaces
    type
    ;


\ 7d50
.( .R )
: .r
    >r  s>d  r>
    d.r
    ;


\ 7d61
.( D. )
: d.
    0 d.r space
    ;


\ 7d70
.( . )
: .    
    s>d  d.
    ;
    
    ' . .^ ! \ patch



\ 7d7c
.( ? )
: ?
    @ .
    ;


\ 7d88
.( U. )
: u.
    0 d.
    ;


\ 7d95
\ WORDS 
.( WORDS )
: words  ( -- )
    [ decimal 128 ] Literal out !
    context @ @
    Begin
        dup c@ [ hex 1F ] Literal and  
        out @ +  
        c/l < 0=
        If 
            cr 
            0 out ! 
        Then
        dup id.
        pfa lfa @ 
        dup 0= 
        ?terminal or 
    Until
    drop
    ;


\ 7ddd
.( LIST )
: list   ( n -- )
    decimal cr 
    dup scr !
    .( Scr# ) .
    \ [ decimal 16 ] Literal 0   \ <-- 
    l/scr 0
    Do
        cr 
        i 3 \ [ decimal 3 ] Literal  
        .r space 
        i scr @ .line
        ?terminal If 
            leave 
        Then
    Loop
    cr
    ;


\ 7e29
.( INDEX )
: index    ( n1 n2 -- )
\   [ decimal 6 ] Literal emitc
    1+ swap
    Do
        cr i 3 \ [ decimal 3 ] Literal
        .r space
        0 i .line 
        ?terminal If
            leave 
        Then
    Loop
    cr
    ;


\ 7e61
\ .CPU
\ : .cpu
\     base @
\     [ decimal 36 ] Literal base !
\     [ hex 10     ] Literal +origin @ u.
\     base !
\     ;


\ 7e86
.( CLS or PAGE )
\ CODE cls 
\ Chr$ 14 is NextZXOS version CLS (LAYER0 don't work this way, though)
: cls 
    [ hex 0E ] Literal emitc
;    


\ 7e96
.( SPLASH )
: splash
    cls
    [compile] (.")
    [ decimal 88 here ," v-Forth 1.52 NextZXOS version" -1 allot ]
    [ decimal 13 here ," Direct Threaded - build 20220508" -1 allot ]
    [ decimal 13 here ," 1990-2022 Matteo Vitturi" -1 allot ]
    [ decimal 13 c, c! c! c! ] 
    ;

    ' splash splash^ ! \ patch 


\ 7ecb
\ XI/O
\ : xi/o
\     0 channel !
\     0 mmap !
\     [ decimal 4 ] Literal mdr
\     ;
\ 
\     ' xi/o  xi/o^  ! \ patch 
\     ' xi/o  xi/o2^ ! \ patch 


\ \ 7ee8
\ \ PRINTER
\ : printer 
\     [ decimal 3 ] Literal 
\     dup device ! select
\     ;


\ 7f00
.( VIDEO )
: video
    2 
    dup device ! select
    ;


.( ACCEPT- )
\ accepts at most n1 characters from current channel/stream
\ and stores them at address a.
\ returns n2 as the number of read characters.
: accept- ( a n1 -- n2 )
    >r    ( a )
    0     ( a n2 as the final counter )
    swap  ( n2 a )
    dup   ( n2 a a )
    r>    ( n2 a a n1 )
    +     ( n2 a n1+a )
    swap  ( n2 n1+a a )
    Do    ( n2 )
        mmu7@ ( n2 page )
        inkey ( n2 page c )
        swap mmu7! ( n2 c )
        dup 0= If video quit Then
        dup [ decimal 13 ] literal = If drop 0 Then \ Then
        dup [ decimal 10 ] literal = If drop 0 Then \ Then
        \ dup  0=  If 
        \     lastl
        \ Then \ Then
        i c! ( n2 )
        1+ ( increment n2 )
        i c@ 0= If leave Then
    Loop  ( n2 )
    ;


.( LOAD- )
\ Provided that a stream n is OPEN# via the standart BASIC 
\ it accepts text from stream #n to the normal INTERPRET 
\ up to now, text-file must end with QUIT 
: load- ( n -- )
    source-id ! 
    Begin
        tib @                        ( a )
        dup [ decimal 80 ] literal   ( a a n )
        2dup blanks                  ( a a n )
        source-id @ abs dup device ! select  \ was printer
        accept-                      ( a n2 )
        video 
        \ type cr
        2drop
        0 blk !
        0 >in !
        interpret
        ?terminal  
    Until         \ Again
;


.( LOAD )
\ if n is positive, it loads screen #n (as usual)
\ if n is negative, it connects stream #n to the normal INTERPRET 
\ this second way is useful if you want to load any kind of file
\ provied that it is OPEN# the usual BASIC way.
: load ( n -- )
    dup 0< 
    If
        load-
    Else
        load+
    Then
    ;


.( AUTOEXEC )
\ this word is called the first time the Forth system boot to
\ load Screen# 1. Once called it patches itself to prevent furhter runs.
: autoexec
    [ decimal 10 0 +origin 32768 u< 1 and + ] Literal  \ this give 10 or 11 
    [ ' noop         ] Literal  
    [ autoexec^      ] Literal  !  \ patch autoexec-off
    load
    quit
    ;
    ' autoexec autoexec^ ! \ patch autoexec-on in ABORT


.( BYE )
: bye ( -- )
    flush
    empty-buffers
    blk-fh @ f_close drop  \ ignore error
    0 +origin 
    basic
    ;
    -2 ALLOT    \ we can save two bytes because BASIC quits to BASIC.


\ \ INVV
\ : invv ( -- )
\     [ decimal 20 ] Literal emitc
\     1 emitc
\     ;
\     
\ 
\ \ TRUV
\ : truv ( -- )
\     [ decimal 20 ] Literal emitc 
\     0 emitc
\     ;
    

\ \ MARK
\ : mark ( a n -- )
\     invv type truv
\     ;


.( BACK )
: back
    here - ,
    ;


.( IF ... THEN )
.( IF ... ELSE ... THEN )
: if    ( -- a 2 ) \ compile-time 
    compile 0branch
    here 0 , 
    2 
    ; 
    immediate


.( THEN )
: then ( a 2 -- ) \ compile-time 
    ?comp
    2 ?pairs  
    here over - swap ! 
    ; 
    immediate
    

.( ENDIF )
: endif ( a 2 -- ) \ compile-time 
    [compile] then 
    ; 
    immediate


.( ELSE )
: else ( a1 2 -- a2 2 ) \ compile-time 
    ?comp
    2 ?pairs  
    compile branch
    here 0 , 
    swap 2 [compile] then
    2 
    ; 
    immediate


.( BEGIN ... AGAIN )
.( BEGIN ... f UNTIL )
.( BEGIN ... f WHILE ... REPEAT )
: begin     ( -- a 1 ) \ compile-time  
    ?comp 
    here 
    2
    ; 
    immediate


.( AGAIN )
: again     ( a 1 -- ) \ compile-time 
    ?comp
    2 ?pairs 
    compile branch
    back 
    ; 
    immediate


.( UNTIL )
: until     ( a 1 -- ) \ compile-time 
    ?comp
    2 ?pairs
    compile 0branch
    back 
    ; 
    immediate


.( END )
: end       ( a 1 -- ) \ compile-time 
    [compile] until ; immediate


.( WHILE )
: while     ( a1 1 -- a2 4 a1 1 ) \ compile-time
    [compile] if \ 2+
    2swap
    ; 
    immediate


.( REPEAT )
: repeat    ( a2 4 a 2 -- ) \ compile-time
    [compile] again
    \ 2-
    [compile] then
    ; 
    immediate


.( ?DO- )
\ peculiar version of BACK fitted for ?DO and LOOP
: ?do-
    back
    Begin
        sp@ csp @ -
        \ dup 0= 
    While
        2+ [compile] then 
    Repeat 
    ?csp csp !      
    ;


.( DO  ... LOOP )
.( DO  ... n +LOOP )
.( ?DO ... LOOP )
.( ?DO ... n +LOOP )
: do        ( -- a 3 ) \ compile-time
    compile (do)
    csp @ !csp
    here 3 
    ; 
    immediate


.( LOOP )
: loop      ( a 3 -- ) \ compile-time
    3 ?pairs 
    compile (loop) 
    ?do- \ back
    ; 
    immediate


.( +LOOP )
: +loop     ( a 3 -- ) \ compile-time
    3 ?pairs 
    compile (+loop) 
    ?do- \ back
    ; 
    immediate


.( ?DO )
: ?do        ( -- a 3 ) \ compile-time
    compile (?do)
    csp @ !csp
    here 0 , 0
    here 3
    ; 
    immediate


\ 7fa0 new
.( \ )
\ the following text is interpreted as a comment until end-of-line
: \ 
    blk @ 
    If
        blk @ 1 >  \ BLOCK 1 is used as temp-line in INCLUDE file.
        If
            >in @ c/l mod c/l swap - >in +!
        Else
            b/buf cell- >in !
        Then
    Else
        [ decimal 80 ] Literal  >in !
    Then
    ;
    immediate


\ .( RENAME )
\ \ special utility to rename a word to another name but same length
\ : rename  ( -- "ccc" "ddd" )
\     ' >body nfa
\     dup c@  [ hex 1F ] Literal  and
\     2dup + 
\     >r
\         bl word       [ hex 20 ] Literal  allot
\         count  [ hex 1F ] Literal  and rot min
\         >r 
\             swap 1+
\         r>
\         cmove
\         r@  c@  [ hex 80 ] Literal  or
\     r>      
\     c!
\     [ hex -20 ] Literal allot
\ ;


\ ______________________________________________________________________ 

\ patch for fence and latest


here       fence !   
here       hex 01C +origin !  \ FENCE
latest     hex 00C +origin !  \ LATEST word used in COLD start
here       hex 01E +origin !  \ set cold-DP
voc-link @ hex 020 +origin !  \ set cold-VOC-LINK
' noop asm^ !

forth definitions

\ ______________________________________________________________________ 

\ this is a final patch to all 'RP-address' references
\ all these address were collected using !rp^ word
\ once used, this word can be forgotten.
CODE final_rp_patch
        PUSH    BC|
        
        LDX     HL|    rp#^ @  NN,
        LDX     DE|    rp#     NN,
        ANDA     A|
        SBCHL   DE|
        LD      B'|    L|
        SRA      B|
        LDX     HL|    rp#  NN, 
        
        HERE \ BEGIN,
            LD      E'| (HL)|
            INCX    HL|
            LD      D'| (HL)| 
            INCX    HL|
            PUSH    HL|
            EXDEHL
            LDX     DE|    hex 030 +origin  NN,  \ NEW ADDRESS.
            LD   (HL)'|    E|
            INCX    HL|
            LD   (HL)'|    D|
            POP     HL|
        DJNZ    HOLDPLACE SWAP DISP, \ pops second HERE
        
        POP     BC|
        Next
        C;

\ ______________________________________________________________________ 


\ RENAME   to             TO
\ RENAME   value          VALUE
\ RENAME   rename         RENAME 
.( RENAME   \              \  )

RENAME   ?do            ?DO
RENAME   +loop          +LOOP
RENAME   loop           LOOP
RENAME   do             DO
RENAME   ?do-           ?DO- 
RENAME   repeat         REPEAT
RENAME   while          WHILE
RENAME   end            END
RENAME   until          UNTIL
RENAME   again          AGAIN
RENAME   begin          BEGIN
RENAME   else           ELSE
RENAME   then           THEN
RENAME   endif          ENDIF 
RENAME   if             IF
RENAME   back           BACK
\ RENAME   mark           MARK
\ RENAME   truv           TRUV
\ RENAME   invv           INVV
RENAME   bye            BYE
RENAME   autoexec       AUTOEXEC 
RENAME   load           LOAD
RENAME   load-          LOAD-
RENAME   accept-        ACCEPT-
\ RENAME   rsload         RSLOAD
\ RENAME   rquery         RQUERY
\ RENAME   rexpect        REXPECT

RENAME   video          VIDEO
\ RENAME   printer        PRINTER        
\ RENAME   xi/o           XI/O
RENAME   splash         SPLASH
RENAME   cls            CLS
RENAME   index          INDEX
RENAME   list           LIST
RENAME   words          WORDS
RENAME   u.             U.
RENAME   ?              ?
RENAME   .              .
RENAME   d.             D.
RENAME   .r             .R
RENAME   d.r            D.R
RENAME   #s             #S
RENAME   #              #
RENAME   sign           SIGN
RENAME   #>             #>
RENAME   <#             <#
RENAME   spaces         SPACES
RENAME   forget         FORGET
RENAME   marker         MARKER
RENAME   '              '
RENAME   -->            -->
RENAME   load+          LOAD+
RENAME   needs          NEEDS 
RENAME   needs-f        NEEDS-F
RENAME   needs-ch       NEEDS-CH
RENAME   ndom           NDOM
RENAME   ncdm           NCDM
RENAME   needs/         NEEDS/
RENAME   needs-lib      NEEDS-LIB
RENAME   needs-inc      NEEDS-INC
RENAME   needs-fn       NEEDS-FN
RENAME   needs-w        NEEDS-W
RENAME   include        INCLUDE
RENAME   open<          OPEN<
RENAME   f_include      F_INCLUDE
RENAME   f_getline      F_GETLINE
RENAME   flush          FLUSH
RENAME   #buff          #BUFF
RENAME   block          BLOCK
RENAME   buffer         BUFFER
RENAME   empty-buffers  EMPTY-BUFFERS
RENAME   update         UPDATE
RENAME   +buf           +BUF
RENAME   r/w            R/W
RENAME   #sec           #SEC
\
RENAME   blk-init       BLK-INIT
RENAME   blk-write      BLK-WRITE
RENAME   blk-read       BLK-READ
RENAME   blk-seek       BLK-SEEK
RENAME   blk-fname      BLK-FNAME
RENAME   blk-fh         BLK-FH
\
RENAME   m_p3dos        M_P3DOS
\ RENAME   <far           <FAR
\ RENAME   >far           >FAR
RENAME   mmu7@          MMU7@
RENAME   mmu7!          MMU7!
RENAME   reg!           REG!
RENAME   reg@           REG@
\ RENAME   select         SELECT
\ RENAME   inkey          INKEY 
\
RENAME   device         DEVICE
RENAME   message        MESSAGE
RENAME   .line          .LINE
RENAME   (line)         (LINE)
\ RENAME   #/mod          #/MOD
RENAME   */             */
RENAME   */mod          */MOD
RENAME   mod            MOD
RENAME   /              /
RENAME   /mod           /MOD
RENAME   *              *
RENAME   m/             M/ 
RENAME   m/mod          M/MOD 
RENAME   fm/mod         FM/MOD
RENAME   sm/rem         SM/REM 
RENAME   m*             M*
RENAME   dabs           DABS
RENAME   abs            ABS
RENAME   d+-            D+-
RENAME   +-             +-
RENAME   s>d            S>D
RENAME   basic          BASIC
RENAME   cold           COLD
RENAME   warm           WARM
RENAME   abort          ABORT
\ RENAME   .cpu           .CPU
RENAME   quit           QUIT
RENAME   (              (
( )
RENAME   definitions    DEFINITIONS
RENAME   forth          FORTH
RENAME   vocabulary     VOCABULARY
RENAME   interpret      INTERPRET
RENAME   ?stack         ?STACK
RENAME   [char]         [CHAR]
RENAME   dliteral       DLITERAL
RENAME   literal        LITERAL
RENAME   [compile]      [COMPILE]
RENAME   create         CREATE
RENAME   mcod           CODE        \ be careful on this
RENAME   id.            ID.
RENAME   error          ERROR
RENAME   (abort)        (ABORT)
RENAME   -find          -FIND
RENAME   number         NUMBER

\ RENAME   (exp)          (EXP) 
\ RENAME   (frac)         (FRAC) 
\ RENAME   (intg)         (INTG) 
\ RENAME   fint           FINT  
\ RENAME   fminus         FMINUS
\ RENAME   f/mod          F/MOD 
\ RENAME   f+             F+    
\ RENAME   f/             F/    
\ RENAME   f*             F*    
\ RENAME   fop            FOP   
\ RENAME   w>             W>    
\ RENAME   >w             >W    

RENAME   (number)       (NUMBER)
RENAME   (sgn)          (SGN) 
RENAME   .(             .(    
( )
RENAME   ."             ."    
RENAME   .c             .C    
RENAME   ,"             ,"
RENAME   char           CHAR  
RENAME   (.")           (.")  
RENAME   word           WORD  
RENAME   pad            PAD   
RENAME   hold           HOLD
RENAME   blanks         BLANKS
RENAME   erase          ERASE 
RENAME   fill           FILL  
RENAME   query          QUERY 
\ RENAME   expect         EXPECT
RENAME   accept         ACCEPT
RENAME   -trailing      -TRAILING
RENAME   leave          LEAVE
RENAME   type           TYPE  
RENAME   bounds         BOUNDS  
RENAME   count          COUNT 
RENAME   does>          DOES> 
\ RENAME   recurse        RECURSE
RENAME   <builds        <BUILDS
RENAME   ;code          ;CODE  
RENAME   (;code)        (;CODE)
RENAME   decimal        DECIMAL
RENAME   hex            HEX    
RENAME   immediate      IMMEDIATE
RENAME   smudge         SMUDGE
RENAME   ]              ]
RENAME   [              [
RENAME   compile,       COMPILE,   
RENAME   compile        COMPILE 
RENAME   ?loading       ?LOADING
RENAME   ?csp           ?CSP  
RENAME   ?pairs         ?PAIRS
RENAME   ?exec          ?EXEC 
RENAME   ?comp          ?COMP 
RENAME   ?error         ?ERROR
RENAME   !csp           !CSP  
RENAME   <name          <NAME 
RENAME   >body          >BODY 
RENAME   pfa            PFA   
RENAME   nfa            NFA   
RENAME   cfa            CFA   
RENAME   lfa            LFA   
RENAME   latest         LATEST
RENAME   traverse       TRAVERSE
RENAME   space          SPACE
RENAME   emit           EMIT 
RENAME   ?dup           ?DUP 
RENAME   -dup           -DUP 
RENAME   max            MAX  
RENAME   min            MIN  
RENAME   >              >    
RENAME   u<             U<   
RENAME   <              <    
RENAME   =              =    
RENAME   -              -    
RENAME   c,             C,   
RENAME   ,              ,    
RENAME   allot          ALLOT
RENAME   here           HERE 
RENAME   hp             HP 
RENAME   handler        HANDLER 
RENAME   span           SPAN 
RENAME   source-id      SOURCE-ID
RENAME   place          PLACE
RENAME   lp             LP   
RENAME   prev           PREV 
RENAME   use            USE  
RENAME   hld            HLD  
RENAME   r#             R#   
RENAME   csp            CSP  
RENAME   fld            FLD  
RENAME   dpl            DPL  
RENAME   base           BASE 
RENAME   state          STATE
RENAME   current        CURRENT
RENAME   context        CONTEXT
RENAME   offset         OFFSET 
RENAME   scr            SCR 
RENAME   out            OUT 
RENAME   >in            >IN  
RENAME   blk            BLK 
RENAME   nmode          NMODE
RENAME   exp            EXP  
RENAME   limit          LIMIT
RENAME   first          FIRST
RENAME   voc-link       VOC-LINK
RENAME   dp             DP   
RENAME   fence          FENCE
RENAME   warning        WARNING
RENAME   width          WIDTH
RENAME   tib            TIB
RENAME   r0             R0 
RENAME   s0             S0 
RENAME   (next)         (NEXT)
RENAME   +origin        +ORIGIN
RENAME   l/scr          L/SCR
RENAME   b/scr          B/SCR 
RENAME   b/buf          B/BUF 
RENAME   c/l            C/L
RENAME   bl             BL 
\ RENAME   pi             PI 
RENAME   -1             -1 
RENAME   3              3  
RENAME   2              2  
RENAME   1              1  
RENAME   0              0  

RENAME   user           USER 
\ RENAME   2variable      2VARIABLE
\ RENAME   2constant      2CONSTANT
RENAME   variable       VARIABLE
RENAME   constant       CONSTANT
RENAME   noop           NOOP
RENAME   ;              ;   
RENAME   :              :   
\ RENAME   Message        MESSAGE
\ RENAME   Create         CREATE 
\ RENAME   call#          CALL#
RENAME   cells          CELLS  
RENAME   rshift         RSHIFT 
RENAME   lshift         LSHIFT 
RENAME   2/             2/     
RENAME   2*             2*     
\ RENAME   bank!          BANK! 
RENAME   p!             P!     
RENAME   p@             P@     
RENAME   2!             2!     
RENAME   c!             C!     
RENAME   !              !      
RENAME   2@             2@     
RENAME   c@             C@     
RENAME   @              @      

RENAME   toggle         TOGGLE
RENAME   +!             +!    
\ RENAME   2rot           2ROT  
RENAME   2dup           2DUP  
RENAME   2swap          2SWAP 
RENAME   2drop          2DROP 
\ RENAME   2over          2OVER 
\ RENAME   roll           ROLL  
RENAME   pick           PICK  
RENAME   -rot           -ROT   
RENAME   rot            ROT   
RENAME   dup            DUP   
RENAME   swap           SWAP  
RENAME   tuck           TUCK  
RENAME   nip            NIP  
RENAME   drop           DROP  
RENAME   over           OVER  
RENAME   dnegate        DNEGATE
RENAME   negate         NEGATE 
RENAME   cell-          CELL-  
RENAME   2-             2- 
\ RENAME   align          ALIGN 
RENAME   cell+          CELL+  
RENAME   2+             2+ 
RENAME   1-             1- 
RENAME   1+             1+ 
RENAME   d+             D+ 
RENAME   +              +  
RENAME   0>             0> 
RENAME   0<             0< 
RENAME   not            NOT
RENAME   0=             0= 
\ RENAME   r              R 
RENAME   r@             R@
RENAME   r>             R> 
RENAME   >r             >R 
\ RENAME   lastl          LASTL
RENAME   exit           EXIT  
RENAME   rp!            RP! 
RENAME   rp@            RP@ 
RENAME   sp!            SP! 
RENAME   sp@            SP@ 
RENAME   xor            XOR 
RENAME   or             OR  
RENAME   and            AND 
RENAME   um/mod         UM/MOD
RENAME   um*            UM*   
RENAME   cmove>         CMOVE>
RENAME   cmove          CMOVE 
RENAME   cr             CR    
RENAME   f_readdir      F_READDIR
RENAME   f_opendir      F_OPENDIR
RENAME   f_open         F_OPEN
RENAME   f_write        F_WRITE
RENAME   f_read         F_READ
RENAME   f_fgetpos      F_FGETPOS
RENAME   f_sync         F_SYNC
RENAME   f_close        F_CLOSE
RENAME   f_seek         F_SEEK
RENAME   select         SELECT
RENAME   inkey          INKEY 
RENAME   ?terminal      ?TERMINAL
RENAME   key            KEY    
\ RENAME   bleep          BLEEP  
RENAME   (?emit)        (?EMIT)
RENAME   emitc          EMITC  
RENAME   (compare)      (COMPARE)
RENAME   (map)          (MAP)
RENAME   enclose        ENCLOSE
RENAME   (find)         (FIND) 
RENAME   upper          UPPER 
RENAME   caseoff        CASEOFF
RENAME   caseon         CASEON
RENAME   digit          DIGIT  
RENAME   i'             I'     
RENAME   i              I      
RENAME   (do)           (DO)   
RENAME   (?do)          (?DO)  
RENAME   (leave)        (LEAVE)
RENAME   0branch        0BRANCH
RENAME   branch         BRANCH 
RENAME   (+loop)        (+LOOP)
RENAME   (loop)         (LOOP) 
RENAME   execute        EXECUTE
RENAME   lit            LIT


\ ______________________________________________________________________ 

SPLASH \ Return to Splash screen


\ display address and length
DECIMAL  
1 WARNING !
CR CR ." give LET A="    0 +ORIGIN DUP U. ." : GO TO 50" CR CR
CR CR ." give SAVE f$ CODE A, " FENCE @ SWAP - U. CR CR

CASEOFF

\ ______________________________________________________________________ 

\ this cuts LFA so dictionary starts with "lit"
0 ' LIT 2- ! final_rp_patch 0 +ORIGIN SOURCE-ID @ F_CLOSE DROP BASIC
\
\ Origin area.
\
\ Memory Map
\ -------------------------------------------------------
\ 0000-3FFF         ROM of Spectrum
\ 4000-47FF         Display file (top)
\ 4800-4FFF         Display file (middle)
\ 5000-57FF         Display file (bottom)
\ 5800-5AFF         Attributes
\ 5B00-5BFF         Printer buffer / System variables 128K RAM
\ 5C00-5CEF         System variables
\          *CHANS   Stream map
\          *PROG    Basic program
\          *VARS    Basic variables
\          *E_LINE  Line in editing
\          *WORKSP  Workspace
\          *STKBOT  Floating point Stack Bottom
\          *STKEND  Floating point end
\          *SP      Z80 Stack Pointer register in Basic
\ 61FF     *RAMTOP  Logical RAM top (RAMTOP system var is at 23730)
\ 6200              Interrupt Vector table to $6363
\ 6302              Saved SP during Interrupt Routine
\ 6363              Interrupt routine
\ 6366      ORIGIN  Forth Origin
\ 63..     *IX      Inner Interpreter pointed by IX.
\                   FENCE @
\                   LATEST @
\           HERE    DP @
\           PAD     HERE 68 + (44h)
\           ...     Dictionary grows upward
\           ...     Free memory
\           ...     Stack grows downward
\ SP                SP@
\ D0E8              S0 @
\ D0E8              #TIB     TIB @
\                   #...     Return stack grows downward: it can hold 80 entries
\                   #RP@
\ D188              #R0 @
\ D188-D1D8         #        User variables area (about 50 entries)
\ D1E4      FIRST   First buffer.
\ E000      LIMIT   There are 7 buffers (516 * 7 = 3612 bytes)
\ FFFF      P_RAMT  Phisical ram-top
\ 

QUIT
