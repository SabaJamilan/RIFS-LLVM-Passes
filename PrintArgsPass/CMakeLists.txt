add_llvm_library(PrintArgsPass MODULE
  PrintArgsPass.cpp
  PLUGIN_TOOL
  opt
  )
add_dependencies(PrintArgsPass intrinsics_gen)
