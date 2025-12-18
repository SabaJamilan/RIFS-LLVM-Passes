import pandas as pd
import io
import pandas as pd
#pd.__cversion__
import pandas as pd
import sys
import re
from collections import defaultdict

def FuncSpec_per_CallSite(in_file, out_file, out_file2):
    CallSiteFreqDict =  dict()
    CallSiteNumProfiles =  defaultdict(int)
    CallArgCovDict =  defaultdict(list)
    CallArgValFreqDict =  defaultdict(list)
    CallSiteValFreqDict =  defaultdict(list)
    CalleeNameDict =  dict()
    CallSiteNameDict =  dict()
    num_of_CallSites = 0
    CallValFreqDict =  dict()
    CallValDictType =  dict()
    CallValPredDict =  dict()

    with open(in_file) as file_in1:
        with open(out_file,"a") as file_out1:
             countlines=0
             for line in file_in1:
                 #(x, y, CallPC, target, CallSiteName, CalleeName, CallFreq, a, b, c, d, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred) = line.split(', ')
                 (CallPC, target, CallSiteName, CalleeName, CallFreq, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred) = line.split(', ')
                 if countlines !=0:
                     if tuple([CallPC,target]) not in CallSiteFreqDict:
                         num_of_CallSites+=1
                         CallSiteFreqDict[tuple([CallPC,target])] = CallFreq
                         CallSiteNameDict[tuple([CallPC,target])] = str(CallSiteName)
                         CalleeNameDict[tuple([CallPC,target])] = str(CalleeName)
                     if tuple([tuple([CallPC,target]),tuple([ArgIndex,ArgVal])]) not in CallValFreqDict:
                         print(line)
                         CallValFreqDict[tuple([tuple([CallPC,target]),tuple([ArgIndex,ArgVal])])] = int(ArgValFreq)
                         CallValPredDict[tuple([tuple([CallPC,target]),tuple([ArgIndex,ArgVal])])] = float(ArgValPred)
                         CallSiteNumProfiles[tuple([CallPC,target])]+=1
                         CallArgCovDict[tuple([tuple([CallPC,target]),ArgIndex])].append(ArgVal)
                         CallArgValFreqDict[tuple([tuple([CallPC,target]),ArgIndex])].append(ArgValFreq)
                         CallValDictType[tuple([tuple([CallPC,target]),tuple([ArgIndex,ArgVal])])] = str(ArgType)
                         #CallSiteValFreqDict[tuple([CallPC,target])].append(ArgValFreq)
                         CallSiteValFreqDict[tuple([tuple([CallPC,target]),ArgIndex])].append(ArgValFreq)
                 else:
#                    file_out1.write("CallPC, target, CallSiteName, CalleeName, CallFreq, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred\n")
                    countlines+=1


             for key, value in sorted(CallValFreqDict.items(), key=lambda kv: kv[1], reverse=True):
                 file_out1.write(
                                            str(key[0][0]) + ", "+ str(key[0][1]) +  ", "
                                            + str(CallSiteNameDict[(key[0][0], key[0][1])]) + ", "
                                            + str(CalleeNameDict[(key[0][0], key[0][1])]) + ", "
                                            + str(CallSiteFreqDict[(key[0][0], key[0][1])]) + ", "
                                            + str(key[1][0])+ ", "
                                            + str(CallValDictType[key]) + ", "
                                            + str(key[1][1]) + ", "
                                            + str(CallValFreqDict[key]) + ", "
                                            + str(CallValPredDict[key]) + "\n")


             CallSiteSpec =  dict()
             CallSiteSpecCovg =  dict()
             
             # Sort the values in each list
             print("before sort")
             for key, value in CallSiteValFreqDict.items():
                 print(key, value)
             for key, value in CallSiteValFreqDict.items():
                 CallSiteValFreqDict[key] = sorted(value, reverse=True)
             print("after sort")
             for key, value in CallSiteValFreqDict.items():
                 print(key, value)
                 total=0
                 num_spec=0
                 for val in value:
                     print("val: ", val)
                     if total <= 0.9 * int(CallSiteFreqDict[tuple([key[0][0], key[0][1]])]):
                         total+=int(val)
                         num_spec+=1
                 CallSiteSpec[key]=num_spec
                 CallSiteSpecCovg[key]=float(total/int(CallSiteFreqDict[tuple([key[0][0], key[0][1]])]))

             avg_num_spec_per_callsite=0
             x=0
             for key, value in CallSiteSpec.items():
                 print(key,", ",CallSiteSpec[key],", ", CallSiteSpecCovg[key])
                 avg_num_spec_per_callsite+=int(CallSiteSpec[key])
                 x+=1
             #avg_num_spec_per_callsite=avg_num_spec_per_callsite/num_of_CallSites
             avg_num_spec_per_callsite=avg_num_spec_per_callsite/x
             print("avg_num_spec_per_callsite: ", avg_num_spec_per_callsite)
             avg_avg_cov_callsite=0
             x=0
             for key, value in CallSiteSpecCovg.items():
                 avg_avg_cov_callsite+=int(CallSiteSpecCovg[key])
                 x+=1
             #avg_avg_cov_callsite=avg_avg_cov_callsite/num_of_CallSites
             avg_avg_cov_callsite=avg_avg_cov_callsite/x
             print("avg_avg_cov_callsite: ", avg_avg_cov_callsite)


             with open(out_file2,"a") as file_out2:
                 for key, value in CallSiteSpec.items():
                     #file_out2.write(str(key[0]) + ", "+ str(key[1]) +", "+str(CallSiteSpec[key])+", "+ str(CallSiteSpecCovg[key])+"\n")
                     file_out2.write(str(key[0][0]) + ", "+str(key[0][1]) + ", "+ str(CallSiteFreqDict[tuple([key[0][0], key[0][1]])])+ ", "+ str(key[1]) +", "+str(CallSiteSpec[key])+", "+ str(float(CallSiteSpecCovg[key])*100)+"\n")
                 file_out2.write("avg_num_spec_per_callsite = "+ str(avg_num_spec_per_callsite) +"\n") 
                 file_out2.write("avg_avg_cov_callsite = "+ str(float(avg_avg_cov_callsite)*100) +"\n") 

def main():
    F1 = sys.argv[1]
    F2 = sys.argv[2]
    F3 = sys.argv[3]
    FuncSpec_per_CallSite(F1, F2, F3) 
    #F3 = sys.argv[3]
    #F4 = sys.argv[4]
    #low_threshold = sys.argv[5]
    #high_threshold = sys.argv[6]
    #cal_coverage(F1, F2, F3, F4, low_threshold, high_threshold)

if __name__ == "__main__":
    main()
