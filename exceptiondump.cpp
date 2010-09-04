#include "pin.H"
#include <stdio.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <set>
#include <list>
#include <sstream>


/**
* Keeps track of legit instructions before control flow is transferred to she
* shellcode.
**/
std::list<std::string> legitInstructions;

/**
* Keeps track of disassembled instructions that were already dumped.
**/
std::set<std::string*> dumped;

/**
* Output file the shellcode information is dumped to.
**/
FILE *traceFile;

/**
* Command line option to specify the name of the output file.
* Default is shellcode.out.
**/
KNOB<string> outputFile(KNOB_MODE_WRITEONCE, "pintool", "o", "crashdump.out", "specify trace file name");
KNOB<INT32> maxInstructions(KNOB_MODE_WRITEONCE, "pintool", "c", "100", "last instruction log count");

string dumpInstruction(INS ins);

/**
* Prints usage information.
**/
INT32 usage()
{
    cerr << "This tool produces a call trace." << endl << endl;
    cerr << KNOB_BASE::StringKnobSummary() << endl;
    return -1;
}

class Instruction
{
	public:
		Instruction(INS ins);
		~Instruction();

		ADDRINT	Address(void) { return address; }
		string Disassembly(void) { return disassembly; }
	private:
		ADDRINT	address;
		char	* opcodes;
		char	  length;

		string	disassembly;
};

class BasicBlock
{
	public:
		BasicBlock();
		~BasicBlock();

		void addInstruction(Instruction * ins) { instructions.push_back(ins); }

		list<Instruction *>::iterator	begin(void) { return instructions.begin(); }
		list<Instruction *>::iterator	end(void) { return instructions.end(); }

	private:
		list<Instruction *>	instructions;
};

BasicBlock * currentBBL;

Instruction::Instruction(INS ins)
{
	address = INS_Address(ins);
	opcodes = (char *) address;
	length = INS_Size(ins);

	disassembly = dumpInstruction(ins);
}

Instruction::~Instruction()
{
}

BasicBlock::BasicBlock()
{
}

BasicBlock::~BasicBlock()
{
}


/**
* Given a fully qualified path to a file, this function extracts the raw
* filename and gets rid of the path.
**/
std::string extractFilename(const std::string& filename)
{
	unsigned int lastBackslash = filename.rfind("\\");

	if (lastBackslash == -1)
	{
		return filename;
	}
	else
	{
		return filename.substr(lastBackslash + 1);
	}
}

/**
* Given an address, this function determines the name of the loaded module the
* address belongs to. If the address does not belong to any module, the empty
* string is returned.
**/
std::string getModule(ADDRINT address)
{
	// To find the module name of an address, iterate over all sections of all
	// modules until a section is found that contains the address.

	for(IMG img=APP_ImgHead(); IMG_Valid(img); img = IMG_Next(img)) {
		for(SEC sec=IMG_SecHead(img); SEC_Valid(sec); sec = SEC_Next(sec)) {
			if (address >= SEC_Address(sec) && address < SEC_Address(sec) + SEC_Size(sec)) {
				return extractFilename(IMG_Name(img));
			}
		}
	}

	return "";
}

/**
* Converts a PIN instruction object into a disassembled string.
**/
std::string dumpInstruction(INS ins)
{
	// save only the instruction bytes??

	std::stringstream ss;

	ADDRINT address = INS_Address(ins);

	// Generate address and module information
	ss << "0x" << setfill('0') << setw(8) << uppercase << hex << address << "::" << getModule(address) << "  ";

	// Generate instruction byte encoding
	for (int i=0;i<INS_Size(ins);i++)
	{
		ss << setfill('0') << setw(2) << (((unsigned int) *(unsigned char*)(address + i)) & 0xFF) << " ";
	}

	for (int i=INS_Size(ins);i<8;i++)
	{
		ss << "   ";
	}

	// Generate diassembled string
	ss << INS_Disassemble(ins);
	
	// Look up call information for direct calls
	if (INS_IsCall(ins) && INS_IsDirectBranchOrCall(ins))
	{
		ss << " -> " << RTN_FindNameByAddress(INS_DirectBranchOrCallTargetAddress(ins));
	}

	return ss.str();
}

static void
logStart(int exceptionCode)
{
	fprintf(traceFile, "EXCEPTION CODE: %x\n", exceptionCode);
}

static void
logInstructions(void)
{
	std::list<std::string>::iterator	it;


	fprintf(traceFile, "PREVIOUS INSTRUCTIONS:\n");
	for (it = legitInstructions.begin(); it != legitInstructions.end(); it++) {
		fprintf(traceFile, "    %s\n", (*it).c_str());
	}
	fprintf(traceFile, "\n");
}

