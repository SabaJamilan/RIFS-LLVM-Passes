/*
 * A pin tool to record the argument values and register values for function calls.
 */
#include <stdio.h>
#include <pin.H>
#include <map>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <string.h>
#include <vector>
#include <algorithm>
#include "pin.H"
#include <iterator>
#include <unordered_map>
#include <deque>
#include "instlib.H"
#include <sstream>
#include <string> // for string and to_string()
using namespace std;

template<typename T>
std::string toString(const T& value)
{
    std::ostringstream oss;
    oss << value;
    return oss.str();
}

std::ofstream TraceFile;
std::ofstream out;

/* ===================================================================== */
/* Commandline Switches */
/* ===================================================================== */
KNOB<string> KnobinputFile(KNOB_MODE_WRITEONCE, "pintool",
                           "i", "func_sig_all.csv", "input file conatin function signature to trace");
KNOB<BOOL> KnobProfileCallArgs(KNOB_MODE_WRITEONCE, "pintool",
                           "p", "0", "profile args values for all function calls with (int/float) args");
KNOB<string> KnobProfileOutputFile(KNOB_MODE_WRITEONCE, "pintool",
                           "po", "profileFuncCallsIntFloatArgs", "specify trace file name");
KNOB<string> KnobLogOutputFile(KNOB_MODE_WRITEONCE, "pintool",
                           "tf", "tracedFuncsName.out", "specify trace file name");
/*KNOB<UINT64> Skip(KNOB_MODE_WRITEONCE, "pintool",
                           "s", "0", "Begin emitting branch descriptors after executing a specified number of instructions ");
KNOB<UINT64> Length(KNOB_MODE_WRITEONCE, "pintool",
                           "l", "0", "Number of instructions to profile (default is no limit)");
*/
KNOB<UINT64> id(KNOB_MODE_WRITEONCE, "pintool",
                           "d", "0", "Number of instructions to profile (default is no limit)");

int NumFuncToTrace;
int DetecFuncToTrace;

struct Record
{
    int id;
    std::string func_name;
    int total_num_args;
    int num_int_args;
    int num_float_args;
    int num_pointer_args;
    
    string IntArgsTypeVec[10];
    int IntArgsIndexVec[10]= {1000};
 
    string FloatArgsTypeVec[10];
    int FloatArgsIndexVec[10]= {1000};
};


static UINT64 totalNumCalls = 0;
std::vector<Record> my_records;
volatile BOOL IsEndOfApplication = FALSE;
struct tm stamp;
std::ofstream CallsArgsValStatFile;
std::string fileName;
UINT64 fastforwardLength;
UINT64 traceLength;

/* ===================================================*/
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallNumTotalArgs;
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallNumIntArgs;
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallNumFpArgs;
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallNumPointerArgs;
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallFreq;
std::map<std::pair<ADDRINT,ADDRINT>, string> CallSiteName;
std::map<std::pair<ADDRINT,ADDRINT>, string> CalleeName;
std::map<ADDRINT, int> SeenCall;

std::map<std::pair<std::pair<ADDRINT,ADDRINT>,std::pair<int,float>> , uint64_t> FpArgFreq;
std::map<std::pair<std::pair<ADDRINT,ADDRINT>,std::pair<int,ADDRINT>> , uint64_t> IntArgFreq;
std::map<std::pair<std::pair<ADDRINT,ADDRINT>, int> , uint64_t> FpArgNumDiffVals;
std::map<std::pair<std::pair<ADDRINT,ADDRINT>, int> , string> FpArgType;
std::map<std::pair<std::pair<ADDRINT,ADDRINT>, int> , uint64_t> IntArgNumDiffVals;
std::map<std::pair<std::pair<ADDRINT,ADDRINT>, int> , string> IntArgType;
/* ===================================================*/
/* ===================================================*/

//bool readyToProfile;

