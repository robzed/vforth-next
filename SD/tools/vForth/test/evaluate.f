\
\ test/evaluate.f
\

NEEDS TESTING

NEEDS S"
NEEDS EVALUATE

TESTING F.6.1.1360 - EVALUATE

: GE1 S" 123" ; IMMEDIATE
: GE2 S" 123 1+" ; IMMEDIATE
: GE3 S" : GE4 345 ;" ;
: GE5 EVALUATE ; IMMEDIATE

( TEST EVALUATE IN INTERP. STATE )
\
T{ GE1 EVALUATE -> 123 }T 
T{ GE2 EVALUATE -> 124 }T
T{ GE3 EVALUATE ->     }T
T{ GE4          -> 345 }T

( TEST EVALUATE IN COMPILE STATE )
\
T{ : GE6 GE1 GE5 ; -> }T 
T{ GE6 -> 123 }T

T{ : GE7 GE2 GE5 ; -> }T
T{ GE7 -> 124 }T



: GE8  S" : GE9 678 ; " EVALUATE ; 

\ The following row doesn't work --> bad definition end.
\ GE8 
\ T{ GE9 -> 678 }T

