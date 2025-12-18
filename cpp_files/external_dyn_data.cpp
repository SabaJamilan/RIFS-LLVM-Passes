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
#include <atomic>
#include <thread>
#include <sstream>

using namespace std;
std::string outputFilename;
double total_app_exe_time;
namespace std {
    template <typename T1, typename T2>
    struct hash<std::tuple<T1, T2>> {
        std::size_t operator()(const std::tuple<T1, T2>& t) const {
            return std::hash<T1>{}(std::get<0>(t)) ^ (std::hash<T2>{}(std::get<1>(t)) << 1);
        }
    };
}
std::atomic<bool> running{true};
static int DumpPhaseCounter = 0;
static int DumpPhaseCounter2 = 0;

static std::unordered_map<std::tuple< std::string, std::tuple<std::string, std::string > > , unsigned long long int> CallInfo;
std::map<std::string, unsigned long long int> NumCalleeCalls; // Use unsigned long long int

extern "C" void CallFreqCounter(const char *instrStr, const char* funcNameCaller, const char* funcNameCallee) {
  CallInfo[std::make_tuple( instrStr, std::make_tuple(funcNameCaller,funcNameCallee))]++;
  NumCalleeCalls[funcNameCallee]++;
}


/*
static std::unordered_map<std::string, std::string > Instr_FuncName;

static std::unordered_map<std::string, std::string > Instr_Opcode;
static std::unordered_map<std::string, unsigned long long int > Instr_OpcodeCost;
static std::unordered_map<std::string, unsigned long long int > OpcodeFreq;
static std::unordered_map<std::string, unsigned long long int > OpcodeBaseCost;
*/
static std::unordered_map<std::string, unsigned long long int > FuncSize;

static std::unordered_map<std::tuple< std::string, std::string> , unsigned long long int> Instr_FuncName_Opcode_freq;
static std::unordered_map<std::tuple< std::string, std::string> , unsigned long long int> Instr_OpcodeCost;

extern "C" void InstrExeCounter(const char *instrStr, const char* funcName, int64_t funcSize, const char* Opcode, int64_t OpcodeCost) {
  //Instr_FuncName_Opcode_freq[std::make_tuple(std::make_tuple(instrStr, funcName), Opcode)]++;
  Instr_FuncName_Opcode_freq[std::make_tuple(funcName, Opcode)]++;
  //Instr_FuncName[instrStr]=funcName;
  FuncSize[funcName]=funcSize;
  //Instr_Opcode[instrStr]=Opcode;
  Instr_OpcodeCost[std::make_tuple(funcName, Opcode)]=OpcodeCost;
  //OpcodeFreq[Opcode]++;
  //OpcodeBaseCost[Opcode]=OpcodeCost;
}


void dumpInstructionCounts2(const std::string &filename, const std::string &filename2) {
   std::ofstream out(filename);
   std::ofstream out2(filename2);
/*
for (const auto& [key, value] : Instr_FuncName_Opcode_freq) {
        const auto& [innerTuple, opcode] = key;
        const auto& [Instr, funcName] = innerTuple;

        out<< funcName << ", " << FuncSize[funcName] << ", " << NumCalleeCalls[funcName] << ", "
          << opcode << ", " << Instr_OpcodeCost[Instr] << ", " << value << "\n";
     //out << Instr_FuncName[Instr]<< ", " << FuncSize[Instr_FuncName[Instr]] << ", " << NumCalleeCalls[Instr_FuncName[Instr]]<< ", " << Instr_Opcode[Instr] << ", " <<  Instr_OpcodeCost[Instr] << ", "<< entry.second << ", " << Instr_OpcodeCost[Instr]*entry.second <<"\n";

    }*/
 // Iterate and read elements
    for (const auto& [key, value] : Instr_FuncName_Opcode_freq) {
        const auto& [first, second] = key;
        out  << first << ", " << second << ", " << Instr_OpcodeCost[key]  <<", "<< value << ", " << FuncSize[first] << ", "<<  NumCalleeCalls[first] << "\n";
    }


    for (const auto& entry : CallInfo) {
      const auto& outer_tuple = entry.first;
      const auto& callInstr = std::get<0>(outer_tuple);
      const auto& funcNames_tuple = std::get<1>(outer_tuple);
      const auto& Caller = std::get<0>(funcNames_tuple);
      const auto& Callee = std::get<1>(funcNames_tuple);
      out2 << Caller << ", " << Callee  << ", " <<   entry.second << ", " << NumCalleeCalls[Callee] << "\n";
    }



 
}

