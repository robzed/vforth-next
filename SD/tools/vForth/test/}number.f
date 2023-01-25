\
\ test/}number.f
\


NEEDS TESTING

( Test Suite - Number Patterns )

\
NEEDS >NUMBER
NEEDS .PAD

TESTING F.6.1.0570   -  >NUMBER

HEX

CREATE GN-BUF 0 C,
: GN-STRING GN-BUF 1 ;
: GN-CONSUMED GN-BUF CHAR+ 0 ;
: GN' [CHAR] ' WORD CHAR+ C@ GN-BUF C! GN-STRING ;
T{ 0 0 GN' 0' >NUMBER ->         0 0 GN-CONSUMED }T
T{ 0 0 GN' 1' >NUMBER ->         1 0 GN-CONSUMED }T
T{ 1 0 GN' 1' >NUMBER -> BASE @ 1+ 0 GN-CONSUMED }T
\ FOLLOWING SHOULD FAIL TO CONVERT
T{ 0 0 GN' -' >NUMBER ->         0 0 GN-STRING   }T
T{ 0 0 GN' +' >NUMBER ->         0 0 GN-STRING   }T
T{ 0 0 GN' .' >NUMBER ->         0 0 GN-STRING   }T

: >NUMBER-BASED
   BASE @ >R BASE ! >NUMBER R> BASE ! ;

T{ 0 0 GN' 2'       10 >NUMBER-BASED ->  2 0 GN-CONSUMED }T
T{ 0 0 GN' 2'        2 >NUMBER-BASED ->  0 0 GN-STRING   }T
T{ 0 0 GN' F'       10 >NUMBER-BASED ->  F 0 GN-CONSUMED }T
T{ 0 0 GN' G'       10 >NUMBER-BASED ->  0 0 GN-STRING   }T
T{ 0 0 GN' G' MAX-BASE >NUMBER-BASED -> 10 0 GN-CONSUMED }T
T{ 0 0 GN' Z' MAX-BASE >NUMBER-BASED -> 23 0 GN-CONSUMED }T

: GN1 ( UD BASE -- UD' LEN )
   \ UD SHOULD EQUAL UD' AND LEN SHOULD BE ZERO.
   BASE @ >R BASE !
   <# #S #> 2DUP TYPE SPACE
   0 0 2SWAP >NUMBER SWAP DROP    \ RETURN LENGTH ONLY
   R> BASE ! ;

T{        0   0        2 GN1 ->        0   0 0 }T
T{ MAX-UINT   0        2 GN1 -> MAX-UINT   0 0 }T
T{ MAX-UINT DUP        2 GN1 -> MAX-UINT DUP 0 }T
T{        0   0 MAX-BASE GN1 ->        0   0 0 }T
T{ MAX-UINT   0 MAX-BASE GN1 -> MAX-UINT   0 0 }T
T{ MAX-UINT DUP MAX-BASE GN1 -> MAX-UINT DUP 0 }T
