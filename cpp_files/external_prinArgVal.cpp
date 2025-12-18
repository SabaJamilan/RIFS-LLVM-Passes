#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <cstdlib>
#include <signal.h>
#include <unordered_map>
#include <utility>  // for std::pair
#include <functional> // for std::hash
#include <tuple> // For std::tuple
#include <time.h> // For CLOCKS_PER_SEC

using namespace std;
std::string outputFilename;
std::string outputFilename3;
double total_app_exe_time;
namespace std {
    template <typename T1, typename T2>
    struct hash<std::tuple<T1, T2>> {
        std::size_t operator()(const std::tuple<T1, T2>& t) const {
            return std::hash<T1>{}(std::get<0>(t)) ^ (std::hash<T2>{}(std::get<1>(t)) << 1);
        }
    };
}

//static std::unordered_map<std::tuple< std::tuple<std::string, std::string>, std::tuple<int64_t, int64_t>> , unsigned long long int> argIndexVal_count;
//static std::unordered_map<std::tuple< std::tuple<std::string, std::string>, std::tuple<int64_t, int64_t>> , std::vector<string>> argIndexVal_CallInstrIR;
static std::unordered_map<std::tuple< std::string, std::tuple<int64_t, int64_t> > , unsigned long long int> CallInstr_IndexVal_freq;
static std::unordered_map<std::tuple< std::string, std::tuple<std::string, std::string > > , unsigned long long int> CallInstr_FuncNames_freq;
static std::unordered_map<std::tuple< std::string, std::tuple<std::string, std::string > > , unsigned long long int> CallInfo;
static std::unordered_map<std::string, std::vector<std::tuple<int64_t, int64_t>> > CallInstr_IndexVal_vec;
static std::unordered_map<std::string, std::tuple<int64_t, int64_t>> CallInstr_DIL;
static std::unordered_map<std::string, std::tuple<int64_t, int64_t>> CallInfo_DIL;
static std::unordered_map<std::string, std::string > CallInstr_fileName;
std::map<std::string, int> NumTimesEachFunctionIsCalled;
std::string outputFilename2;
std::map<std::string, unsigned long long int> instructionCounts; // Use unsigned long long int
std::map<std::string, unsigned long long int> NumCalleeCalls; // Use unsigned long long int
std::map<std::string, long long> funcexeTime_map; // Use unsigned long long int
std::map<std::string, long long> funcCall_map; // Use unsigned long long int

extern "C" void incrementInstructionCount(const char* functionName) {
  //std::cout << "functionName: " << functionName << "\n";
  instructionCounts[functionName]++;
}

extern "C" void CallFreqCounter(const char *instrStr, const char* funcNameCaller, const char* funcNameCallee, const char* filename, int64_t line, int64_t col) {
  CallInfo[std::make_tuple( instrStr, std::make_tuple(funcNameCaller,funcNameCallee))]++;
  CallInfo_DIL[instrStr]=std::make_tuple(line,col);
  NumCalleeCalls[funcNameCallee]++;
}




extern "C" void CallFreqProfiler(const char *instrStr, const char* funcNameCaller, const char* funcNameCallee, const char* filename, int64_t line, int64_t col) {
  CallInstr_FuncNames_freq[std::make_tuple( instrStr, std::make_tuple(funcNameCaller,funcNameCallee))]++;
  CallInstr_DIL[instrStr]=std::make_tuple(line,col);
  CallInstr_fileName[instrStr]=filename;
}



extern "C" void ArgValueProfiler(const char *instrStr, const char* funcNameCaller, const char* funcNameCallee, int64_t argIndex, int64_t argValue) {

  CallInstr_IndexVal_freq[std::make_tuple( instrStr, std::make_tuple(argIndex,argValue))]++;
  if (std::find(CallInstr_IndexVal_vec[instrStr].begin(), CallInstr_IndexVal_vec[instrStr].end(), std::make_tuple(argIndex,argValue)) == CallInstr_IndexVal_vec[instrStr].end()) {
    CallInstr_IndexVal_vec[instrStr].push_back(std::make_tuple(argIndex,argValue));
  }
}


/*
extern "C" void ArgValueProfiler(const char *instrStr, const char* funcNameCaller, const char* funcNameCallee, int64_t argIndex, int64_t argValue) {
  NumTimesEachFunctionIsCalled[funcNameCallee]++;
  argIndexVal_count[std::make_tuple(std::make_tuple(funcNameCaller,funcNameCallee),std::make_tuple( argIndex, argValue))]++;
  if (std::find(argIndexVal_CallInstrIR[std::make_tuple(std::make_tuple(funcNameCaller,funcNameCallee),std::make_tuple( argIndex, argValue))].begin(), argIndexVal_CallInstrIR[std::make_tuple(std::make_tuple(funcNameCaller,funcNameCallee),std::make_tuple( argIndex, argValue))].end(), instrStr) == argIndexVal_CallInstrIR[std::make_tuple(std::make_tuple(funcNameCaller,funcNameCallee),std::make_tuple( argIndex, argValue))].end()) {
    argIndexVal_CallInstrIR[std::make_tuple(std::make_tuple(funcNameCaller,funcNameCallee),std::make_tuple( argIndex, argValue))].push_back(instrStr);
  }
  CallInstrIR_freq[instrStr]++;

}
*/
extern "C" void log_execution_time(const char *function_name, long long time_in_ticks) {
/*    FILE *file = fopen("execution_times.txt", "a"); // Open file in append mode
    if (file) {
        fprintf(file, "Function: %s, Time: %lld ticks\n", function_name, time_in_ticks);
        fclose(file); // Close file after writing
    }*/
  //double time_in_seconds = (double)time_in_ticks / CLOCKS_PER_SEC; // Convert ticks to seconds
  funcexeTime_map[function_name]+=time_in_ticks;
  funcCall_map[function_name]++;
  total_app_exe_time+=time_in_ticks;
}


