#include "llvm/Passes/PassPlugin.h" 
#include "llvm/Passes/PassBuilder.h"  
#include "llvm/IR/PassManager.h"      
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/IR/Module.h"
#include <fstream> 
#include "llvm/IR/Constants.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Type.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/FileSystem.h"
#include <map>
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Module.h"           
#include "llvm/IR/Constants.h"        
#include "llvm/IR/IRBuilder.h"        
#include "llvm/IR/Type.h"    
#include <sstream>

using namespace llvm;

static cl::opt<std::string> targetFunctionName("targetFunctionName", cl::desc("the input filename that specifies Target Function Names to do value profiling"), cl::value_desc("name"));
static cl::opt<int> IndexVal("index", cl::desc("indexval"), cl::value_desc("indexval"));
static cl::opt<std::string> binaryName("binaryName", cl::desc("binary Name"), cl::value_desc("name"));

static cl::opt<bool> EnablePrint(
    "enable-print", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

static cl::opt<bool> EnableValueProfile(
    "enable-value-profiling", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

static cl::opt<bool> EnableCountNumberTimesEachFuncCalled(
    "enable-times-funcs-called", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);


static cl::opt<bool> EnableStaticInstructionsCountperFunction(
    "enable-static-instrs-count", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

static cl::opt<bool> EnableDynamicInstrsCountPerFunction(
    "enable-dynmic-instrs-count", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

static cl::opt<bool> ExeTimePerFunction(
    "enable-func-exe-time", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

static cl::opt<bool> CollectCallsToTarget(
    "enable-collect-calls", // Command-line flag name
    cl::desc("Enable printing argument values"), // Description
    cl::init(false) // Default value: false (disabled)
);

bool alreadyread;



namespace {
struct PrintArgsPass : public PassInfoMixin<PrintArgsPass> {
     GlobalVariable *CounterArray;
     // Get or create a global format string for printf
     
     GlobalVariable *getOrCreatePrintfFormat(Module &M, const char *Fmt) {
       LLVMContext &Ctx = M.getContext();
       // Check if format string already exists
       if (GlobalVariable *GVar = M.getNamedGlobal(Fmt)) {
         return GVar;
       }
       // Create a new global string constant
       Constant *StrConst = ConstantDataArray::getString(Ctx, Fmt, true);
       // Create a global variable for the format string
       GlobalVariable *GVar = new GlobalVariable(
            M,
            StrConst->getType(),
            true,                            // Constant
            GlobalValue::PrivateLinkage,     // Private to module
            StrConst,
            Fmt                              // Name
       );
       return GVar;
     }

     // Get or create the printf function
     FunctionCallee getOrCreatePrintfFunction(Module &M) {
       LLVMContext &Ctx = M.getContext();
       return M.getOrInsertFunction(
           "printf",
            FunctionType::get(
                IntegerType::get(Ctx, 32),  // Return type: int
                PointerType::get(IntegerType::get(Ctx, 8), 0),  // First argument: i8*
                true  // Variadic function
            )
        );
     }
    


      PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
        LLVMContext &Ctx = M.getContext();
        FunctionCallee PrintfFunc = getOrCreatePrintfFunction(M);

        std::vector<std::string> FunctionsToProfileName;
        if(!targetFunctionName.empty() && !alreadyread){
          std::ifstream file;
          file.open(targetFunctionName);
          std::string line;
          while (getline(file, line)) {
            std::stringstream linestream(line);
            std::string FuncName;
            getline(linestream, FuncName, '\n');
            FunctionsToProfileName.push_back(FuncName);
          }
          alreadyread = true;
        }


        for (const auto &elem : FunctionsToProfileName) {
          errs() << "Func: " << elem << "\n";
        }

        FunctionCallee WriteFunc = M.getOrInsertFunction(
            "writeResultsToFile",
            FunctionType::get(Type::getVoidTy(Ctx),Type::getInt8Ty(Ctx)->getPointerTo(0), false)
            );

        //////////////////////////////////////////////
        /// static instructions count per function
         if (EnableStaticInstructionsCountperFunction) {
        std::error_code EC;
        llvm::raw_fd_ostream File("NumberOFStaticInstr_per_Function_" + binaryName + ".txt", EC, llvm::sys::fs::OF_Text);

        if (EC) {
          llvm::errs() << "Error opening file: " << EC.message() << "\n";
        }
        for (Function &F : M) {
          if (!F.isDeclaration()) { // Skip function declarations
             int instructionCount = 0;
             for (BasicBlock &BB : F) {
               for (Instruction &I : BB) {
                 instructionCount++;
               }
             }

             llvm::outs() << format("Function: %-30s #Static Instructions: %d\n", F.getName().str().c_str(), instructionCount);
             File << format("Function: %-30s #Static Instructions: %d\n", F.getName().str().c_str(), instructionCount);
          }
       }
       File.close();
         }
        //////////////////////////////////////////////
        /////////// dynamic instructions count
        if (EnableDynamicInstrsCountPerFunction) {
        FunctionType *IncrementInstCountFuncType = FunctionType::get(Type::getVoidTy(Ctx), Type::getInt8Ty(Ctx)->getPointerTo(0), false);
        FunctionCallee IncrementInstCountFunc = M.getOrInsertFunction("incrementInstructionCount", IncrementInstCountFuncType);

/*        FunctionCallee WriteFunc = M.getOrInsertFunction(
            "writeResultsToFile",
            FunctionType::get(Type::getVoidTy(Ctx),Type::getInt8Ty(Ctx)->getPointerTo(0), false)
            );
*/
        // Check if function name contains the target string
        for (Function &F : M) {
          if (!F.isDeclaration()) { // Skip function declarations
         //     if (F.getName().str().find(targetFunctionName) != std::string::npos) {
           bool matchesTarget = std::any_of(
               FunctionsToProfileName.begin(), FunctionsToProfileName.end(),
               [&](const std::string &name) {
               return F.getName().str().find(name) != std::string::npos;
               });
           if (matchesTarget) {
                errs() << "Found: " << F.getName() << " targetString: " << targetFunctionName << "\n";
                for (BasicBlock &BB : F) {
                  for (Instruction &I : BB) {
                    if (isa<PHINode>(&I)) 
                      continue;
                    IRBuilder<> Builder(&I);
                    Constant *FunctionNameConst = ConstantDataArray::getString(Ctx, F.getName());
                    GlobalVariable *FunctionNameGlobal = new GlobalVariable(
                      M, FunctionNameConst->getType(), true,
                      GlobalValue::PrivateLinkage, FunctionNameConst, "functionName");
                    Constant *FunctionNamePtr = ConstantExpr::getPointerCast(
                      FunctionNameGlobal, Type::getInt8Ty(Ctx)->getPointerTo(0));
                    Builder.CreateCall(IncrementInstCountFunc, FunctionNamePtr);
                  }
                }
              }
          }
        }
        }

        ////////////
        /////////// CallFreqCounter
        if (EnableCountNumberTimesEachFuncCalled) {
        FunctionCallee CallFreqFunc = M.getOrInsertFunction(
            "CallFreqCounter",
            FunctionType::get(Type::getVoidTy(Ctx),
              {PointerType::get(IntegerType::get(Ctx, 8), 0), // Call instruction
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Caller Function name as char*
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Callee Function name as char*
              PointerType::get(IntegerType::get(Ctx, 8), 0), // Call instruction
               Type::getInt32Ty(Ctx),
                Type::getInt32Ty(Ctx)},
              false));


        IRBuilder<> Builder(Ctx);
        for (Function &F : M) {
          if (!F.isDeclaration()) { // Skip function declarations   
              for (auto &BB : F) {
                for (auto &I : BB) {
                  if (auto *Call = dyn_cast<CallInst>(&I)) {
                    Function *CalleeFunc = Call->getCalledFunction();
                    if (!CalleeFunc)
                      continue;

                    bool matchesTarget = std::any_of(
                        FunctionsToProfileName.begin(), FunctionsToProfileName.end(),
                        [&](const std::string &name) {
                        return CalleeFunc->getName().str().find(name) != std::string::npos;
                        });
                    if (matchesTarget) {
                    //if (CalleeFunc->getName().str().find(targetFunctionName) != std::string::npos) {
                      Function *CallerFunc = Call->getFunction();
                      if (!CallerFunc)
                       continue;
                      errs() << "Found Call instr: " << *Call << "\n";
                      //if (Call->arg_size() >= IndexVal+1 && CalleeFunc->getName() != "ArgValueProfiler" && CalleeFunc->getName() !="incrementInstructionCount") {
                      if (CalleeFunc->getName() != "ArgValueProfiler" && CalleeFunc->getName() !="incrementInstructionCount") {
                        /////////////////////////////////////////////////////////////////////
                        ///// to count the number of times the call is executed dynamically
                        ///////////////////////////////////////////////////////////////////// 
                        /////// Caller Name
                         std::string FuncNameStr = F.getName().str();
                         Constant *FuncNameConst = ConstantDataArray::getString(Ctx, FuncNameStr, true);
                         // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobal = new GlobalVariable(
                           M,
                           FuncNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConst,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtr = Builder.CreateBitCast(FuncNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        ///////////
                        
                        ///Callee name
                         std::string FuncNameStrCallee = (Call->getCalledFunction())->getName().str();
                         Constant *FuncNameConstCallee = ConstantDataArray::getString(Ctx, FuncNameStrCallee, true);
                      // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobalCallee = new GlobalVariable(
                           M,
                           FuncNameConstCallee->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConstCallee,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtrCallee = Builder.CreateBitCast(FuncNameGlobalCallee,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));

                        /////////
                        //Call instruction:
                        std::string instrStr;
                        raw_string_ostream rso(instrStr);
                        Call->print(rso);  // Print instruction to string
                        Constant *InstrStrConst = ConstantDataArray::getString(Ctx, instrStr, true);
                        GlobalVariable *InstrStrGlobal = new GlobalVariable(
                            M, 
                            InstrStrConst->getType(),
                            true,
                            GlobalValue::PrivateLinkage, InstrStrConst,
                            "instr_str"
                        );

                        std::string fileName;
                        unsigned line;
                        unsigned col;
                        ///// DILocation for call
                        if (DILocation *loc = Call->getDebugLoc()) {
                          fileName = loc->getFilename().str();
                          line = loc->getLine();
                          col = loc->getColumn();
                          errs() << F.getName() << ", " << fileName << ", " << line << ", " << col << "\n";
                        }
                         Constant *FileNameConst = ConstantDataArray::getString(Ctx, fileName, true);
                         GlobalVariable *FileNameGlobal = new GlobalVariable(
                           M,
                           FileNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FileNameConst,
                           "file_name"
                        );
                        // Convert to pointer
                        Value *FileNamePtr = Builder.CreateBitCast(FileNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        llvm::Type* Int32Ty = llvm::Type::getInt32Ty(Ctx);
                        llvm::Value* LineVal = llvm::ConstantInt::get(Int32Ty, line, true); // Create a llvm constant int
                        llvm::Value* CastedLineVal = Builder.CreateIntCast(LineVal, Int32Ty, true);
                        llvm::Value* ColVal = llvm::ConstantInt::get(Int32Ty, col, true); // Create a llvm constant int
                        llvm::Value* CastedColVal = Builder.CreateIntCast(ColVal, Int32Ty, true);





/////////////
                        Value *InstrStrPtr = Builder.CreateBitCast(InstrStrGlobal, PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        Builder.SetInsertPoint(Call->getNextNode());
                        Builder.CreateCall(CallFreqFunc, {InstrStrPtr, FuncNamePtr,FuncNamePtrCallee, FileNameGlobal, CastedLineVal, CastedColVal});
                      }
                    }
                    }
                    }
                  }
                }
              }
          }

///////////////
///
///
///
//
        //////////////////////////////////////////////
        /////////// Argument Value Profiler
        if (EnableValueProfile) {
        FunctionCallee UpdateArg2CountFunc = M.getOrInsertFunction(
            "ArgValueProfiler",
            FunctionType::get(Type::getVoidTy(Ctx),
              {PointerType::get(IntegerType::get(Ctx, 8), 0), // Call instruction
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Caller Function name as char*
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Callee Function name as char*
               Type::getInt32Ty(Ctx), // //Argument Index
               Type::getInt32Ty(Ctx)}, //Argument Value
               false));
        FunctionCallee CallFreqProfilerFunc = M.getOrInsertFunction(
            "CallFreqProfiler",
            FunctionType::get(Type::getVoidTy(Ctx),
              {PointerType::get(IntegerType::get(Ctx, 8), 0), // Call instruction
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Caller Function name as char*
               PointerType::get(IntegerType::get(Ctx, 8), 0), // Callee Function name as char*
              PointerType::get(IntegerType::get(Ctx, 8), 0), // Call instruction
               Type::getInt32Ty(Ctx),
                Type::getInt32Ty(Ctx)},
              false));


        IRBuilder<> Builder(Ctx);
        for (Function &F : M) {
          if (!F.isDeclaration()) { // Skip function declarations   
              for (auto &BB : F) {
                for (auto &I : BB) {
                  if (auto *Call = dyn_cast<CallInst>(&I)) {
                    Function *CalleeFunc = Call->getCalledFunction();
                    if (!CalleeFunc)
                      continue;

                    bool matchesTarget = std::any_of(
                        FunctionsToProfileName.begin(), FunctionsToProfileName.end(),
                        [&](const std::string &name) {
                        return CalleeFunc->getName().str().find(name) != std::string::npos;
                        });
                    if (matchesTarget) {
                    //if (CalleeFunc->getName().str().find(targetFunctionName) != std::string::npos) {
                      Function *CallerFunc = Call->getFunction();
                      if (!CallerFunc)
                       continue;
                      errs() << "Found Call instr: " << *Call << "\n";
                      //if (Call->arg_size() >= IndexVal+1 && CalleeFunc->getName() != "ArgValueProfiler" && CalleeFunc->getName() !="incrementInstructionCount") {
                      if (CalleeFunc->getName() != "ArgValueProfiler" && CalleeFunc->getName() !="incrementInstructionCount") {
                        /////////////////////////////////////////////////////////////////////
                        ///// to count the number of times the call is executed dynamically
                        ///////////////////////////////////////////////////////////////////// 
                        /////// Caller Name
                         std::string FuncNameStr = F.getName().str();
                         Constant *FuncNameConst = ConstantDataArray::getString(Ctx, FuncNameStr, true);
                         // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobal = new GlobalVariable(
                           M,
                           FuncNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConst,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtr = Builder.CreateBitCast(FuncNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        ///////////
                        
                        ///Callee name
                         std::string FuncNameStrCallee = (Call->getCalledFunction())->getName().str();
                         Constant *FuncNameConstCallee = ConstantDataArray::getString(Ctx, FuncNameStrCallee, true);
                      // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobalCallee = new GlobalVariable(
                           M,
                           FuncNameConstCallee->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConstCallee,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtrCallee = Builder.CreateBitCast(FuncNameGlobalCallee,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));

                        /////////
                        //Call instruction:
                        std::string instrStr;
                        raw_string_ostream rso(instrStr);
                        Call->print(rso);  // Print instruction to string
                        Constant *InstrStrConst = ConstantDataArray::getString(Ctx, instrStr, true);
                        GlobalVariable *InstrStrGlobal = new GlobalVariable(
                            M, 
                            InstrStrConst->getType(),
                            true,
                            GlobalValue::PrivateLinkage, InstrStrConst,
                            "instr_str"
                        );

                        std::string fileName;
                        unsigned line;
                        unsigned col;
                        ///// DILocation for call
                        if (DILocation *loc = Call->getDebugLoc()) {
                          fileName = loc->getFilename().str();
                          line = loc->getLine();
                          col = loc->getColumn();
                          errs() << F.getName() << ", " << fileName << ", " << line << ", " << col << "\n";
                        }
                         Constant *FileNameConst = ConstantDataArray::getString(Ctx, fileName, true);
                         GlobalVariable *FileNameGlobal = new GlobalVariable(
                           M,
                           FileNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FileNameConst,
                           "file_name"
                        );
                        // Convert to pointer
                        Value *FileNamePtr = Builder.CreateBitCast(FileNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        llvm::Type* Int32Ty = llvm::Type::getInt32Ty(Ctx);
                        llvm::Value* LineVal = llvm::ConstantInt::get(Int32Ty, line, true); // Create a llvm constant int
                        llvm::Value* CastedLineVal = Builder.CreateIntCast(LineVal, Int32Ty, true);
                        llvm::Value* ColVal = llvm::ConstantInt::get(Int32Ty, col, true); // Create a llvm constant int
                        llvm::Value* CastedColVal = Builder.CreateIntCast(ColVal, Int32Ty, true);





/////////////
                        Value *InstrStrPtr = Builder.CreateBitCast(InstrStrGlobal, PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        Builder.SetInsertPoint(Call->getNextNode());
                        Builder.CreateCall(CallFreqProfilerFunc, {InstrStrPtr, FuncNamePtr,FuncNamePtrCallee, FileNameGlobal, CastedLineVal, CastedColVal});



                        //////////// 
 

                        //// to profile values for all arguments://////
                        for (unsigned i = 0; i < Call->arg_size(); ++i) {
                            Value *Arg = Call->getArgOperand(i);
                            int ArgIndex = i;
                         

                         errs() << "    Profiling for Arg "<< ArgIndex << " of Func: "<< CalleeFunc->getName() <<" ...\n";
                         ///////////////////////////////////////////////
                         //Value *Arg = Call->getArgOperand(IndexVal);
                         //int ArgIndex = IndexVal;
                        
                         /////// Caller Name
                         std::string FuncNameStr = F.getName().str();
                         Constant *FuncNameConst = ConstantDataArray::getString(Ctx, FuncNameStr, true);
                         // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobal = new GlobalVariable(
                           M,
                           FuncNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConst,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtr = Builder.CreateBitCast(FuncNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
                        ///////////
                        
                        ///Callee name
                         std::string FuncNameStrCallee = (Call->getCalledFunction())->getName().str();
                         Constant *FuncNameConstCallee = ConstantDataArray::getString(Ctx, FuncNameStrCallee, true);
                      // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobalCallee = new GlobalVariable(
                           M,
                           FuncNameConstCallee->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConstCallee,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtrCallee = Builder.CreateBitCast(FuncNameGlobalCallee,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));

                        /////////
                        //Call instruction:
                        std::string instrStr;
                        raw_string_ostream rso(instrStr);
                        Call->print(rso);  // Print instruction to string
                        Constant *InstrStrConst = ConstantDataArray::getString(Ctx, instrStr, true);
                        GlobalVariable *InstrStrGlobal = new GlobalVariable(
                            M, 
                            InstrStrConst->getType(),
                            true,
                            GlobalValue::PrivateLinkage, InstrStrConst,
                            "instr_str"
                        );
                        Value *InstrStrPtr = Builder.CreateBitCast(InstrStrGlobal, PointerType::get(IntegerType::getInt8Ty(Ctx), 0));

                        //////////// 
                        // ArgIndex and ArgVal
                        if (!Arg->getType()->isIntegerTy()) 
                          continue;
                     
                        llvm::Type* Int32Ty = llvm::Type::getInt32Ty(Ctx);
                        llvm::Value* ArgIndexValue = llvm::ConstantInt::get(Int32Ty, ArgIndex, true); // Create a llvm constant int
                        llvm::Value* CastedArgIndex = Builder.CreateIntCast(ArgIndexValue, Int32Ty, true);


                        Builder.SetInsertPoint(Call->getNextNode());
                        Value *ArgVal = Builder.CreateSExtOrTrunc(Arg, Type::getInt32Ty(Ctx));
                        //Builder.CreateCall(UpdateArg2CountFunc, {FuncNamePtr, ArgVal});
                        Builder.CreateCall(UpdateArg2CountFunc, {InstrStrPtr, FuncNamePtr,FuncNamePtrCallee, CastedArgIndex, ArgVal});
                       }// all arguments
                        
                    }
                  
                ///////////////////////////////////////////////////////////
                    // Create format string for "caller, callee, arg_index, arg_value"
                    if (EnablePrint) {
                      //GlobalVariable *FmtVar = getOrCreatePrintfFormat(*M, "%s, %s, %d, %d\n");
                      GlobalVariable *FmtVar = getOrCreatePrintfFormat(M, "%s, %s, %d, %d\n");
                      // Convert function names to i8* (C strings)
                      Value *CallerName = Builder.CreateGlobalStringPtr(CallerFunc->getName());
                      Value *CalleeName = Builder.CreateGlobalStringPtr(CalleeFunc->getName());
                      //Correctly get i8* type
                      Value *FmtStrPtr = Builder.CreateBitCast(FmtVar, PointerType::get(IntegerType::get(Ctx, 8), 0));
                      for (unsigned i = 0; i < Call->arg_size(); ++i) {
                        Value *Arg = Call->getArgOperand(i);
                        if (!Arg->getType()->isIntegerTy()) {
                            continue; // Only print integer arguments
                        }
                        ////////// printing the values for all arguments
                        /*// Create the argument index value
                        Value *IndexVal = ConstantInt::get(IntegerType::get(Ctx, 32), i);
                        // Print "caller -> callee, arg_index: arg_value"
                        Builder.CreateCall(PrintfFunc, {FmtStrPtr, CallerName, CalleeName, IndexVal, Arg});*/
                       
                        //Only print argument index 2
                        // Only print if enabled
                        //if (EnablePrint) {
                        if (Call->arg_size() > 2) {  // Ensure there is an argument at index 2
                            Value *Arg = Call->getArgOperand(2);
                            if (Arg->getType()->isIntegerTy()) {  // Only print integer arguments
                               Value *IndexVal = ConstantInt::get(IntegerType::get(Ctx, 32), 2);
                               Builder.CreateCall(PrintfFunc, {FmtStrPtr, CallerName, CalleeName, IndexVal, Arg});
                            }
                        }
                      }
                      }
                    }
                }
            }
           }
           }
        }
          }
        ////////////////////////////////////////////////////
/*
 * clock() returns the processor time consumed by the program as the number of clock ticks since the program started running.
The type of the return value is clock_t, and it represents time in clock ticks.*/

        if(ExeTimePerFunction){
        // Declare the external logging function (log_execution_time)
        FunctionType *LogFuncType = FunctionType::get(Type::getVoidTy(Ctx), 
                                                      {PointerType::get(Type::getInt8Ty(Ctx), 0), 
                                                       Type::getInt64Ty(Ctx)}, false);
        FunctionCallee LogFunction = M.getOrInsertFunction("log_execution_time", LogFuncType);

        // Declare clock() function to measure time at runtime
        FunctionType *ClockType = FunctionType::get(Type::getInt64Ty(Ctx), false);
        FunctionCallee ClockFunc = M.getOrInsertFunction("clock", ClockType);

        for (Function &F : M) {
            if(F.isDeclaration()) // Skip external function declarations
                continue;

          //  if(F.getName().str().find(targetFunctionName) != std::string::npos) {
               IRBuilder<> Builder(&*F.getEntryBlock().getFirstInsertionPt());
               // Insert call to clock() at the beginning of the function to get the start time
               Value *StartTime = Builder.CreateCall(ClockFunc, {}, "start_time");
               for (BasicBlock &BB : F) {
                  if (ReturnInst *Ret = dyn_cast<ReturnInst>(BB.getTerminator())) {
                     Builder.SetInsertPoint(Ret);
                     // Insert call to clock() at the function exit to get the end time
                     Value *EndTime = Builder.CreateCall(ClockFunc, {}, "end_time");
                     // Calculate elapsed time: end_time - start_time
                     Value *ElapsedTime = Builder.CreateSub(EndTime, StartTime, "elapsed_time");
                     // Pass function name and elapsed time to the external logging function
                     Value *FunctionName = Builder.CreateGlobalStringPtr(F.getName());
                     Builder.CreateCall(LogFunction, {FunctionName, ElapsedTime});
                  }
                }
            // }
           }
        }

        if(CollectCallsToTarget){
          IRBuilder<> Builder(Ctx);
           FunctionCallee CallCollectorFunc = M.getOrInsertFunction(
            "CallCollector",
            FunctionType::get(Type::getVoidTy(Ctx),
              {PointerType::get(IntegerType::get(Ctx, 8), 0), // Caller Function name as char*
              PointerType::get(IntegerType::get(Ctx, 8), 0)}, // Call instruction
               false));


          for (Function &F : M) {
            if (!F.isDeclaration()) { // Skip function declarations   
              for (auto &BB : F) {
                for (auto &I : BB) {
                  if (auto *Call = dyn_cast<CallInst>(&I)) {
                    Function *CalleeFunc = Call->getCalledFunction();
                    if (!CalleeFunc)
                      continue;
                    bool matchesTarget = std::any_of(
                        FunctionsToProfileName.begin(), FunctionsToProfileName.end(),
                        [&](const std::string &name) {
                        return CalleeFunc->getName().str().find(name) != std::string::npos;
                        });
                    if (matchesTarget) {
                    //if (CalleeFunc->getName().str().find(targetFunctionName) != std::string::npos) {
                      Function *CallerFunc = Call->getFunction();
                      if (!CallerFunc)
                       continue;
                      errs() << "Found Call instr: " << CallerFunc->getName() << " -> " << CalleeFunc->getName() << "\n";
                        /////////

                        //Call instruction:
                      std::string instrStr;
                        raw_string_ostream rso(instrStr);
                        Call->print(rso);  // Print instruction to string
                        Constant *InstrStrConst = ConstantDataArray::getString(Ctx, instrStr, true);
                        GlobalVariable *InstrStrGlobal = new GlobalVariable(
                            M, 
                            InstrStrConst->getType(),
                            true,
                            GlobalValue::PrivateLinkage, InstrStrConst,
                            "instr_str"
                        );
                        Value *InstrStrPtr = Builder.CreateBitCast(InstrStrGlobal, PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
//                      Value *FunctionName = Builder.CreateGlobalStringPtr(F.getName());
                         std::string FuncNameStr = F.getName().str();
                         Constant *FuncNameConst = ConstantDataArray::getString(Ctx, FuncNameStr, true);
                         // Create a global variable to hold the string
                         GlobalVariable *FuncNameGlobal = new GlobalVariable(
                           M,
                           FuncNameConst->getType(),
                           true, // Is constant
                           GlobalValue::PrivateLinkage,
                           FuncNameConst,
                           "func_name"
                        );
                        // Convert to pointer
                        Value *FuncNamePtr = Builder.CreateBitCast(FuncNameGlobal,PointerType::get(IntegerType::getInt8Ty(Ctx), 0));
 


                      Builder.SetInsertPoint(Call->getNextNode());
                      Builder.CreateCall(CallCollectorFunc, {FuncNamePtr, InstrStrPtr});
                    }
                  }
                }
              }
            }
          }
        }
        ////////////////////////////////////////////////////
        ////////////////////////////////////////////////////
        Function *MainFunc = M.getFunction("main");
        if (MainFunc) {
             IRBuilder<> Builder(Ctx);
             Builder.SetInsertPoint(M.getFunction("main")->getEntryBlock().getFirstNonPHI());
             std::string filename = "value_profile_" + binaryName + ".txt"; // Modify filename
             llvm::StringRef FilenameStr(filename);  // Convert back to StringRef if needed

             Constant *OutputFilenameConst = ConstantDataArray::getString(Ctx, FilenameStr, true);
             ArrayType *FilenameType = ArrayType::get(IntegerType::get(Ctx, 8), FilenameStr.size() + 1); 
             GlobalVariable *OutputFilenameGlobal = new GlobalVariable(
                 M, 
                 FilenameType,
                 true, // Is constant
                 GlobalValue::PrivateLinkage,
                 OutputFilenameConst,
                 "outputFilename"
                 );
             Constant *OutputFilenamePtr = ConstantExpr::getPointerCast(
             OutputFilenameGlobal, Type::getInt8Ty(Ctx)->getPointerTo(0));
             Builder.CreateCall(WriteFunc, OutputFilenamePtr);
        }
 


        /////////////////////////////////////////////////
       //if (modified){
         return llvm::PreservedAnalyses::none();
       /*}
       else{
         return llvm::PreservedAnalyses::all();
       }*/



      }
  };
} // namespace

//------------------------------------------------------------------------------
// New PM Registration
//------------------------------------------------------------------------------
// Register the pass
llvm::PassPluginLibraryInfo getInstructionCountPassPassPluginInfo() {
    return {LLVM_PLUGIN_API_VERSION, "PrintArgsPass", LLVM_VERSION_STRING,
            [](PassBuilder &PB) {
                PB.registerPipelineParsingCallback(
                    //[](StringRef Name, FunctionPassManager &FPM, ArrayRef<PassBuilder::PipelineElement>) {
                    [](StringRef Name, ModulePassManager &MPM, ArrayRef<PassBuilder::PipelineElement>) {
                        if (Name == "print-args") {
                            //FPM.addPass(PrintArgsPass());
                            MPM.addPass(PrintArgsPass());
                            return true;
                        }
                        return false;
                    });
            }};
}

extern "C" llvm::PassPluginLibraryInfo llvmGetPassPluginInfo() {
    return getInstructionCountPassPassPluginInfo();
}
