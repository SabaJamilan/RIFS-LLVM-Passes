add_llvm_library(FuncSpecPassIRSwitchCaseV3 MODULE
  PLUGIN_TOOL
  opt
  FuncSpecPassIRSwitchCaseV3.cpp
  )
##bohr3
add_dependencies(FuncSpecPassIRSwitchCaseV3 intrinsics_gen)
