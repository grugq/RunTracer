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
#define strdup		_strdup
#endif /* WINDOWS_IS_FUCKING_FUCKED */


FILE *outFile;

KNOB<string> outputFile(KNOB_MODE_WRITEONCE, "pintool", "o", "contexttest.out", "specify trace output file name");


UINT32
Usage()
{
	cout << "This tool instruction stream" << endl;
	cout << KNOB_BASE::StringKnobSummary();
	cout << endl;
	return 2;
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

static VOID
LogInstruction(
	/*	ADDRINT address, const char *disasm, */
		const CONTEXT *ctxt)
{
	REG regList[] = { REG_EDI, REG_ESI, REG_EBP, REG_ESP, REG_EBX, 
  			  REG_EDX, REG_ECX, REG_EAX, REG_SEG_CS, REG_SEG_SS, 
  			  REG_SEG_DS, REG_SEG_ES, REG_SEG_FS, REG_SEG_GS, 
  			  REG_EFLAGS };

//	fprintf(outFile, "%#lX :\t%s\t; {", address, disasm);

	for (unsigned i = 0; i < 15; i++) {
		REG reg = regList[i];

		fprintf(outFile, "%s=%lx ", REG_StringShort(reg).c_str(), 
				PIN_GetContextReg(ctxt, reg)
				);
	}

	fprintf(outFile, "}\n");
	fflush(outFile);
}

VOID
TraceInstructions(INS ins, VOID *arg)
{
	// const char * disasm = dumpInstruction(ins);

	INS_InsertCall(ins, IPOINT_BEFORE,
			(AFUNPTR) LogInstruction,
//			IARG_INST_PTR, // address of instruction
//			IARG_PTR, disasm, // disassembled string
			IARG_CONTEXT,
			IARG_END);
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
