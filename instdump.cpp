#include <stdio.h>
#include <stdlib.h>
#include <map>
#include <list>
#include <iostream>
#include <utility>
#include "pin.H"

#define WINDOWS_IS_FUCKING_FUCKED	1
#ifdef WINDOWS_IS_FUCKING_FUCKED
#define snprintf	sprintf_s
#define stricmp		_stricmp
#endif /* WINDOWS_IS_FUCKING_FUCKED */


VOID
LogInstruction(THREADID threadID, ADDRINT address, string disasm)
{
}

VOID
LogBranchOrCall(THREADID threadID, ADDRINT address, string disasm, ADDRINT target)
{
	fprintf(outputFile, "[%d] 0x%0.8X %s ; 0x%0.8X\n",
			threadID, address, disasm.c_str(), target);
}

VOID
Lo

VOID
TraceInstruction(INS ins, VOID *arg)
{
	std::string disasm = INS_Disassemble(ins);

	if (INS_IsBranchOrCall(ins)) {
		// log direct call
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNCPTR) LogBranchOrCall,
			IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_BRANCH_TARGET_ADDR,
			IARG_END);
	} else if (INS_IsRet(ins) || INS_IsSysret) {
		// log return
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNCPTR) LogInstruction,
			IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_END);
	} else if (INS_IsMemoryRead(ins) ||
		   INS_IsMemoryRead2(ins)) {
		// memory read instruction
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNCPTR) LogInstruction,
			IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_MEMORYREAD_EA, // effective address being read
			IARG_MEMORYREAD_SIZE, // num bytes read
			IARG_END);
	} else if (INS_IsMemoryWrite(ins)) {
		// memory write instruction
		INS_InsertCall(ins,
			IPOINT_BEFORE,
			(AFUNCPTR) LogInstruction,
			IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_MEMORYWRITE_EA, // effective address being written
			IARG_MEMORYWRITE_SIZE, // num bytes writen
			IARG_END);
	} else if (INS_IsNop(ins)) {
		// log nop
	} else {
		// log generic instruction
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNCPTR) LogInstruction,
			IARG_START,
			IARG_INST_PTR, // address of instruction
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_PTR, disasm, // disassembled string
			IARG_END);
	}
}

int main(int argc, char **argv)
{
	PIN_InitSymbols();

	if (PIN_Init(argc, argv)) {
		return Usage();
	}

	TRACE_AddInstrumentationFunction(TraceInstructions, 0);

	PIN_AddFiniFunction(Fini, 0);

	// never returns..
	PIN_StartProgram();

	return 0;
}
