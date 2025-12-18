#!/usr/bin/python
#Python
import sys
output_file=sys.argv[3]
flag1= sys.argv[1]
with open(output_file, "wt") as fout:
    with open(sys.argv[2], "rt") as fin:
        contents = fin.read()
        print("flag1 : ", flag1)
        r_file =contents.replace ('&DEBUGFLAG' , flag1)
        #r_file = r_file.replace ('&BINARIES' , binaries)
        fout.write(r_file)