const string *Target2String(ADDRINT target)
{
   string name = RTN_FindNameByAddress(target);
   return new string(name);
}


const char* StripPath(const char* path)
{
    const char* file = strrchr(path, '/');
    if (file)
        return file + 1;
    else
        return path;
}


VOID PrintStatistics_CallArgsValue() 
{
  if(KnobProfileCallArgs.Value()) {
    //string nameOfFile = fileName  + "_s_" + toString(Skip.Value()) + "_l_" + toString(Length.Value()) +  "_d_" + toString(id.Value())+ ".CallArgsValueStatistics";
    string nameOfFile = fileName + "_chunck_" + toString(id.Value())+ ".CallArgsValueStatistics";
    CallsArgsValStatFile.open(nameOfFile.c_str());
    for (auto &CallId : CallFreq) {

      for ( auto &arg : FpArgFreq){
          if(arg.first.first == CallId.first){
            if (float(arg.second)/float(CallFreq[CallId.first]) >= 0.01 && arg.first.second.first != 1000 && FpArgType[{{CallId.first.first,CallId.first.second},arg.first.second.first}] != "" ){
               //CallsArgsValStatFile  <<  toString(Skip.Value()) << ", " << toString(Length.Value())  << ", " << traceLength << ", " << totalNumCalls << ", ";
               CallsArgsValStatFile  <<  toString(id.Value()) << ", " << totalNumCalls << ", ";


               CallsArgsValStatFile << CallId.first.first << ", " << CallId.first.second << ", ";
               CallsArgsValStatFile << CallSiteName[CallId.first] << ", " << CalleeName[CallId.first] << ", ";
               CallsArgsValStatFile << CallFreq[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumTotalArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumIntArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumFpArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumPointerArgs[CallId.first] << ", ";
               CallsArgsValStatFile << arg.first.second.first << ",";
               CallsArgsValStatFile << FpArgType[{{CallId.first.first,CallId.first.second},arg.first.second.first}] << ", ";
               CallsArgsValStatFile << arg.first.second.second << ", ";
               CallsArgsValStatFile << arg.second << ", ";
               CallsArgsValStatFile << float(arg.second)/float(CallFreq[CallId.first])*100;
               CallsArgsValStatFile <<"\n";
            }
          }
        }
      for ( auto &arg : IntArgFreq){
          if(arg.first.first == CallId.first){
            if (float(arg.second)/float(CallFreq[CallId.first]) >= 0.01 && arg.first.second.first != 1000 && IntArgType[{{CallId.first.first,CallId.first.second},arg.first.second.first}] != ""){
               CallsArgsValStatFile  <<  toString(id.Value()) << ", " << totalNumCalls << ", ";
               //CallsArgsValStatFile  <<  toString(Skip.Value()) << ", " << toString(Length.Value())  << ", " << traceLength + 1  << ", " << totalNumCalls << ", ";
              //CallsArgsValStatFile << toString(Skip.Value()) << ", " << toString(Length.Value())<< ", ";
               CallsArgsValStatFile << CallId.first.first << ", " << CallId.first.second << ", ";
               CallsArgsValStatFile << CallSiteName[CallId.first] << ", " << CalleeName[CallId.first] << ", ";
               CallsArgsValStatFile << CallFreq[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumTotalArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumIntArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumFpArgs[CallId.first] << ", ";
               CallsArgsValStatFile << CallNumPointerArgs[CallId.first] << ", ";
               CallsArgsValStatFile << arg.first.second.first << ",";
               CallsArgsValStatFile << IntArgType[{{CallId.first.first,CallId.first.second},arg.first.second.first}] << ", ";
               CallsArgsValStatFile << arg.first.second.second << ", ";
               CallsArgsValStatFile << arg.second << ", ";
               CallsArgsValStatFile << float(arg.second)/float(CallFreq[CallId.first])*100;
               CallsArgsValStatFile <<"\n";
            }
          }
        }
    }//CallId
    CallsArgsValStatFile.close();
  }
}


void profile_args_val(CONTEXT * ctxt,  ADDRINT ip, ADDRINT instrAddr,
    int identifer_num,
    ADDRINT arg0, ADDRINT arg1, ADDRINT arg2, ADDRINT arg3,
    ADDRINT arg4, ADDRINT arg5, ADDRINT arg6, ADDRINT arg7,
    ADDRINT arg8, ADDRINT arg9, ADDRINT arg10, ADDRINT arg11,
    ADDRINT arg12, ADDRINT arg13, ADDRINT arg14, ADDRINT arg15,  CHAR *Caller)
{
 /* 
   ///skip
    if (fastforwardLength < Skip.Value()) {
      std::cout << " 1) Skip: "<< Skip.Value() << "  fastforwardLength: "<< fastforwardLength << "\n";  
      
      fastforwardLength++;
        return;
    }
    else {
        traceLength++;
      std::cout << " traceLength : " <<  traceLength << "   Skip.Value(): "<< Skip.Value() << " fastforwardLength : " << fastforwardLength << "\n";
    }
    if ((traceLength + 1) == Length.Value()) {
        std::cout << " 11) Skip: "<< Skip.Value() <<  "  traceLength: "<< traceLength << "  Detach!!!\n";
        PIN_Detach();
        return;
    }
*/

    string targetName=RTN_FindNameByAddress(ip);
    string Callee = "";
    const string *s = Target2String(ip);
    Callee = strdup(&(*s->c_str()));

    CallFreq[{instrAddr,ip}]++;
    CallSiteName[{instrAddr,ip}] = Caller;
    CalleeName[{instrAddr,ip}] = Callee ;

//    std::cout << "   instrAddr: "<< instrAddr << "   ip: "<< ip << "\n";
    std::map<string,ADDRINT> strToADD;
    strToADD["arg0"]=arg0;
    strToADD["arg1"]=arg1;
    strToADD["arg2"]=arg2;
    strToADD["arg3"]=arg3;
    strToADD["arg4"]=arg4;
    strToADD["arg5"]=arg5;
    strToADD["arg6"]=arg6;
    strToADD["arg7"]=arg7;
    strToADD["arg8"]=arg8;
    strToADD["arg9"]=arg9;
    strToADD["arg10"]=arg10;
    strToADD["arg11"]=arg11;
    strToADD["arg12"]=arg12;
    strToADD["arg13"]=arg13;
    strToADD["arg14"]=arg14;
    strToADD["arg15"]=arg15;
 

    /////
    //totalNumCalls++;
    FPSTATE fpState;
    PIN_GetContextFPState(ctxt, &fpState);
    if (KnobProfileCallArgs.Value()) {

      for (auto i: my_records) {
        if (i.id == identifer_num){

          CallNumTotalArgs[{instrAddr,ip}] = i.total_num_args;
          CallNumIntArgs[{instrAddr,ip}] = i.num_int_args;
          CallNumFpArgs[{instrAddr,ip}] = i.num_float_args;
          CallNumPointerArgs[{instrAddr,ip}] = i.num_pointer_args;

          for (int e=0; e< i.num_float_args; e++){
            float val;
            memcpy(&val, &fpState.fxsave_legacy._xmms[e], sizeof(val));
            if(FpArgFreq.find(std::make_pair(std::make_pair(instrAddr,ip), std::make_pair(i.FloatArgsIndexVec[e],val)))!=FpArgFreq.end()){
              FpArgFreq[{{instrAddr,ip}, {i.FloatArgsIndexVec[e],val}}]++;
            }
            else{
              FpArgFreq[{{instrAddr,ip}, {i.FloatArgsIndexVec[e],val}}] = 1;
              FpArgNumDiffVals[{{instrAddr,ip}, i.FloatArgsIndexVec[e]}]++;
              FpArgType[{{instrAddr,ip}, i.FloatArgsIndexVec[e]}] = i.FloatArgsTypeVec[e];
            }
          }

          int totalIntTypeArgs = i.num_int_args + i.num_pointer_args;

          if (totalIntTypeArgs < 17 ){
            for (int e=0; e < totalIntTypeArgs; e++){
              std::string argId = "arg" + toString(e);
              if(IntArgFreq.find(std::make_pair(std::make_pair(instrAddr,ip), std::make_pair(i.IntArgsIndexVec[e],strToADD[argId])))!=IntArgFreq.end()){
                IntArgFreq[{{instrAddr,ip}, {i.IntArgsIndexVec[e],strToADD[argId]}}]++;
              }
              else{
                IntArgFreq[{{instrAddr,ip}, {i.IntArgsIndexVec[e],strToADD[argId]}}] = 1;
                IntArgNumDiffVals[{{instrAddr,ip}, i.IntArgsIndexVec[e]}]++;
                IntArgType[{{instrAddr,ip}, i.IntArgsIndexVec[e]}] = i.IntArgsTypeVec[e];
              }
            } 
          }
        }
      }
  } //if (KnobProfileCallArgs.Value())

}


void indirect_profile_args_val(CONTEXT * ctxt,  ADDRINT target, BOOL taken , ADDRINT instrAddr,
    int identifer_num,
    ADDRINT arg0, ADDRINT arg1, ADDRINT arg2, ADDRINT arg3,
    ADDRINT arg4, ADDRINT arg5, ADDRINT arg6, ADDRINT arg7,
    ADDRINT arg8, ADDRINT arg9, ADDRINT arg10, ADDRINT arg11,
    ADDRINT arg12, ADDRINT arg13, ADDRINT arg14, ADDRINT arg15,  CHAR *Caller)
{
  ///skip
  /*  if (fastforwardLength < Skip.Value()) {
        fastforwardLength++;
        return;
    }
    else {
      std::cout << " traceLength : " <<  traceLength << "Skip.Value(): "<< Skip.Value() << " fastforwardLength : " << fastforwardLength << "\n";
        traceLength++;
    }
    if ((traceLength + 1) == Length.Value()) {
      //std::cout << " 22) Skip: "<< Skip.Value() <<  "  traceLength: "<< traceLength << "  Detach!!!\n";
        PIN_Detach();
        return;
    }
  /////
  totalNumCalls++;
*/
    if (!taken)
        return;
    profile_args_val(ctxt, target, instrAddr,
        identifer_num,
        arg0, arg1, arg2, arg3, 
        arg4, arg5, arg6, arg7,
        arg8, arg9, arg10, arg11,
        arg12, arg13, arg14, arg15, Caller);
}



VOID do_count(ADDRINT ip, ADDRINT target ) {
  ///skip
    totalNumCalls++;
   /* 
    if (fastforwardLength < Skip.Value()) {
        //std::cout << " 1) Skip: "<< Skip.Value() << "  fastforwardLength: "<< fastforwardLength << "\n";  
        fastforwardLength++;
        readyToProfile=false;
        return;
    }
    else {
        traceLength++;
          //std::cout  << "readyToProfile set to true\n";
          //std::cout << " traceLength : " <<  traceLength << "   Skip.Value(): "<< Skip.Value() << " fastforwardLength : " << fastforwardLength << "\n";
        readyToProfile=true;
    }
    if ((traceLength + 1) == Length.Value()) {
          std::cout << " Skip: "<< Skip.Value() <<  "  traceLength: "<< traceLength << "  Detach!!!\n";
        readyToProfile=false;
        PIN_Detach();
        return;
    }
*/    
  /////


}

VOID Instruction(INS tail, VOID *v)
{
  if( INS_IsCall(tail))
  {
    RTN cur_rtn = INS_Rtn(tail);
    if (RTN_Valid(cur_rtn))
    {
      if( IMG_IsMainExecutable(SEC_Img(RTN_Sec(cur_rtn))))
      {

/*        totalNumCalls++;

        std::cout  << "totalNumCalls : " << totalNumCalls << "\n";
        if (fastforwardLength < Skip.Value()) {
          std::cout << " 1) Skip: "<< Skip.Value() << "  fastforwardLength: "<< fastforwardLength << "\n";  
         fastforwardLength++;
         return;
        }
        else {
          traceLength++;
          std::cout << " traceLength : " <<  traceLength << "   Skip.Value(): "<< Skip.Value() << " fastforwardLength : " << fastforwardLength << "\n";
        }
        if ((traceLength + 1) == Length.Value()) {
          std::cout << " Skip: "<< Skip.Value() <<  "  traceLength: "<< traceLength << "  Detach!!!\n";
          PIN_Detach();
          return;
        }

*/
INS_InsertCall(tail, IPOINT_BEFORE, AFUNPTR (do_count), IARG_INST_PTR, IARG_BRANCH_TARGET_ADDR, IARG_END);
    //if(readyToProfile ){
        string rtnName = RTN_Name(cur_rtn);
        //if(INS_IsDirectBranchOrCall(tail))
        //////////////////////////////////////////
        //Pin 3.31 new API for above instruction:
        //////////////////////////////////////////
        if(INS_IsDirectControlFlow(tail))
        {
          //const ADDRINT target = INS_DirectBranchOrCallTargetAddress(tail);
          //////////////////////////////////////////
          //Pin 3.31 new API for above instruction:
          //////////////////////////////////////////
          const ADDRINT target = INS_DirectControlFlowTargetAddress(tail);
          string targetName=RTN_FindNameByAddress(target);
          char * callSite;
          callSite = strdup(rtnName.c_str() );
          string callee = "";
          const string *s = Target2String(target);
          callee = strdup(&(*s->c_str()));

          if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(profile_args_val),
                   IARG_CONTEXT,
                   IARG_ADDRINT,                       // "target"'s type
                   target,                             // Who is called?
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

          }//if(SeenCall.find(target)!=SeenCall.end())
          else{
            for (auto i: my_records) {
              //std::cout << "targetName: "<< targetName << "\n";
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(profile_args_val),
                     IARG_CONTEXT,
                     IARG_ADDRINT,                       // "target"'s type
                     target,                             // Who is called?
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
              }
            }//for
           }//else
         }//INS_IsDirectBranchOrCall
         else{

           if(INS_IsDirectControlFlow(tail)){
             const ADDRINT target = INS_DirectControlFlowTargetAddress(tail);
             string targetName=RTN_FindNameByAddress(target);
             char * callSite;
             callSite = strdup(rtnName.c_str() );
             if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(profile_args_val),
                   IARG_CONTEXT,
                   IARG_ADDRINT,                       // "target"'s type
                   target,                             // Who is called?
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

            }//if
            else{
             for (auto i: my_records) {
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(profile_args_val),
                     IARG_CONTEXT,
                     IARG_ADDRINT,                       // "target"'s type
                     target,                             // Who is called?
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
               }//if
             }//for
            }//else
           }//INS_IsDirectControlFlow(tail)
          else{
             const ADDRINT target = IARG_BRANCH_TARGET_ADDR;
             string targetName=RTN_FindNameByAddress(target);
             char * callSite;
             callSite = strdup(rtnName.c_str() );
             if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(indirect_profile_args_val),
                   IARG_CONTEXT,
                   IARG_BRANCH_TARGET_ADDR,
                   IARG_BRANCH_TAKEN,
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

            }//if
            else{
             for (auto i: my_records) {
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(indirect_profile_args_val),
                     IARG_CONTEXT,
                     IARG_BRANCH_TARGET_ADDR,
                     IARG_BRANCH_TAKEN,
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
  //             }
             }//if
            }//for
           }//else
         }//else
       
   // }
    } 
      }
    }///IsCall(tail)
  }
}






