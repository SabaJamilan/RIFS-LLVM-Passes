///////////////// included libraries for LLVM 20.0.0 ////////////////////////
#include "llvm/ProfileData/FunctionId.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/IR/Instructions.h"  // <- Important for TerminatorInst
////////////////////////////////////////////////////////////////////////////
#include "llvm/Transforms/IPO/FunctionSpecialization.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/CodeMetrics.h"
#include "llvm/Analysis/InlineCost.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/Analysis/ValueLattice.h"
#include "llvm/Analysis/ValueLatticeUtils.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/Transforms/Scalar/SCCP.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/SCCPSolver.h"
#include "llvm/Transforms/Utils/SizeOpts.h"
#include <cctype>
#include <cmath>
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/ValueMap.h"
#include "llvm/Pass.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/ProfileData/SampleProf.h"
#include "llvm/ProfileData/SampleProfReader.h"
#include "llvm/Transforms/IPO/SampleProfile.h"
#include "llvm/Analysis/LoopInfo.h"
#include <string>
#include <sstream>
#include <vector>
#include <fstream>
#include <iostream>
#include <bits/stdc++.h>
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iterator>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
#include "llvm/IR/MDBuilder.h"
using namespace llvm;
using namespace std;
using namespace sampleprof;


#define DEBUG_TYPE "FuncSpecPassIRSwitchCaseV3"
STATISTIC(NumFuncSpecialized, "Number of functions specialized");

static cl::opt<std::string> Profile("input-file", cl::desc("Specify the input Profile "), cl::value_desc("ProfileName"));
static cl::opt<unsigned> ValPredThrd( "ValPredThreshold", cl::Hidden, cl::desc("Don't specialize functions that value predictibilty is less than this threshold"), cl::init(10));
static cl::opt<unsigned> NumOFDepInstrThrd("NumOFDepInstrThreshold", cl::Hidden, cl::desc("Number of instructions dependent to the value invariant argument"), cl::init(1));
//static cl::opt<unsigned> profileNum("profileNum", cl::Hidden, cl::desc("Number ID of Profile Candidate"), cl::init(1));
static cl::opt<double> profileNum("profileNum", cl::Hidden, cl::desc("Number ID of Profile Candidate"), cl::init(1));
static cl::opt<std::string> benchmarkName("benchmarkName", cl::desc("Specify the benchmark Name "), cl::value_desc("benchmarkName"));

struct ProfileEntry {
    std::string file;
    std::string function_caller;
    std::string function_callee;
    unsigned line;
    unsigned column;
    uint64_t callFreq;
    uint64_t argIndex;
    uint64_t argValue;
    uint64_t valFreq;
    uint64_t predictability;
};
std::vector<ProfileEntry> ProfileEntriesVec;
std::vector<std::string> CallerFuncNamesVec ;

struct LocationKeyHash {
    std::size_t operator()(const std::tuple<std::string, unsigned, unsigned, std::string, std::string>& key) const {
        const auto& [file, line, col, caller, callee] = key;
        std::size_t h1 = std::hash<std::string>()(file);
        std::size_t h2 = std::hash<unsigned>()(line);
        std::size_t h3 = std::hash<unsigned>()(col);
        std::size_t h4 = std::hash<std::string>()(caller);
        std::size_t h5 = std::hash<std::string>()(callee);
        return (((((h1 ^ (h2 << 1)) ^ (h3 << 2)) ^ (h4 << 3)) ^ (h5 << 4)));
    }
};

using LocationKey = std::tuple<std::string, unsigned, unsigned, std::string, std::string>;
//std::unordered_map<LocationKey, ProfileEntry, LocationKeyHash> profileMap;
std::unordered_map<LocationKey, std::vector<ProfileEntry>, LocationKeyHash> profileMap;

bool alreadyread =false;
uint64_t num_candidates;
std::map<CallBase*, std::vector<ProfileEntry>> groupedProfiles;

using SpecializationKey = std::map<unsigned, std::vector<int64_t>>; // argIndex → list of values

using CallsiteGrouped = std::map<llvm::CallBase*, std::vector<std::pair<SpecializationKey, std::vector<ProfileEntry>>>>;
std::map<std::pair<Function*, std::map<unsigned, int64_t>>, Function*> cache;
std::map<std::pair<Function*, std::map<unsigned, std::vector<int64_t>>>, Function*> cache_multiKey;


using ArgKey = std::pair<llvm::Argument*, int>;

struct ArgKeyHash {
    std::size_t operator()(const ArgKey& key) const {
        return std::hash<llvm::Argument*>{}(key.first) ^ (std::hash<int>{}(key.second) << 1);
    }
};

using ArgValueMap = std::unordered_map<ArgKey, std::vector<int64_t>, ArgKeyHash>;

// Holds clones for lookup or cleanup
//std::vector<Function*> Targets;
std::unordered_map<std::string, Function*> ClonedFunctionMap;

namespace {
  struct FuncSpecPassIRSwitchCaseV3 : public llvm::PassInfoMixin<FuncSpecPassIRSwitchCaseV3> {
    llvm::PreservedAnalyses run(llvm::Function &F, llvm::FunctionAnalysisManager &);
    bool isInVector(const std::vector<std::string> &vec, const std::string &target);
    void writeInstructionDependencyInfo(const std::map<CallBase*, std::vector<ProfileEntry>> &groupedProfiles);
    unsigned countDependentInstructions(Function *F, unsigned argIndex);
    std::map<CallBase*, std::vector<ProfileEntry>> groupProfilesByCallsite(const std::map<Instruction*, ProfileEntry> &matchedProfiles);
    unsigned countInstructionsDependingOnArgument(Function *F, unsigned argIndex);
    CallsiteGrouped groupProfilesBySpecialization(const std::map<CallBase*, std::vector<ProfileEntry>> &groupedProfiles);
    void handleFunctionSpecialization_general(const std::map<Instruction*, std::vector<ProfileEntry>> &matchedProfiles);
    void createSpecializedFunction_clusterSizeOne(CallBase* CB, Function *Orig, const SpecializationKey &key);
    bool isSingleBranchBlock(BasicBlock *BB);
    void createSpecializedFunction_clusterSizeGreaterThanOne_ArgOne(CallBase* CB, std::vector<std::pair<SpecializationKey, std::vector<ProfileEntry>>> ClusterInfo );
    void createSpecializedFunction_clusterSizeAndNumArgsGreaterThanOne(CallBase* CB, std::vector<std::pair<SpecializationKey, std::vector<ProfileEntry>>> ClusterInfo );
    bool hasKey(const std::unordered_map<int, llvm::Argument*>& argMap, int key);
    void printArgValueMap(const ArgValueMap &argValueMap);
    void generateCombinations(const SpecializationKey &key,std::vector<std::map<unsigned, int64_t>> &result);
    void printCombos(const std::vector<std::map<unsigned, int64_t>> &combos);
    void cloneFunctionsForAnalysis(const std::vector<Function*> &FunctionsToClone);
    Function* cloneFunctionForAnalysis(Function *OrigF);
    public:
      static char ID;
    private:
  //---------------------
  // Legacy PM interface
  //---------------------
  };
  struct LegacyFuncSpecPassIRSwitchCaseV3 : public llvm::FunctionPass {
    static char ID;
    LegacyFuncSpecPassIRSwitchCaseV3() : llvm::FunctionPass(ID) {}
    bool runOnFunction(llvm::Function &F) override;
    ~LegacyFuncSpecPassIRSwitchCaseV3(){
    }

    private:
  };
} //namespace

unsigned countInstructions(Function *F) {
    unsigned count = 0;
    for (auto &BB : *F) {
        count += BB.size();
    }
    return count;
}


