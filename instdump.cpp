#include <stdio.h>
#include <stdlib.h>
#include <map>
#include <list>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <utility>
#include <string.h>
#include "pin.H"

#define WINDOWS_IS_FUCKING_FUCKED	1
#ifdef WINDOWS_IS_FUCKING_FUCKED
#define snprintf	sprintf_s
#define stricmp		_stricmp
#endif /* WINDOWS_IS_FUCKING_FUCKED */


FILE *outFile;

KNOB<string> outputFile(KNOB_MODE_WRITEONCE, "pintool", "o", "instructions.out", "specify trace output file name");


UINT32
Usage()
{
	cout << "This tool produces an instruction stream w/ runtime metadata" << endl;
	cout << KNOB_BASE::StringKnobSummary();
	cout << endl;
	return 2;
}

VOID
LogInstruction(THREADID threadID, ADDRINT address, const char * disasm)
{
	fprintf(outFile, "UN [%d] 0x%lx %s ;\n", 
			threadID, address, disasm);
}

VOID
LogMovInstruction(THREADID threadID, ADDRINT address, const char *disasm)
{
}

VOID
LogBranchOrCall(THREADID threadID, ADDRINT address, const char * disasm, ADDRINT target)
{
	fprintf(outFile, "BR [%d] 0x%lx %s ; 0x%lx\n",
			threadID, address, disasm, target);
}

VOID
LogMemoryRead(THREADID threadID, ADDRINT address, const char * disasm,
		ADDRINT readaddr, UINT32 size,
		const CONTEXT *ctx, void *data)
{
	std::list<REG> * registers = (std::list<REG> *) data;


	fprintf(outFile, "RD [%d] 0x%lx %s ; 0x%lx [%lx]",
			threadID, address, disasm, readaddr,
			(*(unsigned long *)readaddr) );

	fprintf(outFile, "{");
	for (std::list<REG>::iterator it = registers->begin();
			it != registers->end(); it++) {
		REG reg = (*it);
		std::string name = REG_StringShort(reg);
		ADDRINT value = 0;
		// value = PIN_GetContextReg(ctx, reg);

		fprintf(outFile, " %s:%lx ", name.c_str(), value);
	}
	fprintf(outFile, "}\n");
}

VOID
LogMemoryRead2(THREADID threadID, ADDRINT address, const char * disasm,
		ADDRINT readaddr, UINT32 size, ADDRINT readaddr2)
{
	fprintf(outFile, "RD [%d] 0x%lx %s ; 0x%lx [%lx], 0x%lx [%lx]\n",
			threadID,  address, disasm,
			 readaddr,  (*(unsigned long *)readaddr),
			 readaddr2, (*(unsigned long *)readaddr2));
}

VOID
LogMemoryWrite(THREADID threadID, ADDRINT address, const char * disasm,
		ADDRINT writeaddr, UINT32 size)
{
	fprintf(outFile, "WR [%d] 0x%lx %s ; 0x%lx [%lx]\n",
			threadID, address, disasm,
			 writeaddr, (*(unsigned long *)writeaddr));
}

const char *
dumpInstruction(INS ins)
{
	ADDRINT address = INS_Address(ins);
	std::stringstream ss;

	// Generate instruction byte encoding
	for (size_t i=0;i<INS_Size(ins);i++)
	{
		ss << setfill('0') << setw(2) << hex << (((unsigned int) *(unsigned char*)(address + i)) & 0xFF) << " ";
	}

	for (size_t i=INS_Size(ins);i<8;i++)
	{
		ss << "   ";
	}

	// Generate diassembled string
	ss << INS_Disassemble(ins);

	return strdup(ss.str().c_str());
}


std::list<REG> *
listRegisters(INS ins)
{
	std::list<REG> *registers = new std::list<REG>;

	for (UINT32 i = 0; i < INS_OperandCount(ins); i++) {
		if (INS_OperandIsReg(ins, i)) {
			REG reg = INS_OperandReg(ins, i);
			registers->push_back(reg);
		}
	}

	return registers;
}

VOID
TraceInstructions(INS ins, VOID *arg)
{
	/*
	ADDRINT	address = INS_Address(ins);
	unsigned char *opcodes = (unsigned char *)address;
	char nbytes = INS_Size(ins);
	*/

	const char * disasm = dumpInstruction(ins);

	fprintf(stderr, "%s\n", OPCODE_StringShort(INS_Opcode(ins)).c_str());


	if (INS_IsBranchOrCall(ins)) {
		// log direct call
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogBranchOrCall,
			// IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_BRANCH_TARGET_ADDR,
			IARG_END);
	} else if (INS_IsRet(ins) || INS_IsSysret(ins)) {
		// log return
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogInstruction,
			// IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_END);
	} else if (INS_IsMemoryRead(ins)) {
		if (!INS_HasMemoryRead2(ins)) {
			// memory read instruction
			INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogMemoryRead,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_MEMORYREAD_EA, // effective address being read
			IARG_MEMORYREAD_SIZE, // num bytes read
			IARG_MEMORYREAD2_EA,
			IARG_CONTEXT,
			IARG_PTR, (void *) listRegisters(ins),
			IARG_END);
		} else {
			INS_InsertCall(ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogMemoryRead2,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_MEMORYREAD_EA, // effective address being read
			IARG_MEMORYREAD_SIZE, // num bytes read
			IARG_MEMORYREAD2_EA, // effective address being read
			IARG_END);
		}
	} else if (INS_IsMemoryWrite(ins)) {
		// memory write instruction
		INS_InsertCall(ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogInstruction,
			// IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_MEMORYWRITE_EA, // effective address being written
			IARG_MEMORYWRITE_SIZE, // num bytes writen
			IARG_END);
//	} else if (INS_IsNop(ins)) {
		// log nop
	} else if (INS_IsMov(ins)) {
		INS_InsertCall(ins,
				IPOINT_BEFORE,
				(AFUNPTR) LogMovInstruction,
				IARG_THREAD_ID,
				IARG_INST_PTR,
				IARG_PTR, disasm,
				IARG_END
			      );

	} else {
		// log generic instruction
		INS_InsertCall( ins,
			IPOINT_BEFORE,
			(AFUNPTR) LogInstruction,
			// IARG_START,
			IARG_THREAD_ID, // thread ID of the executing thread
			IARG_INST_PTR, // address of instruction
			IARG_PTR, disasm, // disassembled string
			IARG_END);
	}
}

VOID
Fini(INT32 code, VOID *v)
{
	fflush(outFile);
	fclose(outFile);
}


int main(int argc, char **argv)
{
	PIN_SetSyntaxXED();
	PIN_InitSymbols();

	if (PIN_Init(argc, argv)) {
		return Usage();
	}

    	outFile = fopen(outputFile.Value().c_str(), "wb+");

	INS_AddInstrumentFunction(TraceInstructions, 0);

	PIN_AddFiniFunction(Fini, 0);

	// never returns..
	PIN_StartProgram();

	return 0;
}