/*
VOID Trace(TRACE trace, VOID *v)
{
  for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl))
  {
    INS tail = BBL_InsTail(bbl);
    RTN cur_rtn = INS_Rtn(tail);
    if (RTN_Valid(cur_rtn))
    {
      if( IMG_IsMainExecutable(SEC_Img(RTN_Sec(cur_rtn))))
      {
        if( INS_IsCall(tail))
        {
          bool readyToProfile = false;
          totalNumCalls++;
          if (fastforwardLength < Skip.Value()) {
            fastforwardLength++;
            readyToProfile = false;
          }
          else{
            traceLength++;
            readyToProfile = true;
          }

          if ((traceLength + 1) == Length.Value()) {
            readyToProfile=false;
            PIN_Detach();
          }


      if(readyToProfile){

         std::cout  << " ***** readyToProfile  --> true (skip) : " << Skip.Value() <<  "\n";
         string rtnName = RTN_Name(cur_rtn);
         if(INS_IsDirectBranchOrCall(tail))
         {
          const ADDRINT target = INS_DirectBranchOrCallTargetAddress(tail);
          string targetName=RTN_FindNameByAddress(target);
          char * callSite;
          callSite = strdup(rtnName.c_str() );
          string callee = "";
          const string *s = Target2String(target);
          callee = strdup(&(*s->c_str()));

          if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(profile_args_val),
                   IARG_CONTEXT,
                   IARG_ADDRINT,                       // "target"'s type
                   target,                             // Who is called?
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

          }
          else{
            for (auto i: my_records) {
              //std::cout << "targetName: "<< targetName << "\n";
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(profile_args_val),
                     IARG_CONTEXT,
                     IARG_ADDRINT,                       // "target"'s type
                     target,                             // Who is called?
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
              }
            }
           }
         }//INS_IsDirectBranchOrCall
          //
         else{

           if(INS_IsDirectControlFlow(tail)){
             const ADDRINT target = INS_DirectControlFlowTargetAddress(tail);
             string targetName=RTN_FindNameByAddress(target);
             char * callSite;
             callSite = strdup(rtnName.c_str() );
             if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(profile_args_val),
                   IARG_CONTEXT,
                   IARG_ADDRINT,                       // "target"'s type
                   target,                             // Who is called?
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

            }
            else{
             for (auto i: my_records) {
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(profile_args_val),
                     IARG_CONTEXT,
                     IARG_ADDRINT,                       // "target"'s type
                     target,                             // Who is called?
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
               }
             }
            }
           }//INS_IsDirectControlFlow(tail)
          else{
             const ADDRINT target = IARG_BRANCH_TARGET_ADDR;
             string targetName=RTN_FindNameByAddress(target);
             char * callSite;
             callSite = strdup(rtnName.c_str() );
             if(SeenCall.find(target)!=SeenCall.end()){
              int call_id = SeenCall[target];
              INS_InsertPredicatedCall(
                   tail,
                   IPOINT_BEFORE,
                   AFUNPTR(indirect_profile_args_val),
                   IARG_CONTEXT,
                   IARG_BRANCH_TARGET_ADDR,
                   IARG_BRANCH_TAKEN,
                   IARG_INST_PTR,
                   IARG_PTR,call_id,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                   IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,10,     // Arg_10 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,11,     // Arg_11 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,12,     // Arg_12 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,13,     // Arg_13 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,14,     // Arg_14 value
                   IARG_FUNCARG_ENTRYPOINT_VALUE,15,     // Arg_15 value
                   IARG_PTR, callSite,
                   IARG_END);

            }
            else{
             for (auto i: my_records) {
              if (targetName.find(i.func_name) != std::string::npos){ 
                DetecFuncToTrace++;
                SeenCall[target]=i.id;
                INS_InsertPredicatedCall(
                     tail,
                     IPOINT_BEFORE,
                     AFUNPTR(indirect_profile_args_val),
                     IARG_CONTEXT,
                     IARG_BRANCH_TARGET_ADDR,
                     IARG_BRANCH_TAKEN,
                     IARG_INST_PTR,
                     IARG_PTR,i.id,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,0,      // Arg_0 value,
                     IARG_FUNCARG_ENTRYPOINT_VALUE,1,      // Arg_1 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,2,      // Arg_2 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,3,      // Arg_3 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,4,      // Arg_4 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,5,      // Arg_5 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,6,      // Arg_6 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,7,      // Arg_7 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,8,      // Arg_8 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,9,      // Arg_9 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,10,      // Arg_10 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,11,      // Arg_11 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,12,      // Arg_12 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,13,      // Arg_13 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,14,      // Arg_14 value
                     IARG_FUNCARG_ENTRYPOINT_VALUE,15,      // Arg_15 value
                     IARG_PTR, callSite,
                     IARG_END);
               }
             }
            }
           }//else
         }//else
       }
      }
    }///IsCall(tail)
   }
  }
}
*/