bool FuncSpecPassIRSwitchCaseV3::isInVector(const std::vector<std::string> &vec, const std::string &target) {
    return std::find(vec.begin(), vec.end(), target) != vec.end();
}




// simple and shallow analysis that counts the number of instructions in the function F that directly use the function argument at index argIndex
// Count dependent instructions
//

unsigned FuncSpecPassIRSwitchCaseV3::countDependentInstructions(Function *F, unsigned argIndex) {
    std::error_code EC;
    std::string filename = benchmarkName + "_" + std::to_string(profileNum) + "_countDependentInstructionsDirect.txt";
    llvm::raw_fd_ostream out(filename, EC, llvm::sys::fs::OF_Text);

    if (EC) {
        llvm::errs() << "Could not open file: " << filename << "\n";
    }

 
   unsigned count = 0;
    for (auto &BB : *F) {
        for (auto &I : BB) {
            for (unsigned i = 0; i < I.getNumOperands(); ++i) {
                if (auto *Op = dyn_cast<Value>(I.getOperand(i))) {
                    if (Argument *arg = dyn_cast<Argument>(Op)) {
                        if (arg->getArgNo() == argIndex) {
                            out << *&I << "\n";
                            
                            ++count;
                        }
                    }
                }
            }
        }
    }
    return count;
}



std::map<CallBase*, std::vector<ProfileEntry>>
FuncSpecPassIRSwitchCaseV3::groupProfilesByCallsite(const std::map<Instruction*, ProfileEntry> &matchedProfiles) {
    std::map<CallBase*, std::vector<ProfileEntry>> result;

    for (const auto &pair : matchedProfiles) {
        if (auto *CB = dyn_cast<CallBase>(pair.first)) {
            result[CB].push_back(pair.second);
        }
    }

    return result;
}

//Starts from a specific function argument and counts all instructions that directly or transitively use it.
unsigned FuncSpecPassIRSwitchCaseV3::countInstructionsDependingOnArgument(Function *F, unsigned argIndex) {
 unsigned idx = 0;
 unsigned count = 0;
     std::error_code EC;
    std::string filename = benchmarkName + "_" + std::to_string(profileNum) + "_countDependentInstructionsDirectIndirect.txt";
    llvm::raw_fd_ostream out(filename, EC, llvm::sys::fs::OF_Text);

    if (EC) {
        llvm::errs() << "Could not open file: " << filename << "\n";
    }



 for (Argument &arg : F->args()) {
    if (idx == argIndex) {
    std::set<const Value *> visited;
    std::queue<const Value *> worklist;

    worklist.push(&arg);
    visited.insert(&arg);

    while (!worklist.empty()) {
        const Value *v = worklist.front();
        //errs() << "v: "<< *v << "\n";
        worklist.pop();

        for (const User *user : v->users()) {
            if (const Instruction *inst = dyn_cast<Instruction>(user)) {
                // Only count instructions that belong to the function F
                if (inst->getFunction() == F && visited.insert(inst).second) {
         //           errs() << "instr: " << *inst << "\n";
                    out << *inst << "\n";

                    ++count;
                    worklist.push(inst);
                }
            }
        }
    }
    }
    //count =0;
    idx++;
}
    return count;
}



void FuncSpecPassIRSwitchCaseV3::writeInstructionDependencyInfo(const std::map<CallBase*, std::vector<ProfileEntry>> &groupedProfiles) {
    std::error_code EC;
    std::string filename = benchmarkName + "_" + std::to_string(profileNum) + "_ProfileInfo.txt";
    llvm::raw_fd_ostream out(filename, EC, llvm::sys::fs::OF_Text);

    if (EC) {
        llvm::errs() << "Could not open file: " << filename << "\n";
        return;
    }

    for (const auto &[CB, profiles] : groupedProfiles) {
        for (const auto &entry : profiles) {
          Function *callee = CB->getCalledFunction();
          unsigned origCount = countInstructions(callee);
          unsigned depOrig = countDependentInstructions(callee, entry.argIndex);
          unsigned origArgDep = countInstructionsDependingOnArgument(callee, entry.argIndex);

          out << entry.file << ", " << entry.line <<  ", " << entry.column <<  ", " << entry.function_caller <<  ", " << entry.function_callee  <<  ", " << entry.callFreq << ", " << entry.argIndex << ", " << entry.argValue << ", " << entry.predictability << ", " <<
            origCount << ", "<< depOrig << ", "<< origArgDep << "\n"; 


        }
    }

}


CallsiteGrouped FuncSpecPassIRSwitchCaseV3::groupProfilesBySpecialization(
    const std::map<CallBase*, std::vector<ProfileEntry>> &groupedProfiles) {
    CallsiteGrouped result;

    for (const auto &[CB, profiles] : groupedProfiles) {
        // Step 1: Collect all observed values per argIndex
        std::map<unsigned, std::vector<int64_t>> argToValues;
        std::map<std::pair<unsigned, int64_t>, std::vector<ProfileEntry>> valueProfiles;

        for (const auto &entry : profiles) {
            auto &vals = argToValues[entry.argIndex];
            if (std::find(vals.begin(), vals.end(), entry.argValue) == vals.end()) {
                vals.push_back(entry.argValue);
            }

            valueProfiles[{entry.argIndex, entry.argValue}].push_back(entry);
        }

        // Step 2: Create one specialization key per unique value
        for (const auto &[argValPair, profs] : valueProfiles) {
            SpecializationKey key;
            //key[argValPair.first] = argValPair.second;  // argIndex → val
            key[argValPair.first].push_back(argValPair.second);
            result[CB].emplace_back(key, profs);        // Add this to result
        }
    }

    return result;
}

bool FuncSpecPassIRSwitchCaseV3::isSingleBranchBlock(BasicBlock *BB) {
    // Safety check in case the pointer is null
    if (!BB)
        return false;

    // Check if the block has exactly one instruction
    if (BB->size() != 1)
        return false;

    // Get the only instruction in the block
    Instruction &I = BB->front();

    // Return true if it's a branch instruction
    return isa<BranchInst>(&I);
}



