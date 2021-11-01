\
\ speed!.f
\
\ Set CPU speed via Register #7 Port.
\ 0 -->  3.5 MHz
\ 1 -->  7.0 MHz
\ 2 --> 14.0 MHz
\ 3 --> 28.0 MHz
\
.( SPEED! )
\
HEX
\
: SPEED! ( n -- )
    3 AND   7 REG!
;