static void
logBBL(ADDRINT faultAddress)
{
	fprintf(traceFile, "FAULTING BASIC BLOCK\n");
	for (list<Instruction *>::iterator it = currentBBL->begin(); it != currentBBL->end(); it++) {
		if ((*it)->Address() == faultAddress) {
			fprintf(traceFile, "--->");
		} else {
			fprintf(traceFile, "    ");
		}

		fprintf(traceFile, "%s\n", (*it)->Disassembly().c_str());
	}
	fprintf(traceFile, "\n");
}

static void
logContext(const CONTEXT *ctxt)
{
	fprintf(traceFile, "CONTEXT:\n");
	fprintf(traceFile, "EAX: 0x%0.8x EBX: 0x%0.8x ECX: 0x%0.8x EDX: 0x%0.8x\n", 
			PIN_GetContextReg( ctxt, REG_GAX ), PIN_GetContextReg( ctxt, REG_GBX ),
			PIN_GetContextReg( ctxt, REG_GCX ), PIN_GetContextReg( ctxt, REG_GDX )
		);
	fprintf(traceFile, "ESI: 0x%0.8x EDI: 0x%0.8x EBP: 0x%0.8x ESP: 0x%0.8x\n",
			PIN_GetContextReg( ctxt, REG_GSI ), PIN_GetContextReg( ctxt, REG_GDI ),
			PIN_GetContextReg( ctxt, REG_GBP ), PIN_GetContextReg( ctxt, REG_ESP )
		);
	fprintf(traceFile, "SS : 0x%0.8x CS : 0x%0.8x DS : 0x%0.8x ES : 0x%0.8x\n",
			PIN_GetContextReg( ctxt, REG_SEG_SS ), PIN_GetContextReg( ctxt, REG_SEG_SS ),
			PIN_GetContextReg( ctxt, REG_SEG_DS ), PIN_GetContextReg( ctxt, REG_SEG_ES )
		);
	fprintf(traceFile, "FS : 0x%0.8x GS : 0x%0.8x GFLAGS: 0x%0.8x IP: 0x%0.8x\n",
			PIN_GetContextReg( ctxt, REG_SEG_FS ), PIN_GetContextReg( ctxt, REG_SEG_GS ),
			PIN_GetContextReg( ctxt, REG_GFLAGS ), PIN_GetContextReg( ctxt, REG_INST_PTR )
		);
	fprintf(traceFile, "\n");
}

static void
logEnd(void)
{
	fflush(traceFile);
	fclose(traceFile);
}

static void OnException(THREADID threadIndex, 
                  CONTEXT_CHANGE_REASON reason, 
                  const CONTEXT *ctxtFrom,
                  CONTEXT *ctxtTo,
                  INT32 info, 
                  VOID *v)
{
	if (reason != CONTEXT_CHANGE_REASON_EXCEPTION)
		return;

        UINT32 exceptionCode = info;
	ADDRINT	address = PIN_GetContextReg(ctxtFrom, REG_INST_PTR);

        // Depending on the system and CRT version, C++ exceptions can be implemented 
        // as kernel- or user-mode- exceptions.
        // This callback does not not intercept user mode exceptions, so we do not 
        // log C++ exceptions to avoid difference in output files.
        if ((exceptionCode >= 0xc0000000) && (exceptionCode <= 0xcfffffff))
        {
		logStart(exceptionCode);
		// logInstructions();
		logBBL(address);
		logContext(ctxtFrom);
		logEnd();
		PIN_ExitProcess(-1);
        }
}

static void
basicBlockLogger(BasicBlock * bbl)
{
	currentBBL = bbl;
	return;
}

void Trace(TRACE trace, VOID *)
{
	for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl)) {
		BasicBlock * basicBlock = new BasicBlock();

		for (INS ins = BBL_InsHead(bbl); INS_Valid(ins); ins = INS_Next(ins)) {
			basicBlock->addInstruction(new Instruction(ins));
		}


		BBL_InsertCall(bbl, IPOINT_BEFORE,
				(AFUNPTR) basicBlockLogger,
				IARG_PTR, basicBlock,
				IARG_END
			      );

	}
}

void TraceInst(INS ins, VOID*)
{
	// The address is a legit address, meaning it is probably not part of
	// any shellcode. In this case we just log the instruction to dump it
	// later to show when control flow was transfered from legit code to
	// shellcode.

	legitInstructions.push_back(dumpInstruction(ins));

	if (legitInstructions.size() > maxInstructions)
	{
		legitInstructions.pop_front();
	}
}

VOID Fini(INT32 code, VOID *v)
{
}

int main(INT32 argc, CHAR **argv)
{

    PIN_InitSymbols();
    PIN_Init(argc, argv);

    traceFile = fopen(outputFile.Value().c_str(), "wb+");

    PIN_AddContextChangeFunction(OnException, 0);
    TRACE_AddInstrumentFunction(Trace, 0);

//    PIN_AddFiniFunction(Fini, 0);

    // Never returns
    PIN_StartProgram();

    return 0;
}