void FuncSpecPassIRSwitchCaseV3::createSpecializedFunction_clusterSizeOne(CallBase* CB, Function *Orig, const SpecializationKey &key) {
  llvm::Function *F = CB->getParent()->getParent();
  BasicBlock *BB = CB->getParent();
  BasicBlock *BBbeforeCall = BB->splitBasicBlock(CB, "specialized_block"); // Split before I1, creating BB1
  llvm::Module *M = BBbeforeCall->getParent()->getParent();
  LLVMContext &Ctx = M->getContext();
  Value* V = ConstantInt::get(Type::getInt8Ty((CB->getParent())->getContext()), 0);
  Instruction *NewInst = BinaryOperator::Create(Instruction::Add, V, V,"NOP");
  NewInst->insertAfter(CB);
  BasicBlock *BBofCall = BBbeforeCall->splitBasicBlock(CB, "original_Block"); // Split before I2 in the new BB1, creating BB2
  BasicBlock *BBafterCall = BBofCall->splitBasicBlock(CB->getNextNonDebugInstruction()->getNextNonDebugInstruction(), "continue_block");

  Instruction *Terminator = BBbeforeCall->getTerminator();


  std::vector<llvm::CallBase*> callInstructionsVec;
  callInstructionsVec.push_back(CB);
  int num_cases = 0;
  unsigned int i = 0;
  //for (auto &arg : Orig->args()) {
  for (auto &arg : ClonedFunctionMap[Orig->getName().str()]->args()) {
    if (key.count(i)) {
         Type* argTy = arg.getType();
         if (!argTy->isPointerTy()){
           for (auto &[idx, values] : key){
             num_cases=values.size();
             for (int64_t val : values) {
                std::map<unsigned, int64_t> singleValueKey = {{idx, val}};
                //auto specKey = std::make_pair(Orig, singleValueKey);
                auto specKey = std::make_pair(ClonedFunctionMap[Orig->getName().str()], singleValueKey);
                Function *Cloned = nullptr;
                if (cache.count(specKey)) {
                  Cloned = cache[specKey];
                } else {
                  ValueToValueMapTy VMap;
                  //Function *Cloned = CloneFunction(Orig, VMap);
                  
                  Function *Cloned = CloneFunction( ClonedFunctionMap[Orig->getName().str()], VMap);
                  std::string suffix;
                  suffix += ".arg" + std::to_string(idx) + "_" + std::to_string(val);
                  Cloned->setName(ClonedFunctionMap[Orig->getName().str()]->getName().str() + ".specialized" + suffix);
                  Argument *origArg = ClonedFunctionMap[Orig->getName().str()]->getArg(i);
                  Value *clonedArg = VMap[origArg];
          
                  Constant *constVal = ConstantInt::get(clonedArg->getType(), singleValueKey.at(i));
                  std::vector<User*> users(clonedArg->user_begin(), clonedArg->user_end());
                  for (User *U : users) {
                    U->replaceUsesOfWith(clonedArg, constVal);
                  }
                  Cloned->setLinkage(GlobalValue::InternalLinkage);
                  cache[specKey] =  Cloned;
                }

                uint64_t ArgIndex = i;
                std::vector<int64_t> argVals = values;
                IRBuilder<> BuilderBB(BBbeforeCall, BBbeforeCall->begin());
                // Create a constant integer for the switch condition
                Value *switchValue = CB->getOperand(i);
                Type* argType = CB->getOperand(i)->getType();
                SwitchInst *SI = BuilderBB.CreateSwitch(switchValue, BBofCall);
                for (int caseValue = 1 ; caseValue <= num_cases ; caseValue++) {
                  //1) per case we need to create a BB
                  BasicBlock *caseBlock = BasicBlock::Create(Ctx, "switch.case." + std::to_string(caseValue), F);
                  //2) per case we need to add it to SI
                  if (argType->isIntegerTy(64)) {
                    SI->addCase(ConstantInt::get(Type::getInt64Ty(Ctx), argVals[caseValue-1]), caseBlock);
                  }
                  else if (argType->isIntegerTy(32)) {
                    SI->addCase(ConstantInt::get(Type::getInt32Ty(Ctx), argVals[caseValue-1]), caseBlock);
                  }
                  BuilderBB.SetInsertPoint(caseBlock);
                  Instruction *ClonedInst = CB->clone();
                  ClonedInst->setName(CB->getName());
                  if (dyn_cast<CallInst>(ClonedInst)) {
                    CallInst* CallToSpecFunc = dyn_cast<CallInst>(ClonedInst);
                    callInstructionsVec.push_back(CallToSpecFunc);
                    Function *Callee = cache[specKey];
                    if (Callee) {
                      CallToSpecFunc->setCalledFunction(Callee);
                    }
                  }
                  // Insert the cloned instruction at the beginning of the block
                  BuilderBB.Insert(ClonedInst);
                  if (!caseBlock->getTerminator()){
                    BasicBlock *SuccessorBB = caseBlock->getNextNode();
                    if (SuccessorBB){
                    }
                  //define a branch to one of the existing basic blocks
                  BuilderBB.CreateBr(BBafterCall);
                  }
                }
                Instruction *T = BBbeforeCall->getTerminator();
                T->eraseFromParent();
                // Get a successor block (or create a new one)
                BasicBlock *SuccessorBB = BBbeforeCall->getNextNode();
                if (!SuccessorBB) {
                  SuccessorBB = BasicBlock::Create(Ctx, "successor", F);
                }
                ////////////////////  add the PHI node ///////////////////////
                /// capture instructions in the BBafterCall basic block that are
                /// dependent to the original call instruction and we need to
                /// create a PHI node for each of them to have all the users
                /// for the instructions with them inside a same BB.
                SmallVector<Instruction *, 100> CallInstrsVec;
                CallInstrsVec.push_back(CB);
                SmallVector< Instruction*, 100> InstrsToModifyafterSwitch;

               // if( !isSingleBranchBlock(BBafterCall)){ 
                  for (auto IIT = BBafterCall->begin(), IE = BBafterCall->end(); IIT != IE; ++IIT) {
                    Instruction &I = *IIT;
                    assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                    Use* OperandList = I.getOperandList();
                    Use* NumOfOperands = OperandList + I.getNumOperands();
                    for(Use* op = OperandList; op < NumOfOperands; op++) {
                      if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                         InstrsToModifyafterSwitch.push_back(&I);
                      }
                    }
                  }


                  //////////////////////////////////////////////////
                  // how to get dependencies at all BBs after BBafterCall
                  Function::iterator It = BBafterCall->getIterator();
                  Function *ParentF = BBafterCall->getParent();
                  // Move to the next BB
                  ++It;
                  // Iterate through all remaining BBs
                  for (; It != ParentF->end(); ++It) {
                    BasicBlock &BBNext = *It;
                    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
                        Instruction &I = *IIT;
                        assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                        Use* OperandList = I.getOperandList();
                        Use* NumOfOperands = OperandList + I.getNumOperands();
                        for(Use* op = OperandList; op < NumOfOperands; op++) {
                          if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                            InstrsToModifyafterSwitch.push_back(&I);
                          }
                        }
                    }
                  }
                  //////////////////////////////////////////////////
                  //////////////////////////////////////////////////
                  // how to get dependencies at all BBs after BBafterCall
                 // Function::iterator It = BBafterCall->getIterator();
                //  Function *ParentF = BBafterCall->getParent();
                  // Move to the next BB
                 // ++It;
                  
                  Function::iterator End = BBbeforeCall->getIterator();
                  for (Function::iterator It = ParentF->begin(); It != End; ++It) {
                    BasicBlock &BBNext = *It;
                    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
                        Instruction &I = *IIT;
                        assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                        Use* OperandList = I.getOperandList();
                        Use* NumOfOperands = OperandList + I.getNumOperands();
                        for(Use* op = OperandList; op < NumOfOperands; op++) {
                          if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                            InstrsToModifyafterSwitch.push_back(&I);
                          }
                        }
                    }
                  }
                  //////////////////////////////////////////////////




                std::vector<BasicBlock*> PredsBasicBlocks;
                std::map<CallInst*, BasicBlock*> instructionToBlockMap;
                // Get the list of predecessors
                for (BasicBlock *Pred : predecessors(BBafterCall)) {
                  PredsBasicBlocks.push_back(Pred);
                }
                for (BasicBlock* BB : PredsBasicBlocks) {
                  for (auto I = BB->begin(), IE = BB->end(); I != IE; ++I) {
                    if (dyn_cast<CallInst>(I)) {
                      CallInst* CI = dyn_cast<CallInst>(I);
                      Function *Callee = CI->getCalledFunction();
                      if (Callee) {
                        bool foundInVector = false;
                        for (auto CE : callInstructionsVec) {
                          if (CE == CI) {
                            foundInVector = true;
                            instructionToBlockMap[CI]=BB;
                          }
                        }
                      }
                    }
                  }
                }
                for (auto& pair : instructionToBlockMap) {
                  CallInst* I = pair.first;
                  BasicBlock* BB = pair.second;
                }
                IRBuilder<> Builder2(BBafterCall, BBafterCall->begin());
                for (Instruction* instr: InstrsToModifyafterSwitch) {
                  Type *typeOfPHI=CB->getType();
                  PHINode *Phi = Builder2.CreatePHI(typeOfPHI, instructionToBlockMap.size(), "my_phi_node");
                  for (auto& pair : instructionToBlockMap) {
                    CallInst* I = pair.first;
                    Type *typeOfI= I->getType();
                    BasicBlock* BB = pair.second;
                    Phi->addIncoming(I, BB);
                  }
                  //Replace the uses of the original Call in the BBafterCall with PHI node
                  Use* OperandList = instr->getOperandList();
                  Use* NumOfOperands = OperandList + instr->getNumOperands();
                  uint64_t op_index =0;
                  for(Use* op = OperandList; op < NumOfOperands; op++) {
                    if( dyn_cast<llvm::CallBase> (op) == CB ){
                      instr->setOperand(op_index, Phi);
                    }
                    op_index++;
                  }
                }

            }
         }
      }
    }
    i++;
  }
    // === End analysis ===
}