std::map<std::tuple<std::string, std::string>, long long> CallFreq; // Use unsigned long long int
extern "C" void CallCollector( const char* funcNameCaller,  const char *instrStr) {
  CallFreq[std::make_tuple(instrStr, funcNameCaller)]++;
}




void dumpInstructionCounts() {
  std::ofstream outputFile(outputFilename);
  if (outputFile.is_open()) {
    for (const auto& entry : CallFreq) {
      const auto& outer_tuple = entry.first;
      const auto& func_arg_tuple = std::get<0>(outer_tuple);
      const auto& int_tuple = std::get<1>(outer_tuple);
 
      outputFile  << int_tuple << " -----> " << func_arg_tuple <<" ----> " << entry.second << "\n";
    }
/*    outputFile << "----------------------------------------\n\n";
    outputFile << "app total run time: " << total_app_exe_time <<"\n\n";
    outputFile << "log execution time of functions:\n";
  */
    for (const auto& pair : funcexeTime_map) {
      outputFile << "   " << pair.first << ", " << pair.second << ", " << funcCall_map[pair.first] << ", " << pair.second/funcCall_map[pair.first] << ", "<< (pair.second/total_app_exe_time)*100 << std::endl;
    }
    //outputFile << "----------------------------------------\n\n";
 


   // outputFile << "Number of time each function is called:\n";
    for (const auto& pair : NumTimesEachFunctionIsCalled) {
      outputFile << "   " << pair.first << ", " << pair.second << std::endl;
    }
   // outputFile << "----------------------------------------\n";

    //outputFile << "Number of Dynamic Instructions Executed in each function:\n";
    for (const auto& pair : instructionCounts) {
      outputFile << "   " << pair.first << ", " << pair.second << std::endl;
    }
  


//    outputFile << "----------------------------------------\n\n";
    //outputFile << "Value Profiles:\n\n";
  outputFile << "FileName, Caller, Callee, Line, Col, CallFreq, ArgIndex, ArgVal, ArgValFreq, ArgValPred\n";

    

    for (const auto& entry : CallInstr_FuncNames_freq) {
      const auto& outer_tuple = entry.first;
      const auto& callInstr = std::get<0>(outer_tuple);
      const auto& funcNames_tuple = std::get<1>(outer_tuple);
      const auto& Caller = std::get<0>(funcNames_tuple);
      const auto& Callee = std::get<1>(funcNames_tuple);
      if(CallInstr_IndexVal_vec[callInstr].size()> 0){ 
         const auto& callInstrDIL =CallInstr_DIL[callInstr];
         for (int i=0; i< CallInstr_IndexVal_vec[callInstr].size() ; i++) {
             const auto& elem = CallInstr_IndexVal_vec[callInstr][i];
             const auto& callInstArgIndex = std::get<0>(elem);
             const auto& callInstArgVal = std::get<1>(elem);
             float valPred = static_cast<float>(CallInstr_IndexVal_freq[std::make_tuple(callInstr, std::make_tuple(callInstArgIndex,callInstArgVal))]) / entry.second;
             if(valPred> 0.1 )
             outputFile << CallInstr_fileName[callInstr] << ", "<<  Caller << ", " << Callee << ", "<< std::get<0>(callInstrDIL) << ", "<< std::get<1>(callInstrDIL) << ", " <<   entry.second <<  ", " << callInstArgIndex << ", "<< callInstArgVal << ", "<< CallInstr_IndexVal_freq[std::make_tuple(callInstr, std::make_tuple(callInstArgIndex,callInstArgVal))] << ", "<< valPred*100  << "\n";
         }
      }
    }
    //outputFile << "----------------------------------------\n\n";


    for (const auto& entry : CallInfo) {
      const auto& outer_tuple = entry.first;
      const auto& callInstr = std::get<0>(outer_tuple);
      const auto& funcNames_tuple = std::get<1>(outer_tuple);
      const auto& Caller = std::get<0>(funcNames_tuple);
      const auto& Callee = std::get<1>(funcNames_tuple);
      const auto& callInfoDIL =CallInfo_DIL[callInstr];
             outputFile << callInstr << ", "<<  Caller << ", " << Callee << ", "<< std::get<0>(callInfoDIL) << ", "<< std::get<1>(callInfoDIL) << ", " <<   entry.second  << "\n";
    }

 
    //outputFile << "----------------------------------------\n\n";

for (const auto& pair : NumCalleeCalls) {
      outputFile << "   " << pair.first << "  ---> " << pair.second << std::endl;
    }
  


    //outputFile << "----------------------------------------\n";
    outputFile.close();

  } else {
    std::cerr << "Error: Could not open output file:  " << outputFilename << std::endl;
  }

}

void signalHandler(int signum) {
  dumpInstructionCounts();
  exit(signum);
}

extern "C" void writeResultsToFile(const char* filename) {
  //std::cerr << "**********Writing results...\n";
  outputFilename = filename;
  signal(SIGABRT, signalHandler);
  signal(SIGTERM, signalHandler);
  signal(SIGINT, signalHandler);
  signal(SIGSEGV, signalHandler);
  atexit(dumpInstructionCounts);
}



