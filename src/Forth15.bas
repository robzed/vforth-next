  10 LET A=25604: REM Warm start  15 GO TO 80  20 LET A=25600: REM Cold start  80  .CD "C:/FORTH"  83 REM #4 must be the 1st open  84 ; OPEN # 4,"u>!Blocks-64.bin"  86 RUN AT 3  91 OPEN # 11,"src/F15a.f"  92 OPEN # 12,"src/Z80N-asm.f"  93 OPEN # 13,"o>output.txt"  96 LAYER 1,2  97 ; OPEN # 2,"W>0,0,24,32,8"  98 PRINT CHR$ 14:;clear scr  99 LET A= USR A 100 CLOSE # 4 101 CLOSE # 11: CLOSE # 12  102 CLOSE # 13 103 CLOSE # 2 110 IF A>33000 THEN PAUSE 0: GO TO 80:; useful compiling9996 STOP 9997 SAVE "forth15e.bin" CODE 25600,92169998 STOP 9999 SAVE "Forth15.bas" LINE 20