void FuncSpecPassIRSwitchCaseV3::printArgValueMap(const ArgValueMap &argValueMap) {
    for (const auto &entry : argValueMap) {
        llvm::Argument* arg = entry.first.first;
        int index = entry.first.second;
        const std::vector<int64_t>& values = entry.second;


        /*for (size_t i = 0; i < values.size(); ++i) {
            errs() << values[i];
            if (i < values.size() - 1)
                errs() << ", ";
        }
       // errs() << "]\n\n";*/
    }
}


bool FuncSpecPassIRSwitchCaseV3::hasKey(const std::unordered_map<int, llvm::Argument*>& argMap, int key) {
    return argMap.find(key) != argMap.end();
}

void FuncSpecPassIRSwitchCaseV3::generateCombinations(const SpecializationKey &key,std::vector<std::map<unsigned, int64_t>> &result) {
    if (key.empty())
        return;

    result.clear();
    result.push_back({}); // start with one empty combination

    for (const auto &[argIdx, values] : key) {
        std::vector<std::map<unsigned, int64_t>> newResult;
        for (const auto &partial : result) {
            for (int64_t val : values) {
                std::map<unsigned, int64_t> next = partial;
                next[argIdx] = val;
                newResult.push_back(next);
            }
        }
        result = std::move(newResult);
    }
}


void FuncSpecPassIRSwitchCaseV3::printCombos(const std::vector<std::map<unsigned, int64_t>> &combos) {
    llvm::outs() << "Specialization combinations:\n";
    for (const auto &combo : combos) {
        llvm::outs() << "  Combo: ";
        for (const auto &[argIdx, val] : combo) {
            llvm::outs() << "arg" << argIdx << "=" << val << " ";
        }
        llvm::outs() << "\n";
    }
}


