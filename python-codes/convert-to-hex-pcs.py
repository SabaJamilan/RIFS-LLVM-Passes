import pandas as pd
import io
import pandas as pd
pd.__version__
import pandas as pd 
import sys
import re
from collections import defaultdict


###convert Vals and PCs from Decimal to Hex
conversion_table = {0: '0', 1: '1', 2: '2', 3: '3',
                    4: '4', 5: '5', 6: '6', 7: '7',
                    8: '8', 9: '9', 10: 'a', 11: 'b',
                    12: 'c', 13: 'd', 14: 'e', 15: 'f'}

###function which converts decimal value to hexadecimal value
def decimalToHexadecimal(decimal):
    if(decimal <= 0):
        return ''
    remainder = decimal % 16
    return decimalToHexadecimal(decimal//16) + conversion_table[remainder]


def performAnalysis(in_file, out_file):
    count=0
    num_pointer_args=0;
    with open(in_file) as file_in:
        with open(out_file,"a") as file_out:
            for line in file_in:
                (func_file_id, NumCalls, CallPC, target, CallSiteName, CalleeName, CallFreq, NumtotalArgs, NumIntArgs, NumfloatArgs, NumPointerArgs, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred) = line.split(', ')
                if count !=0 :
                    CallPC_hex = decimalToHexadecimal(int(CallPC))
                    target_hex = decimalToHexadecimal(int(target))
                    file_out.write(str(CallPC_hex) +", "+str(target_hex)+", "+  str(CallSiteName)+", "+str(CalleeName)+", "+str(CallFreq)+", "+ str(ArgIndex)+", "+ str(ArgType) + ", "+ str(ArgVal) + ", "+ str(ArgValFreq) + ", "+ str(ArgValPred));
                else:
                    file_out.write("CallPC, target, CallSiteName, CalleeName, CallFreq, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred\n");
                count += 1


def main():
    inF = sys.argv[1]
    outF = sys.argv[2]
    performAnalysis(inF, outF)

if __name__ == "__main__":
    main()


