import pandas as pd
import io
import pandas as pd
pd.__version__
import pandas as pd
import sys
import re
from collections import defaultdict

def filterPointerArgs(in_file, out_file):
    with open(in_file) as file_in1:
                with open(out_file,"a") as file_out2:
                    countlines=0
                    for line in file_in1:
                        (CallPC, target, CallSiteName, CalleeName, CallFreq, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred) = line.split(', ')
                        if countlines !=0:
                            if "*" not in ArgType and int(ArgValFreq) > 1:
                                file_out2.write(line)
                        else:
                            file_out2.write("CallPC, target, CallSiteName, CalleeName, CallFreq, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred\n")
                            countlines+=1
def main():
    pinoutF1 = sys.argv[1]
    pinoutF2 = sys.argv[2]
    filterPointerArgs(pinoutF1, pinoutF2)

if __name__ == "__main__":
    main()