void FuncSpecPassIRSwitchCaseV3::createSpecializedFunction_clusterSizeAndNumArgsGreaterThanOne(CallBase* CB, std::vector<std::pair<SpecializationKey, std::vector<ProfileEntry>>> ClusterInfo ){
  
  llvm::Function *F = CB->getParent()->getParent();
  BasicBlock *BB = CB->getParent();
  BasicBlock *BBbeforeCall = BB->splitBasicBlock(CB, "specialized_block"); // Split before I1, creating BB1
  llvm::Module *M = BBbeforeCall->getParent()->getParent();
  LLVMContext &Ctx = M->getContext();
  
  Value* V = ConstantInt::get(Type::getInt8Ty((CB->getParent())->getContext()), 0);
  Instruction *NewInst = BinaryOperator::Create(Instruction::Add, V, V,"NOP");
  NewInst->insertAfter(CB);
  
  BasicBlock *BBofCall = BBbeforeCall->splitBasicBlock(CB, "original_Block"); // Split before I2 in the new BB1, creating BB2
  BasicBlock *BBafterCall = BBofCall->splitBasicBlock(CB->getNextNonDebugInstruction()->getNextNonDebugInstruction(), "continue_block");

  std::unordered_map<int, llvm::Argument*> argIndexMap;
  std::vector<llvm::CallBase*> callInstructionsVec;
  callInstructionsVec.push_back(CB);

  std::unordered_map< Argument *, uint64_t >  ArgIndexMap;
  SmallVector<Argument *> callee_args;
  SmallVector<Argument *> invariant_args;
  std::vector<uint64_t> invariant_args_index;
 
  Function* Orig = CB->getCalledFunction();
  //std::string baseName = Orig->getName().str();
  std::string baseName = ClonedFunctionMap[Orig->getName().str()]->getName().str();

  uint64_t ArgIndexcount =0;
  //for (Argument &Arg : Orig->args()){
  for (Argument &Arg : ClonedFunctionMap[Orig->getName().str()]->args()){
       callee_args.push_back(&Arg);
       argIndexMap[ArgIndexcount]=&Arg;
       ArgIndexcount++;
  }

  ArgValueMap ArgumentMapToValues;
  for (const auto &[key, profiles] : ClusterInfo) {
    for (auto &[idx, values] : key){
       for(const auto& elem : argIndexMap){
          uint64_t counter =0;
           if ( idx == elem.first){
             ArgKey keyForMap = std::make_pair(elem.second, idx);
             for (int64_t val : values) {     
               ArgumentMapToValues[keyForMap].push_back(val);
             }
           }
       }
    }
  }

  printArgValueMap(ArgumentMapToValues);

  int64_t total_conditions = 1;
  for (const auto &entry : ArgumentMapToValues) {
        llvm::Argument* arg = entry.first.first;
        invariant_args.push_back(arg);
        int idx = entry.first.second;
        const std::vector<int64_t>& values = entry.second;
        total_conditions = total_conditions * (values.size());
        invariant_args_index.push_back(idx);
  } 


  SpecializationKey multiKey;
  for (const auto &entry : ArgumentMapToValues) {
        llvm::Argument* arg = entry.first.first;
        int idx = entry.first.second;
        const std::vector<int64_t>& values = entry.second;
        Type* argTy = arg->getType();
        if (!argTy->isPointerTy()) {
          for (int64_t val : values) {
            std::map<unsigned, int64_t> singleValueKey = {{idx, val}};
            multiKey[idx].push_back(val);
            //errs() << "... idx : " << idx << " values : "<<  val << "\n";
          }//for (int64_t val : values)
        }//if (!argTy->isPointerTy())
  }//for (const auto &entry : ArgumentMapToValues)

  std::vector<std::map<unsigned, int64_t>> combos;
  generateCombinations(multiKey, combos);
  //printCombos(combos);

///////
  BasicBlock *currBB = BBbeforeCall;
  Instruction *Terminator = BBbeforeCall->getTerminator();
  //IRBuilder<> Builder(BBbeforeCall, BBbeforeCall->begin());
/////////////
  std::vector<BasicBlock*> condBlocks;
  std::vector<BasicBlock*> thenBlocks;
  for (size_t i = 0; i < combos.size(); ++i) {
    condBlocks.push_back(BasicBlock::Create(Ctx, "cond." + std::to_string(i), F, BBofCall));
    thenBlocks.push_back(BasicBlock::Create(Ctx, "then." + std::to_string(i), F, BBofCall));
  }
  for (size_t i = 0; i < combos.size(); ++i) {
    const auto &combo = combos[i];
    BasicBlock *condBB = condBlocks[i];
    BasicBlock *thenBB = thenBlocks[i];
    
    IRBuilder<> condBuilder(condBB);
    condBuilder.SetInsertPoint(condBB);
    Value *cond = nullptr;
    for (const auto &[argIdx, val] : combo) {
      Value *argVal = CB->getArgOperand(argIdx);
      Value *cmp = condBuilder.CreateICmpEQ(argVal, ConstantInt::get(argVal->getType(), val));
      cond = cond ? condBuilder.CreateAnd(cond, cmp) : cmp;
    }
    BasicBlock *falseDest = (i + 1 < combos.size()) ? condBlocks[i + 1] : BBofCall;
    condBuilder.CreateCondBr(cond, thenBB, falseDest);
    IRBuilder<> thenBuilder(thenBB);
    thenBuilder.SetInsertPoint(thenBB);
    std::vector<Value*> newArgs(CB->arg_begin(), CB->arg_end());
    SpecializationKey comboMultiKey;
    std::string specName = baseName + ".specialized";
    for (const auto &[argIdx, val] : combo) {
      specName += ".arg" + std::to_string(argIdx) + "_" + std::to_string(val);
      comboMultiKey[argIdx].push_back(val);
    }
    //auto specKey = std::make_pair(Orig, comboMultiKey);
    auto specKey = std::make_pair(ClonedFunctionMap[Orig->getName().str()], comboMultiKey);
    Function *Cloned = nullptr;
    if (cache_multiKey.count(specKey)) {
      Cloned = cache_multiKey[specKey];
    } else {
      ValueToValueMapTy VMap;
      //Cloned = CloneFunction(Orig, VMap);

      Cloned = CloneFunction( ClonedFunctionMap[Orig->getName().str()], VMap);
      Cloned->setName(specName);
      for (const auto &[argIdx, val] : combo) {
        ///start from here
        //Argument *origArg = Orig->getArg(argIdx);
        Argument *origArg = ClonedFunctionMap[Orig->getName().str()]->getArg(argIdx);
        Value *clonedArg = VMap[origArg];
        Constant *constVal = ConstantInt::get(clonedArg->getType(), val);
        std::vector<User*> users(clonedArg->user_begin(), clonedArg->user_end());
        for (User *U : users) {
          U->replaceUsesOfWith(clonedArg, constVal);
        }
      }  
      Cloned->setLinkage(GlobalValue::InternalLinkage);
      cache_multiKey[specKey] =  Cloned;
      }
      Instruction *ClonedInst = CB->clone();
      ClonedInst->setName(CB->getName());
      if (dyn_cast<CallInst>(ClonedInst)) {
        CallInst* CallToSpecFunc = dyn_cast<CallInst>(ClonedInst);
        callInstructionsVec.push_back(CallToSpecFunc);
        if (Cloned) {
          CallToSpecFunc->setCalledFunction(Cloned);
        }
      }
      thenBuilder.Insert(ClonedInst);
      thenBuilder.CreateBr(BBafterCall);
  }

  // Link BBBeforeCall to first cond block
  BBbeforeCall->getTerminator()->eraseFromParent();
  BranchInst::Create(condBlocks[0], BBbeforeCall);
  ////////////////////  add the PHI node ///////////////////////
  /// capture instructions in the BBafterCall basic block that are
  /// dependent to the original call instruction and we need to
  /// create a PHI node for each of them to have all the users
  /// for the instructions with them inside a same BB.
  SmallVector<Instruction *, 100> CallInstrsVec;
  CallInstrsVec.push_back(CB);
  SmallVector< Instruction*, 100> InstrsToModifyafterSwitch;

  for (auto IIT = BBafterCall->begin(), IE = BBafterCall->end(); IIT != IE; ++IIT) {
    Instruction &I = *IIT;
    assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
    Use* OperandList = I.getOperandList();
    Use* NumOfOperands = OperandList + I.getNumOperands();
    for(Use* op = OperandList; op < NumOfOperands; op++) {
      if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
        InstrsToModifyafterSwitch.push_back(&I);
      }
    }
  }
  //////////////////////////////////////////////////
  // how to get dependencies at all BBs after BBafterCall
  Function::iterator It = BBafterCall->getIterator();
  Function *ParentF = BBafterCall->getParent();
  ++It;
  for (; It != ParentF->end(); ++It) {
    BasicBlock &BBNext = *It;
    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
      Instruction &I = *IIT;
      assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
      Use* OperandList = I.getOperandList();
      Use* NumOfOperands = OperandList + I.getNumOperands();
      for(Use* op = OperandList; op < NumOfOperands; op++) {
        if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
          InstrsToModifyafterSwitch.push_back(&I);
        }
      }
    }
  }
  //////////////////////////////////////////////////
  // how to get dependencies at all BBs before BBbeforeCall
  Function::iterator End = BBbeforeCall->getIterator();
  for (Function::iterator It = ParentF->begin(); It != End; ++It) {
    BasicBlock &BBNext = *It;
    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
      Instruction &I = *IIT;
      assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
      Use* OperandList = I.getOperandList();
      Use* NumOfOperands = OperandList + I.getNumOperands();
      for(Use* op = OperandList; op < NumOfOperands; op++) {
        if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
          InstrsToModifyafterSwitch.push_back(&I);
        }
      }
    }
  }
  //////////////////////////////////////////////////
  std::vector<BasicBlock*> PredsBasicBlocks;
  std::map<CallInst*, BasicBlock*> instructionToBlockMap;
  // Get the list of predecessors
  for (BasicBlock *Pred : predecessors(BBafterCall)) {
      PredsBasicBlocks.push_back(Pred);
  }
  for (BasicBlock* BB : PredsBasicBlocks) {
    for (auto I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      if (dyn_cast<CallInst>(I)) {
        CallInst* CI = dyn_cast<CallInst>(I);
        Function *Callee = CI->getCalledFunction();
        if (Callee) {
          bool foundInVector = false;
          for (auto CE : callInstructionsVec) {
            if (CE == CI) {
              foundInVector = true;
              instructionToBlockMap[CI]=BB;
            }
          }
        }
      }
     }
   }
   for (auto& pair : instructionToBlockMap) {
     CallInst* I = pair.first;
     BasicBlock* BB = pair.second;
   }
   IRBuilder<> Builder2(BBafterCall, BBafterCall->begin());
   for (Instruction* instr: InstrsToModifyafterSwitch) {
     Type *typeOfPHI=CB->getType();
     PHINode *Phi = Builder2.CreatePHI(typeOfPHI, instructionToBlockMap.size(), "my_phi_node");
     for (auto& pair : instructionToBlockMap) {
       CallInst* I = pair.first;
       Type *typeOfI= I->getType();
       BasicBlock* BB = pair.second;
       Phi->addIncoming(I, BB);
     }
     Use* OperandList = instr->getOperandList();
     Use* NumOfOperands = OperandList + instr->getNumOperands();
     uint64_t op_index =0;
     for(Use* op = OperandList; op < NumOfOperands; op++) {
       if( dyn_cast<llvm::CallBase> (op) == CB ){
         instr->setOperand(op_index, Phi);
       }
       op_index++;
     }
  }
  /******************************************************************* */
}