/*  ===================================================================== */
// Pin calls this function every time a new img is loaded
// It can instrument the image, but this example does not
/* ===================================================================== */
/*
VOID ImageLoad(IMG img, VOID *v)
{
    //TraceFile << "Loading " << IMG_Name(img) << ", Image id = " << IMG_Id(img) << endl;
}
*/
/* ===================================================================== */
// Pin calls this function every time a new img is unloaded
// You can't instrument an image that is about to be unloaded
/* ===================================================================== */
/*
VOID ImageUnload(IMG img, VOID *v)
{
    //TraceFile << "Unloading " << IMG_Name(img) << endl;
}
*/
/* ===================================================================== */
/* Print Help Message                                                    */
/* ===================================================================== */

INT32 Usage()
{
    cerr << "This tool produces a trace of register contents." << endl << endl;
    cerr << KNOB_BASE::StringKnobSummary() << endl;
    return -1;
}
/* ===================================================================== */
/* This function is called when the application exits*/
/* ===================================================================== */

VOID DetachCallback(VOID *args)
{
    //std::cout << "TraceCalls pin tool: Detaching ... Skipped: " << Skip.Value() << ", "<< traceLength << std::endl;
    if (KnobProfileCallArgs.Value() == TRUE){
      PrintStatistics_CallArgsValue();
    }
    IsEndOfApplication = TRUE;
    PIN_ExitApplication(0);
}


