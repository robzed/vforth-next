PLUS3DOS �   K
 K                                                                                                         � 
 ; ***  v.Forth 1.7      ***  ; ***  MMU7 Dictionary  ***  ; ***  build 202304016  *** < ; matteo_vitturi at yahoo.com ? �b=1    :�w=7     @3 �2    ,0     :�b:�216  �  :�:�2    ,0       A �0     :  �b:�w:�:�b  B �1    ,1    :�b:�w:� C �1    ,2    :�b:� D �1    ,3    :�b:�w:� E ; setup 64 columns  F ��b:��w:��64   @   K  ��26    ;�0     :�Layer1 cls L � P �i=0     �1     Z. �67  C  ,i*64  @  :�Ula palette Darker-Blue [ �REG 64,14: REG 65,%@10110110 \( �64  @  ,25    :�65  A  ,%@00000001 ]( �64  @  ,17    :�65  A  ,%@00000001 `# ��30    ;�8    :�Full Chr size b �i c# ��"a"-1    :�"ram7.bin"�16     d2 �25087  �a :�Allow 360 bytes before Forth origin n) �org=25446  fc : ; Forth origin address s	 �q$="""" x �f$="forth17d.bin" � �w$="Forth17.bas" � .CD "C:/tools/vForth" � �'"now LOADing code... " � �q$;f$;q$;" CODE ";org � �f$�org � �'"sleep 2":�100  d   � �'"LOADing wrapper...  " � �q$;w$;q$' �
 �50  2   � �w$' �'5 .cd "C:/tools/vForth":�"Forth17_loader.bas"�10  
  