//  ______________________________________________________________________ 
//
//  next-opt.asm
// 
//  ZX Spectrum Next - peculiar definitions
//  ______________________________________________________________________ 

//  ______________________________________________________________________ 
//
// reg@         n -- b
// read Next REGister n giving byte b
//
//              Colon_Def REG_FETCH, "REG@", is_normal
//              dw      LIT, $243B          
//              dw      PSTORE
//              dw      LIT, $253B          
//              dw      PFETCH
//              dw      EXIT
                New_Def REG_FETCH, "REG@", is_code, is_normal
                exx
                ld      bc, $243B 
                pop     hl 
                out     (c), l 
                inc     b
                in      l, (c)
                push    hl
                exx
                next


//  ______________________________________________________________________ 
//
// reg!         b n --
// write value b to Next REGister n 
//
//              Colon_Def REG_STORE, "REG!", is_normal
//              dw      LIT, $243B          
//              dw      PSTORE
//              dw      LIT, $253B          
//              dw      PSTORE
//              dw      EXIT
                New_Def REG_STORE, "REG!", is_code, is_normal
                exx
                ld      bc, $243B 
                pop     hl 
                out     (c), l 
                inc     b
                pop     hl
                out     (c), l
                exx
                next


//  ______________________________________________________________________ 
//
// m_p3dos      n1 n2 n3 n4 a -- n5 n6 n7 n8  f 
// NextZXOS call wrapper.
//  n1 = hl register parameter value
//  n2 = de register parameter value 
//  n3 = bc register parameter value
//  n4 =  a register parameter value
//   a = routine address in ROM 3
// ----
//  n5 = hl returned value
//  n6 = de returned value 
//  n7 = bc returned value
//  n8 =  a returned value
//   f
                New_Def M_P3DOS, "M_P3DOS", is_code, is_normal
                 exx
                 pop     hl                  // dos call entry address a  //  n1 n2 n3 n4
                 pop     de                  // a register argument       //  n1 n2 n3
                 ld      a, e
                 pop     bc                  // bc' argument              //  n1 n2
                 pop     de                  // de' argument              //  n1 
                 ex      (sp), hl            // hl' argument and entry address in TOS
                exx
                pop     hl                  // entry address a
                push    ix     
                push    de
                push    bc
                ex      de, hl              // de is entry address
//              ld      (SP_Saved), sp
//              ld      sp, Cold_origin - 5
//              ld      sp, TSTACK          // Carefully balanced from startup
                ld      c, 7                // use 7 RAM Bank
                di
                rst     08
                db      $94
                ei
        ////    ld      a, (Saved_MMU + 1)
        ////    nextreg $53, a            // some calls reset MMU3 to $11 !

//              ld      sp, (SP_Saved)
//              push    ix
//              pop     hl
//              ld      (IX_Echo), hl
                ld      (IX_Echo), ix

                exx 
                pop     bc
                pop     de
                pop     ix
                 exx
                 push    hl
                 push    de
                 push    bc
                 ld      h, 0
                 ld      l, a
                 push    hl
                exx
                sbc     hl, hl              // -1 for OK ; 0 for KO but now...
                inc     hl                  //  0 for OK ; 1 for ko
                push    hl
                next

//  ______________________________________________________________________ 
//
// blk-fh
//              Variable_Def BLK_FH,   "BLK-FH",   1
// 
//              New_Def BLK_FNAME,   "BLK-FNAME", Create_Ptr, is_normal  
// Len_Filename:   db      30
// Blk_filename:   db      "c:/tools/vforth/!Blocks-64.bin", 0
//                 ds      32

//  ______________________________________________________________________ 
//
// blk-seek     n -- 
// seek block n  within blocks!.bin  file
                Colon_Def BLK_SEEK, "BLK-SEEK", is_normal
                dw  BBUF, MMUL
                dw  BLK_FH, FETCH
                dw  F_SEEK
                dw  LIT, $2D, QERROR
                dw  EXIT

//  ______________________________________________________________________ 
//
// blk-read     n -- 
// seek block n  within blocks!.bin  file
                Colon_Def BLK_READ, "BLK-READ", is_normal
                dw  BLK_SEEK
                dw  BBUF
                dw  BLK_FH, FETCH
                dw  F_READ
                dw  LIT, $2E, QERROR
                dw  DROP
                dw  EXIT

//  ______________________________________________________________________ 
//
// blk-write     n -- 
// seek block n  within blocks!.bin  file
                Colon_Def BLK_WRITE, "BLK-WRITE", is_normal
                dw  BLK_SEEK
                dw  BBUF
                dw  BLK_FH, FETCH
                dw  F_WRITE
                dw  LIT, $2F, QERROR
                dw  DROP
                dw  EXIT

//  ______________________________________________________________________ 
//
// blk-init     n -- 
// seek block n  within blocks!.bin  file
                Colon_Def BLK_INIT, "BLK-INIT", is_normal
                dw  BLK_FH, FETCH, F_CLOSE, DROP
                dw  BLK_FNAME, ONE_PLUS
                dw  HERE, THREE, F_OPEN         // open for update (read+write)
            //    dw  LIT, $2C, QERROR
            
                dw  ZBRANCH
                dw  Blk_Init_Endif - $

                dw  LIT, $FFCF
                dw  LIT, Exit_with_error
                dw  STORE

                dw  BASIC
Blk_Init_Endif:
                
                dw  BLK_FH, STORE
                dw  EXIT

//  ______________________________________________________________________ 
//
// #sec
// number of 512-Byte "sectors" available on thie sysstem.
// it adds up to 16 MByte of data that can be used as source or pool for almost anything.

                Constant_Def NSEC , "#SEC", 32767

//  ______________________________________________________________________ 