VOID Fini(INT32 code, VOID *v)
{
//  std::cout << "Fin .." << Skip.Value() << ", "<< traceLength <<   std::endl ;
  PrintStatistics_CallArgsValue();  
  TraceFile  << NumFuncToTrace << "\n";
  TraceFile  << DetecFuncToTrace << "\n";
  TraceFile  << totalNumCalls << "\n";
  TraceFile.close();
  std::cout  << "DetecFuncToTrace:  "<< DetecFuncToTrace << "\n";
}
/* ===================================================================== */
/* Main                                                                  */
/* ===================================================================== */

int main(int argc, char *argv[])
{
    PIN_InitSymbols();
    if( PIN_Init(argc,argv) )
    {
        return Usage();
    }

    if (KnobProfileCallArgs.Value()) {
      time_t t = time(NULL);
      stamp = *localtime(&t);
      std::ostringstream ss;
      ss << static_cast<long long>(stamp.tm_year + 1900) << "_" << static_cast<long long>(stamp.tm_mon + 1) << "_"
        << static_cast<long long>(stamp.tm_mday) << "_" << static_cast<long long>(stamp.tm_hour) << "."
        << static_cast<long long>(stamp.tm_min) << "." << static_cast<long long>(stamp.tm_sec);
      fileName = KnobProfileOutputFile.Value() + ss.str();
    }
   

    TraceFile.open(KnobLogOutputFile.Value().c_str());
    int counter = 0;

    ifstream data(KnobinputFile.Value().c_str());
    std::string str;
    while (getline(data, str))
    {
      Record record;
      std::istringstream stream(str);
      string token;
      
      int int_args=0;
      int float_args=0;
      int pointer_args=0;
     

      getline(stream, record.func_name, ',');
      //std::cout << "record.func_name: "<< record.func_name;
      getline(stream, token, ',');
      record.total_num_args = atoi(token.c_str());
      //std::cout << ", record.total_num_args: "<< record.total_num_args;
      getline(stream, token, ',');
      record.num_int_args = atoi(token.c_str());
      //std::cout << ", record.num_int_args: "<< record.num_int_args;
      getline(stream, token, ',');
      record.num_float_args = atoi(token.c_str());
      //std::cout << ", record.num_float_args: "<< record.num_float_args;
      getline(stream, token, ',');
      record.num_pointer_args = atoi(token.c_str());
      //std::cout << ", record.num_pointer_args: "<< record.num_pointer_args << "\n";
      //
      record.id=counter;

      int i=0;
      int f=0;
      while (stream)
      {
        while ( getline(stream, token, ',')){
          //std::cout<< "stream-token: "<< token  << "\n";
          if(token.find("float") != std::string::npos && token.find("*") == std::string::npos){
            std::string ArgType = token;
            record.FloatArgsTypeVec[f]=ArgType;
            getline(stream, token, ',');
            int ArgIndex = atoi(token.c_str());
            record.FloatArgsIndexVec[f]=ArgIndex;
            //std::cout<< "FloatArgType: "<<  ArgType << "  ArgIndex:  "<< ArgIndex   << "\n";
            f++;
            float_args++;
          }

          if((token.find("int") != std::string::npos || token.find("unsigned long") != std::string::npos ||  token.find("size_t") != std::string::npos ) && token.find("*") == std::string::npos){
            std::string ArgType = token;
            record.IntArgsTypeVec[i]=(ArgType);
            getline(stream, token, ',');
            int ArgIndex = atoi(token.c_str());
            record.IntArgsIndexVec[i]=ArgIndex;
            //std::cout<< "IntArgType: "<<  ArgType << "  ArgIndex:  "<< ArgIndex   << "\n";
            i++;
            int_args++;
          }
 
          if(token.find("*") != std::string::npos){
            std::string ArgType = token;
            record.IntArgsTypeVec[i]=(ArgType);
            getline(stream, token, ',');
            int ArgIndex = atoi(token.c_str());
            record.IntArgsIndexVec[i]=ArgIndex;
            i++;
            //record.PointerArgsIndexVec.push_back(ArgIndex);
            //std::cout<< "PointerArgType: "<<  ArgType << "  ArgIndex:  "<< ArgIndex   << "\n";
            pointer_args++;
          }
        }
      }//while(stream)
      NumFuncToTrace++;
      my_records.push_back(record);
      counter++;
    }
    

   // }

    std::cout << "NumFuncToTrace: "<< NumFuncToTrace << "\n";

/*
    TRACE_AddInstrumentFunction(Trace, 0);
    // Register ImageLoad to be called when an image is loaded
    IMG_AddInstrumentFunction(ImageLoad, 0);
    // Register ImageUnload to be called when an image is unloaded
    IMG_AddUnloadFunction(ImageUnload, 0);
    PIN_AddFiniFunction(Fini, 0);
    PIN_AddDetachFunction(DetachCallback, NULL);
    // Never returns
    PIN_StartProgram();
*/

    INS_AddInstrumentFunction(Instruction, 0);
    PIN_AddFiniFunction(Fini, 0);
    PIN_AddDetachFunction(DetachCallback, NULL);
    PIN_StartProgram();


    return 0;
}


