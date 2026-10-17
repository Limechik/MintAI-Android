cmake_minimum_required(VERSION 3.10)
project(voxsynth C)
add_library(voxsynth SHARED
  voxsynth/FormantCore.c voxsynth/Phonemes.c voxsynth/Stress.c voxsynth/vox_ffi.c)
target_include_directories(voxsynth PRIVATE voxsynth)
target_compile_options(voxsynth PRIVATE -O2)
target_link_libraries(voxsynth m)