void dumpInstructionCounts() {
  std::ofstream outputFile(outputFilename);
  if (outputFile.is_open()) {
    std::cerr << "Error: Opend output file:  " << outputFilename << std::endl;
/*
for (const auto& [key, value] : Instr_FuncName_Opcode_freq) {
        const auto& [innerTuple, opcode] = key;
        const auto& [Instr, funcName] = innerTuple;

        outputFile << funcName << ", " << FuncSize[funcName] << ", " << NumCalleeCalls[funcName] << ", "
          << opcode << ", " << Instr_OpcodeCost[Instr] << ", " << value << "\n";
     //out << Instr_FuncName[Instr]<< ", " << FuncSize[Instr_FuncName[Instr]] << ", " << NumCalleeCalls[Instr_FuncName[Instr]]<< ", " << Instr_Opcode[Instr] << ", " <<  Instr_OpcodeCost[Instr] << ", "<< entry.second << ", " << Instr_OpcodeCost[Instr]*entry.second <<"\n";

    }*/
    // Iterate and read elements
    for (const auto& [key, value] : Instr_FuncName_Opcode_freq) {
        const auto& [first, second] = key;
        outputFile  << first << ", " << second << ", " << Instr_OpcodeCost[key]  <<", "<< value << ", "<< FuncSize[first] << ", "<<  NumCalleeCalls[first] << "\n";
    }


/*
    for (const auto& entry :Instr_FuncName_freq) {
     const auto& outer_tuple = entry.first;
     const auto& Instr = std::get<0>(outer_tuple);
     const auto& funcName = std::get<1>(outer_tuple);
     outputFile << Instr_FuncName[Instr]<< ", " << FuncSize[Instr_FuncName[Instr]] << ", " << NumCalleeCalls[Instr_FuncName[Instr]]<< ", " << Instr_Opcode[Instr] << ", " <<  Instr_OpcodeCost[Instr] << ", "<< entry.second << ", " << Instr_OpcodeCost[Instr]*entry.second <<"\n";

    }*/
    outputFile << "------------------------------------------------\n";
    for (const auto& entry : CallInfo) {
      const auto& outer_tuple = entry.first;
      const auto& callInstr = std::get<0>(outer_tuple);
      const auto& funcNames_tuple = std::get<1>(outer_tuple);
      const auto& Caller = std::get<0>(funcNames_tuple);
      const auto& Callee = std::get<1>(funcNames_tuple);
      outputFile << Caller << ", " << Callee  << ", " <<   entry.second << ", " << NumCalleeCalls[Callee] << "\n";
    }
    outputFile.close();

  } else {
    std::cerr << "Error: Could not open output file:  " << outputFilename << std::endl;
  }

}

void periodicDumper() {
 while (running) {
   std::this_thread::sleep_for(std::chrono::seconds(200));
   //std::this_thread::sleep_for(std::chrono::seconds(2000));

    // Create a timestamped file name
    auto now = std::time(nullptr);
    std::stringstream ss;
    std::stringstream ss2;
    ss << "dynamic_instr_dump_" << DumpPhaseCounter++ << ".txt";
    ss2 << "callFreq_info_dump_" <<  DumpPhaseCounter2++ << ".txt";
    std::cout <<"fileName: "<<  ss.str() << ","<< ss2.str() << "\n";
    dumpInstructionCounts2(ss.str(), ss2.str());
 }
}

void signalHandler(int signum) {
  dumpInstructionCounts();
  exit(signum);
}

void shutdownHandler() {
  running = false;
  //dumpInstructionCounts("instr_dump_final.txt");  // Final dump
  dumpInstructionCounts();  // Final dump
}

extern "C" void writeResultsToFile(const char* filename) {
  std::cerr << "**********Writing results...\n";
  std::cout<< "filename : "  << filename << "\n";
  outputFilename = filename;
  std::thread dumperThread(periodicDumper);
  
  dumperThread.detach();  // Run in background
                        //
  signal(SIGABRT, signalHandler);
  signal(SIGTERM, signalHandler);
  signal(SIGINT, signalHandler);
  signal(SIGSEGV, signalHandler);
 // atexit(dumpInstructionCounts);
  atexit(shutdownHandler);

}