void FuncSpecPassIRSwitchCaseV3::createSpecializedFunction_clusterSizeGreaterThanOne_ArgOne(CallBase* CB, std::vector<std::pair<SpecializationKey, std::vector<ProfileEntry>>> ClusterInfo ){
  llvm::Function *F = CB->getParent()->getParent();
  BasicBlock *BB = CB->getParent();
  BasicBlock *BBbeforeCall = BB->splitBasicBlock(CB, "specialized_block"); // Split before I1, creating BB1
  llvm::Module *M = BBbeforeCall->getParent()->getParent();
  LLVMContext &Ctx = M->getContext();
  Value* V = ConstantInt::get(Type::getInt8Ty((CB->getParent())->getContext()), 0);
  Instruction *NewInst = BinaryOperator::Create(Instruction::Add, V, V,"NOP");
  NewInst->insertAfter(CB);
  BasicBlock *BBofCall = BBbeforeCall->splitBasicBlock(CB, "original_Block"); // Split before I2 in the new BB1, creating BB2
  BasicBlock *BBafterCall = BBofCall->splitBasicBlock(CB->getNextNonDebugInstruction()->getNextNonDebugInstruction(), "continue_block");

  Instruction *Terminator = BBbeforeCall->getTerminator();


  std::unordered_map<int, llvm::Argument*> argIndexMap;
  std::vector<llvm::CallBase*> callInstructionsVec;
  callInstructionsVec.push_back(CB);
  int num_cases = 0;
  unsigned int i = 0;
  Function* Orig = CB->getCalledFunction();
  for (const auto &[key, profiles] : ClusterInfo) {
    //for (auto &arg : Orig->args()) {
    for (auto &arg : ClonedFunctionMap[Orig->getName().str()]->args()) {
      if (key.count(i)) {
         Type* argTy = arg.getType();
         if (!argTy->isPointerTy()){
           argIndexMap[i]=&arg;
         }
      }
      i++;
    }
  }

  ArgValueMap ArgumentMapToValues; 
  //start from here!
  for (const auto &[key, profiles] : ClusterInfo) {
    for (auto &[idx, values] : key){
      for (int64_t val : values) {
        if (hasKey(argIndexMap, idx)) {
          llvm::Argument* arg = argIndexMap[idx];
           ArgKey keyForMap = std::make_pair(arg, idx);
           // Insert a value
           ArgumentMapToValues[keyForMap].push_back(val);
        }
      }
    }
  }

  printArgValueMap(ArgumentMapToValues);


  for (const auto &entry : ArgumentMapToValues) {
        llvm::Argument* arg = entry.first.first;
        int idx = entry.first.second;
        const std::vector<int64_t>& values = entry.second;
        Type* argTy = arg->getType();
        if (!argTy->isPointerTy()){
          num_cases=values.size();
          //for (size_t i = 0; i < values.size(); ++i) {
          for (int64_t val : values) {
            std::map<unsigned, int64_t> singleValueKey = {{idx, val}};
            //auto specKey = std::make_pair(Orig, singleValueKey);
            auto specKey = std::make_pair(ClonedFunctionMap[Orig->getName().str()], singleValueKey);
            Function *Cloned = nullptr;
            if (cache.count(specKey)) {
              Cloned = cache[specKey];
            } else {
              ValueToValueMapTy VMap;
      //        Function *Cloned = CloneFunction(Orig, VMap);
      Cloned = CloneFunction( ClonedFunctionMap[Orig->getName().str()], VMap);
              std::string suffix;
              suffix += ".arg" + std::to_string(idx) + "_" + std::to_string(val);
              //Cloned->setName(Orig->getName().str() + ".specialized" + suffix);
              Cloned->setName(ClonedFunctionMap[Orig->getName().str()]->getName().str() + ".specialized" + suffix);
              //Argument *origArg = Orig->getArg(idx);
              Argument *origArg = ClonedFunctionMap[Orig->getName().str()]->getArg(idx);
              Value *clonedArg = VMap[origArg];
          
              Constant *constVal = ConstantInt::get(clonedArg->getType(), singleValueKey.at(idx));
              std::vector<User*> users(clonedArg->user_begin(), clonedArg->user_end());
              for (User *U : users) {
                U->replaceUsesOfWith(clonedArg, constVal);
              }
              Cloned->setLinkage(GlobalValue::InternalLinkage);
              cache[specKey] =  Cloned;
            }
          }
          uint64_t ArgIndex = idx;
          i=idx;
            
            std::vector<int64_t> argVals = values;
            IRBuilder<> BuilderBB(BBbeforeCall, BBbeforeCall->begin());
            // Create a constant integer for the switch condition
            Value *switchValue = CB->getOperand(idx);
            Type* argType = CB->getOperand(idx)->getType();
            SwitchInst *SI = BuilderBB.CreateSwitch(switchValue, BBofCall);
            for (int caseValue = 1 ; caseValue <= num_cases ; caseValue++) {
              BasicBlock *caseBlock = BasicBlock::Create(Ctx, "switch.case." + std::to_string(caseValue), F);
              if (argType->isIntegerTy(64)) {
                SI->addCase(ConstantInt::get(Type::getInt64Ty(Ctx), argVals[caseValue-1]), caseBlock);
              }
              else if (argType->isIntegerTy(32)) {
                SI->addCase(ConstantInt::get(Type::getInt32Ty(Ctx), argVals[caseValue-1]), caseBlock);
              }
              BuilderBB.SetInsertPoint(caseBlock);
              Instruction *ClonedInst = CB->clone();
              ClonedInst->setName(CB->getName());
              if (dyn_cast<CallInst>(ClonedInst)) {
                CallInst* CallToSpecFunc = dyn_cast<CallInst>(ClonedInst);
                callInstructionsVec.push_back(CallToSpecFunc);
          std::map<unsigned, int64_t> singleValueKey = {{idx, argVals[caseValue-1] }};
          //auto specKey = std::make_pair(Orig, singleValueKey);
          auto specKey = std::make_pair(ClonedFunctionMap[Orig->getName().str()], singleValueKey);
            
 
                Function *Callee = cache[specKey];
                if (Callee) {
                    CallToSpecFunc->setCalledFunction(Callee);
                 }
               }
               // Insert the cloned instruction at the beginning of the block
               BuilderBB.Insert(ClonedInst);
               if (!caseBlock->getTerminator()){
                  BasicBlock *SuccessorBB = caseBlock->getNextNode();
                  if (SuccessorBB){
                  }
                  //define a branch to one of the existing basic blocks
                  BuilderBB.CreateBr(BBafterCall);
               }
            }// for (int caseValue = 1 ; caseValue <= num_cases ; caseValue++)
           
            Instruction *T = BBbeforeCall->getTerminator();
            T->eraseFromParent();
            // Get a successor block (or create a new one)
            BasicBlock *SuccessorBB = BBbeforeCall->getNextNode();
            if (!SuccessorBB) {
               SuccessorBB = BasicBlock::Create(Ctx, "successor", F);
            }

            ////////////////////  add the PHI node ///////////////////////
            /// capture instructions in the BBafterCall basic block that are
            /// dependent to the original call instruction and we need to
            /// create a PHI node for each of them to have all the users
            /// for the instructions with them inside a same BB.
            SmallVector<Instruction *, 100> CallInstrsVec;
            CallInstrsVec.push_back(CB);
            SmallVector< Instruction*, 100> InstrsToModifyafterSwitch;

            for (auto IIT = BBafterCall->begin(), IE = BBafterCall->end(); IIT != IE; ++IIT) {
                    Instruction &I = *IIT;
                    assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                    Use* OperandList = I.getOperandList();
                    Use* NumOfOperands = OperandList + I.getNumOperands();
                    for(Use* op = OperandList; op < NumOfOperands; op++) {
                      if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                         InstrsToModifyafterSwitch.push_back(&I);
                      }
                    }
            }


            //////////////////////////////////////////////////
            // how to get dependencies at all BBs after BBafterCall
            Function::iterator It = BBafterCall->getIterator();
            Function *ParentF = BBafterCall->getParent();
            // Move to the next BB
            ++It;
            // Iterate through all remaining BBs
            for (; It != ParentF->end(); ++It) {
                    BasicBlock &BBNext = *It;
                    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
                        Instruction &I = *IIT;
                        assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                        Use* OperandList = I.getOperandList();
                        Use* NumOfOperands = OperandList + I.getNumOperands();
                        for(Use* op = OperandList; op < NumOfOperands; op++) {
                          if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                            InstrsToModifyafterSwitch.push_back(&I);
                          }
                        }
                    }
             }
                  //////////////////////////////////////////////////
                  //////////////////////////////////////////////////
                  
             Function::iterator End = BBbeforeCall->getIterator();
             for (Function::iterator It = ParentF->begin(); It != End; ++It) {
                    BasicBlock &BBNext = *It;
                    //errs() << "BB after target: " << BBNext.getName() << "\n";
                    for (auto IIT = BBNext.begin(), IE = BBNext.end(); IIT != IE; ++IIT) {
                        Instruction &I = *IIT;
                        assert(!isa<PHINode>(&I) && "Phi nodes have already been filtered out");
                        Use* OperandList = I.getOperandList();
                        Use* NumOfOperands = OperandList + I.getNumOperands();
                        for(Use* op = OperandList; op < NumOfOperands; op++) {
                          if(std::find(CallInstrsVec.begin(), CallInstrsVec.end(),dyn_cast<llvm::Instruction>(op)) != CallInstrsVec.end()){
                            InstrsToModifyafterSwitch.push_back(&I);
                          }
                        }
                    }
             }
             //////////////////////////////////////////////////




            std::vector<BasicBlock*> PredsBasicBlocks;
            std::map<CallInst*, BasicBlock*> instructionToBlockMap;
                // Get the list of predecessors
            for (BasicBlock *Pred : predecessors(BBafterCall)) {
                  PredsBasicBlocks.push_back(Pred);
            }
            for (BasicBlock* BB : PredsBasicBlocks) {
                  for (auto I = BB->begin(), IE = BB->end(); I != IE; ++I) {
                    if (dyn_cast<CallInst>(I)) {
                      CallInst* CI = dyn_cast<CallInst>(I);
                      Function *Callee = CI->getCalledFunction();
                      if (Callee) {
                        bool foundInVector = false;
                        for (auto CE : callInstructionsVec) {
                          if (CE == CI) {
                            foundInVector = true;
                            instructionToBlockMap[CI]=BB;
                          }
                        }
                      }
                    }
                  }
             }
             for (auto& pair : instructionToBlockMap) {
                  CallInst* I = pair.first;
                  BasicBlock* BB = pair.second;
             }
             IRBuilder<> Builder2(BBafterCall, BBafterCall->begin());
             for (Instruction* instr: InstrsToModifyafterSwitch) {
                  Type *typeOfPHI=CB->getType();
                  PHINode *Phi = Builder2.CreatePHI(typeOfPHI, instructionToBlockMap.size(), "my_phi_node");
                  for (auto& pair : instructionToBlockMap) {
                    CallInst* I = pair.first;
                    Type *typeOfI= I->getType();
                    BasicBlock* BB = pair.second;
                    Phi->addIncoming(I, BB);
                  }
                  //Replace the uses of the original Call in the BBafterCall with PHI node
                  Use* OperandList = instr->getOperandList();
                  Use* NumOfOperands = OperandList + instr->getNumOperands();
                  uint64_t op_index =0;
                  for(Use* op = OperandList; op < NumOfOperands; op++) {
                    if( dyn_cast<llvm::CallBase> (op) == CB ){
                      instr->setOperand(op_index, Phi);
                    }
                    op_index++;
                  }
             }
      }//if (!argTy->isPointerTy())
  }//for (const auto &entry : ArgumentMapToValues)


}


