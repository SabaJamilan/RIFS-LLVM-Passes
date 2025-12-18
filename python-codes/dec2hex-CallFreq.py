import pandas as pd
import io
import pandas as pd
pd.__version__
import pandas as pd
import sys
import re
from collections import defaultdict
from ast import literal_eval                  

def dec2hex(in_file, out_file):
    found=False
    with open(in_file) as file_in:
        with open(out_file,"a") as file_out:
            for line in file_in:
                (ip, target, freq) = line.split(', ')
                hexip = hex(int(ip.split()[0]))
                hextarget = hex(int(target.split()[0]))
                file_out.write(str(hexip[2:])+","+str(hextarget[2:]) +","+ str(freq))

def main():
    inF = sys.argv[1]
    outF = sys.argv[2]
    df = pd.read_csv(inF)
    dec2hex(inF, outF)

if __name__ == "__main__":
    main()

