# Shim: Fedora ships Zydis with pkg-config only; provide the Zydis::Zydis target gpu/CMakeLists.txt expects.
find_package(PkgConfig REQUIRED)
pkg_check_modules(ZYDIS_PC REQUIRED IMPORTED_TARGET zydis)
if(NOT TARGET Zydis::Zydis)
    add_library(Zydis::Zydis INTERFACE IMPORTED)
    target_link_libraries(Zydis::Zydis INTERFACE PkgConfig::ZYDIS_PC)
endif()
set(Zydis_FOUND TRUE)