void FuncSpecPassIRSwitchCaseV3::handleFunctionSpecialization_general( const std::map<Instruction*, std::vector<ProfileEntry>> &matchedProfiles) {
    //errs() << "matchedProfiles: " << matchedProfiles.size() <<"\n";
    std::map<CallBase*, std::vector<ProfileEntry>> groupedProfiles;
    for (const auto &[inst, entryVec] : matchedProfiles) {
      if (auto *CB = dyn_cast<CallBase>(inst)) {
        for (const auto &entry :  entryVec) {
          groupedProfiles[CB].push_back(entry);
        }
      }
    }

    writeInstructionDependencyInfo(groupedProfiles);

    for (const auto &[CB, profiles] : groupedProfiles) {
        for (const auto &entry : profiles) {
          Function *callee = CB->getCalledFunction();
          unsigned origCount = countInstructions(callee);
          unsigned depOrig = countDependentInstructions(callee, entry.argIndex);
          unsigned origArgDep = countInstructionsDependingOnArgument(callee, entry.argIndex);



        }
    }

    CallsiteGrouped callsiteGroups = groupProfilesBySpecialization(groupedProfiles);
    std::vector<uint64_t> NumArgsInCallsite ;
    for (const auto &[CallB, clusters] : callsiteGroups) {
        for (const auto &[key, profiles] : clusters) {
            Function *callee = CallB->getCalledFunction();
            if (!callee || callee->isDeclaration())
              continue;
            for (const auto &[argIdx, argVal] : key) {
               if (std::find(NumArgsInCallsite.begin(), NumArgsInCallsite.end(), argIdx) == NumArgsInCallsite.end()) {
                 NumArgsInCallsite.push_back(argIdx);
               }
            }
        }
    }

    for (const auto &[CallB, clusters] : callsiteGroups) {
      
      if(clusters.size() == 1 && NumArgsInCallsite.size() == 1 ) {
        errs() << "clusters.size = 1 and NumArgsInCallsite = 1 !\n";
        for (const auto &[key, profiles] : clusters) {
          Function *callee = CallB->getCalledFunction();
          if (!callee || callee->isDeclaration())
              continue;
          for (const auto &[argIdx, argVal] : key) {
            createSpecializedFunction_clusterSizeOne(CallB, callee, key);
          }
        }
      }
      
      if(clusters.size() > 1 &&  NumArgsInCallsite.size() == 1 ){
        createSpecializedFunction_clusterSizeGreaterThanOne_ArgOne(CallB , clusters);
      }

      if(clusters.size() > 1 &&  NumArgsInCallsite.size() > 1){
        createSpecializedFunction_clusterSizeAndNumArgsGreaterThanOne(CallB , clusters);
      }


    }

}
Function* FuncSpecPassIRSwitchCaseV3::cloneFunctionForAnalysis(Function *OrigF) {
    assert(OrigF && !OrigF->isDeclaration() && "Cannot clone null or declaration-only function");


    if (OrigF->isDeclaration()) {
      return nullptr;
    }
    LLVMContext &Ctx = OrigF->getContext();
    FunctionType *FTy = OrigF->getFunctionType();

    // Create a function, but do not add to module
    Function *ClonedF = Function::Create(
        FTy,
        Function::PrivateLinkage,
        OrigF->getAddressSpace(),
        OrigF->getName() + ".clone"
    );

    // Make sure argument names match (required for some analyses)
    auto DestArg = ClonedF->arg_begin();
    for (const Argument &OrigArg : OrigF->args()) {
        DestArg->setName(OrigArg.getName());
        ++DestArg;
    }

    ValueToValueMapTy VMap;
    SmallVector<ReturnInst*, 8> Returns;

    // Map function arguments
    Function::arg_iterator DestI = ClonedF->arg_begin();
    for (const Argument &Arg : OrigF->args()) {
        VMap[&Arg] = &*DestI++;
    }

    // Clone body
    CloneFunctionInto(ClonedF, OrigF, VMap, CloneFunctionChangeType::LocalChangesOnly, Returns);

    return ClonedF;
}


/// Clone multiple functions and store them in a map by name
void FuncSpecPassIRSwitchCaseV3::cloneFunctionsForAnalysis(const std::vector<Function*> &FunctionsToClone) {
  for (Function *F : FunctionsToClone) {
    errs() << "name of function to clone: " <<  F->getName() << "\n";
        if (!F || F->isDeclaration())
          continue;

         llvm::Module *M = F->getParent();
        Function *Cloned = cloneFunctionForAnalysis(F);
        if(Cloned!=nullptr )
        ClonedFunctionMap[F->getName().str()] = Cloned;
        M->getFunctionList().push_back(Cloned);
    }
}




