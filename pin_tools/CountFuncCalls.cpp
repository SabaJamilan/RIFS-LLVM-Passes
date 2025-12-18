#include <iostream>
#include <fstream>
#include "pin.H"
#include <stdio.h>
#include <pin.H>
#include <map>
#include <iomanip>
#include <string.h>
#include <vector>
#include <algorithm>
#include <iterator>
#include <unordered_map>
#include <deque>
#include "instlib.H"
#include <sstream>

using namespace std;
using std::cerr;
using std::ofstream;
using std::ios;
using std::string;
using std::endl;
using std::hex;

std::string fileName;
std::ofstream OutFile1;
std::ofstream OutFile2;
std::ofstream CallsFreqStatFile;
struct tm stamp;

static UINT64 TotalCalls = 0;
static UINT64 NumDiffCalls = 0;
std::map<std::pair<ADDRINT,ADDRINT>, uint64_t> CallFreq;


KNOB<string> KnobOutputFile1(KNOB_MODE_WRITEONCE, "pintool", "o1", "TotalNumCalls.out", "specify output file name");
KNOB<string> KnobOutputFile2(KNOB_MODE_WRITEONCE, "pintool", "o2", "NumDiffCalls.out", "specify output file name");
KNOB<BOOL> KnobProfileCallsFreq(KNOB_MODE_WRITEONCE, "pintool", "p", "0", "profile ip/target addresses for Function Calls");
KNOB<string> KnobProfileCallsFreqOutputFile(KNOB_MODE_WRITEONCE, "pintool", "po", "output file contains profiling ip/target addresses for Function Calls", "specify trace file name");

VOID PrintStatistics_CallsFreq()
{
  if(KnobProfileCallsFreq.Value()) {
    string nameOfFile = fileName;
    CallsFreqStatFile.open(nameOfFile.c_str());
    for ( auto &CallId : CallFreq){
      CallsFreqStatFile <<  CallId.first.first << ", " << CallId.first.second ; 
      CallsFreqStatFile <<  ", " << CallFreq[{CallId.first.first,CallId.first.second}] <<"\n";
    }
  }
}



VOID do_count(ADDRINT ip, ADDRINT target ) { 
  //CallFreq[{ip,target}]++;
  TotalCalls++;

  if(CallFreq.find(std::make_pair(ip,target))!=CallFreq.end()){
    CallFreq[{ip,target}]++;
  }
  else{
    CallFreq[{ip,target}]=1;
    NumDiffCalls++;
  }
}
/*
VOID Trace(TRACE trace, VOID *v)
{
  for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl))
  {
    INS ins = BBL_InsTail(bbl);
    RTN cur_rtn = INS_Rtn(ins);
    if (RTN_Valid(cur_rtn))
    {
      if( IMG_IsMainExecutable(SEC_Img(RTN_Sec(cur_rtn))))
      {
         if( INS_IsCall(ins))
         {
*/
VOID Instruction(INS tail, VOID *v)
{
  if( INS_IsCall(tail))
  {
    RTN cur_rtn = INS_Rtn(tail);
    if (RTN_Valid(cur_rtn))
    {
      if( IMG_IsMainExecutable(SEC_Img(RTN_Sec(cur_rtn))))
      {
           INS_InsertCall(tail, IPOINT_BEFORE, AFUNPTR (do_count), IARG_INST_PTR, IARG_BRANCH_TARGET_ADDR, IARG_END);
           //INS_InsertCall(ins, IPOINT_TAKEN_BRANCH, AFUNPTR(do_count), IARG_BRANCH_TARGET_ADDR, IARG_RETURN_IP,IARG_END);
          }
      }
    }    
}


// This function is called when the application exits
VOID Fini(INT32 code, VOID *v)
{
  PrintStatistics_CallsFreq();  
    
  OutFile1.setf(ios::showbase);
  OutFile1 << TotalCalls << endl;
  OutFile1.close();
  OutFile2.setf(ios::showbase);
  OutFile2 << NumDiffCalls << endl;
  OutFile2.close();


}

INT32 Usage()
{
    cerr << "This tool counts the number of FuncCalls" << endl;
    cerr << endl << KNOB_BASE::StringKnobSummary() << endl;
    return -1;
}


int main(int argc, char * argv[])
{
    // Initialize pin
    if (PIN_Init(argc, argv)) return Usage();
    
    if (KnobProfileCallsFreq.Value()) {
   /*   time_t t = time(NULL);
      stamp = *localtime(&t);
      std::ostringstream ss;
      ss << static_cast<long long>(stamp.tm_year + 1900) << "_" << static_cast<long long>(stamp.tm_mon + 1) << "_"
        << static_cast<long long>(stamp.tm_mday) << "_" << static_cast<long long>(stamp.tm_hour) << "."
        << static_cast<long long>(stamp.tm_min) << "." << static_cast<long long>(stamp.tm_sec);
     */
        fileName = KnobProfileCallsFreqOutputFile.Value();
    }
    
    OutFile1.open(KnobOutputFile1.Value().c_str());
    OutFile2.open(KnobOutputFile2.Value().c_str());
    /*TRACE_AddInstrumentFunction(Trace, 0);
    // Register Fini to be called when the application exits
    PIN_AddFiniFunction(Fini, 0);
    // Start the program, never returns
    PIN_StartProgram();
    */

    INS_AddInstrumentFunction(Instruction, 0);
    PIN_AddFiniFunction(Fini, 0);
    PIN_StartProgram();



    return 0;
}
