@echo off
rem Builds the thread stack sampler (needs clang-cl or cl from a Visual Studio developer prompt).
clang-cl /nologo /O2 /EHsc /utf-8 /Fe:echantillonneur.exe "%~dp0echantillonneur.cpp" dbghelp.lib