PreservedAnalyses FuncSpecPassIRSwitchCaseV3::run( llvm::Function &F,llvm::FunctionAnalysisManager &FAM) {
  bool modified =false;
  //psimplex.c, master, primal_bea_mpp, 176, 21, 217866, 7, 0, 217866, 100
  if(!Profile.empty() && !alreadyread){
    std::ifstream file;
    file.open(Profile);
    std::string line;
    while (getline(file, line)) {
      std::stringstream linestream(line);
      std::string filename;
      std::string Caller;
      std::string Callee;
      std::string line_str;
      std::string col_str;
      std::string callfreq_str;
      std::string argIndex_str;
      std::string argVal_str;
      std::string argValfreq_str;
      std::string argValPred_str;
      
      getline(linestream, filename, ',');
      getline(linestream, Caller, ',');
      getline(linestream, Callee, ',');
      getline(linestream, line_str, ',');
      getline(linestream, col_str, ',');
      getline(linestream, callfreq_str, ',');
      getline(linestream, argIndex_str, ',');
      getline(linestream, argVal_str, ',');
      getline(linestream, argValfreq_str, ',');
      getline(linestream, argValPred_str, ',');
      
      uint64_t CallLine = atoi(line_str.c_str());
      uint64_t CallCol = atoi(col_str.c_str());
      uint64_t CallFreq = atoi(callfreq_str.c_str());
      uint64_t ArgIndex = atoi(argIndex_str.c_str());
      uint64_t ArgVal = atoi(argVal_str.c_str());
      uint64_t ArgValFreq = atoi(argValfreq_str.c_str());
      uint64_t ArgValPred = atof(argValPred_str.c_str());

      filename.erase(std::remove_if(filename.begin(), filename.end(), ::isspace), filename.end());
      Caller.erase(std::remove_if(Caller.begin(), Caller.end(), ::isspace), Caller.end());
      Callee.erase(std::remove_if(Callee.begin(), Callee.end(), ::isspace), Callee.end());
      line_str.erase(std::remove_if(line_str.begin(), line_str.end(), ::isspace), line_str.end());
      col_str.erase(std::remove_if(col_str.begin(), col_str.end(), ::isspace), col_str.end());
      callfreq_str.erase(std::remove_if(callfreq_str.begin(), callfreq_str.end(), ::isspace), callfreq_str.end());
      argIndex_str.erase(std::remove_if(argIndex_str.begin(), argIndex_str.end(), ::isspace), argIndex_str.end());
      argVal_str.erase(std::remove_if(argVal_str.begin(), argVal_str.end(), ::isspace), argVal_str.end());
      argValfreq_str.erase(std::remove_if(argValfreq_str.begin(), argValfreq_str.end(), ::isspace), argValfreq_str.end());
      argValPred_str.erase(std::remove_if(argValPred_str.begin(), argValPred_str.end(), ::isspace), argValPred_str.end());

      ////////////////////
      ProfileEntry entry;
      
      entry.file=filename;
      entry.function_caller=Caller;
      entry.function_callee=Callee;
      entry.line=CallLine;
      entry.column=CallCol;
      entry.callFreq=CallFreq;
      entry.argIndex=ArgIndex;
      entry.argValue=ArgVal;
      entry.valFreq=ArgValFreq;
      entry.predictability=ArgValPred;

      ProfileEntriesVec.push_back(entry);
      CallerFuncNamesVec.push_back(Caller);
      ///////////////////
      num_candidates++;
    }

    for (const auto &entry :  ProfileEntriesVec) {
      LocationKey key = {entry.file, entry.line, entry.column, entry.function_caller, entry.function_callee};
      profileMap[key] = ProfileEntriesVec;
    }
    alreadyread = true;
  }


  //std::map<llvm::Instruction*, ProfileEntry> matchedProfiles;
  std::map<llvm::Instruction*, std::vector<ProfileEntry>> matchedProfiles;
  std::vector<Function*> Targets;

  std::string callerName = F.getName().str(); // current function
  if (isInVector(CallerFuncNamesVec, callerName)) {
    for (auto &BB : F) {
      for (auto &I : BB) {
        if (auto *callInst = llvm::dyn_cast<llvm::CallBase>(&I)) {
                if (const llvm::DILocation *loc = I.getDebugLoc()) {
                    std::string filename = loc->getFilename().str();
                    unsigned line = loc->getLine();
                    unsigned column = loc->getColumn();

                    llvm::Function *calledFunc = callInst->getCalledFunction();
                    if (!calledFunc)
                      continue; // skip indirect calls

                    if (std::find(Targets.begin(), Targets.end(), calledFunc) == Targets.end()) {
                      // F is NOT in Targets → safe to add
                      //Targets.push_back(calledFunc);
                    }
                    std::string calleeName = calledFunc->getName().str();
                    LocationKey key = {filename, line, column, callerName, calleeName};

                    auto it = profileMap.find(key);
                    if (it != profileMap.end()) {
                        std::vector<ProfileEntry> entryVec = it->second;
                        for (const auto &entry :  entryVec) {
                          if (entry.function_caller == callerName &&  entry.function_callee == calleeName &&  entry.line == line && entry.column == column )
                       Targets.push_back(calledFunc);
                           matchedProfiles[&I].push_back(entry);
                        }
                           //matchedProfiles[&I] = it->second;
                    }
                }
        }
      }
    }
    cloneFunctionsForAnalysis(Targets);
    // Example: print names of cloned functions
  }

  if (!matchedProfiles.empty() && isInVector(CallerFuncNamesVec, callerName)) {

    handleFunctionSpecialization_general(matchedProfiles);
  }

  if (modified){
    return llvm::PreservedAnalyses::none();
  }
  else{
     return llvm::PreservedAnalyses::all();
  }


}

bool LegacyFuncSpecPassIRSwitchCaseV3::runOnFunction(llvm::Function &F) {
   bool modified = false;
   for (Function::iterator BB = F.begin(); BB != F.end(); BB++) {
     for (BasicBlock::iterator I = BB->begin(); I != BB->end(); I++) {
     }
   }
   return modified;
}

/*
// --- Module Pass to clean up cloned functions ---
class CloneCleanupPass : public PassInfoMixin<CloneCleanupPass> {
public:
    PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
//        auto &Tracker = MAM.getResult<CloneTrackerAnalysis>(M);
  //      for (Function *F : Tracker.ClonedFunctions) {
      for (auto &Entry : ClonedFunctionMap) {
      Entry.second->dropAllReferences();
            Entry.second->eraseFromParent();
        }
        return PreservedAnalyses::all();
    }    
};
*/
//------------------------------------------------------------------------------
// New PM Registration
//------------------------------------------------------------------------------




llvm::PassPluginLibraryInfo getFuncSpecPassIRSwitchCaseV3PluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "FuncSpecPassIRSwitchCaseV3", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
/*            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                    if (Name == "clone-cleanup") {
                        MPM.addPass(CloneCleanupPass());
                        return true;
                    }
                    return false;
                });
 */


            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "FuncSpecPassIRSwitchCaseV3") {

                    FPM.addPass(FuncSpecPassIRSwitchCaseV3());
                    //FPM.addPass(FuncSpecPassIRSwitchCaseV3());
                    return true;
                  }
                  return false;
                });
          }};
}
extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return getFuncSpecPassIRSwitchCaseV3PluginInfo();
}
//------------------------------------------------------------------------------
// Legacy PM Registration
//------------------------------------------------------------------------------
char LegacyFuncSpecPassIRSwitchCaseV3::ID = 0;
static RegisterPass<LegacyFuncSpecPassIRSwitchCaseV3> X(/*PassArg=*/"legacy-FuncSpecPassIRSwitchCaseV3",
                                         /*Name=*/"Changes control flow based on the collected VP for load instructions",
                                         /*CFGOnly=*/false, // This pass doesn't modify the CFG => false
                                         /*is_analysis=*/false // This pass is not a pure analysis pass => false
                                         );



