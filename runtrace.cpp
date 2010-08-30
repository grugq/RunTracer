/* 
 * Copyright 2010, the grugq <the.grugq@gmail.com>
 */

#include "pin.H"
#include <stdio.h>
#include <string.h>
#include <iostream>

#include "runtrace.h"

static FILE * OutFile;


KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
		"o", "trace.out", "specifity trace file name");

// heap-trace
KNOB<BOOL> KnobTraceHeap(KNOB_MODE_WRITEONCE, "pintool",
		"heap", "0", "trace heap operations");

// basic block trace
KNOB<BOOL> KnobTraceBasicBlocks(KNOB_MODE_WRITEONCE, "pintool",
		"bbl", "0", "enable basic block tracing");

// call / ret trace
KNOB<BOOL> KnobTraceCalls(KNOB_MODE_WRITEONCE, "pintool",
		"call", "0", "enable call/ret tracing");

// memory tracer
KNOB<BOOL> KnobTraceMemory(KNOB_MODE_WRITEONCE, "pintool",
		"memory", "0", "enable memory tracing");


UINT32 Usage()
{
	cout << "RunTrace tool for monitoring program execution" << endl;
	cout << KNOB_BASE::StringKnobSummary();
	cout << endl;
	return 2;
}

VOID EmitRecord(UINT32 tracetype, THREADID threadid, void *rec_data, size_t len)
{
	TRACE_RECORD	record;

	memset(&record, 0, sizeof(record));

	record.header.type = tracetype;
	record.header.threadid = threadid;

	memcpy(&record.call, rec_data, len);

	fwrite(&record, sizeof(TRACE_RECORD_HEADER) + len, 1, OutFile);
}

VOID EmitBasicBlock(THREADID threadid, ADDRINT address)
{
	TRACE_RECORD_BASIC_BLOCK	record;

	record.address = address;

	EmitRecord(TRACE_TYPE_BASIC_BLOCK, threadid, &record, sizeof(record));
}

VOID EmitIndirectCall(THREADID threadid, ADDRINT address, ADDRINT target, ADDRINT esp)
{
	TRACE_RECORD_CALL	record;

	record.address = address;
	record.target = target;
	record.esp = esp;

	EmitRecord(TRACE_TYPE_INDIRECT_CALL, threadid, &record, sizeof(record));
}

VOID EmitDirectCall(THREADID threadid, ADDRINT address, ADDRINT target, ADDRINT esp)
{
	TRACE_RECORD_CALL	record;

	record.address = address;
	record.target = target;
	record.esp = esp;

	EmitRecord(TRACE_TYPE_DIRECT_CALL, threadid, &record, sizeof(record));
}

VOID EmitReturn(THREADID threadid, ADDRINT address, ADDRINT retval, ADDRINT esp)
{
	TRACE_RECORD_RETURN	record;

	record.address = address;
	record.retval = retval;
	record.esp = esp;

	EmitRecord(TRACE_TYPE_RETURN, threadid, &record, sizeof(record));
}

static VOID EmitMemory(THREADID threadid, ADDRINT address, bool isStore, ADDRINT ea)
{
	TRACE_RECORD_MEMORY	record;

	record.store = isStore;
	record.address = address;
	record.target = ea;

	EmitRecord(TRACE_TYPE_MEMORY, threadid, &record, sizeof(record));
}

VOID CallTrace(TRACE trace, INS ins)
{
	if (!KnobTraceCalls)
		return;

	// RTN = TRACE_Rtn(trace);
	// ADDRINT rtn_addr = RTN_Address(rtn);

	if (INS_IsCall(ins) && !INS_IsDirectBranchOrCall(ins)) {
		// Indirect Call
		INS_InsertCall(ins, IPOINT_BEFORE,
				AFUNPTR(EmitIndirectCall),
				IARG_THREAD_ID,
				IARG_INST_PTR,
				IARG_BRANCH_TARGET_ADDR,
				IARG_REG_VALUE, REG_STACK_PTR,
				IARG_END
			      );

	} else if (INS_IsDirectBranchOrCall(ins)) {
		// Direct call..
		ADDRINT target = INS_DirectBranchOrCallTargetAddress(ins);
		INS_InsertCall(ins, IPOINT_BEFORE,
				AFUNPTR(EmitDirectCall),
				IARG_THREAD_ID,
				IARG_INST_PTR,
				IARG_ADDRINT, target,
				IARG_REG_VALUE, REG_STACK_PTR,
				IARG_END
			      );
	} else if (INS_IsRet(ins)) {
		INS_InsertCall(ins, IPOINT_BEFORE,
				AFUNPTR(EmitReturn),
				IARG_THREAD_ID,
				IARG_INST_PTR,
				IARG_FUNCRET_EXITPOINT_VALUE,
				IARG_REG_VALUE, REG_STACK_PTR,
				IARG_END
			      );
	}
}

static VOID BasicBlockTrace(TRACE trace, BBL bbl)
{
	if (!KnobTraceBasicBlocks)
		return;

	INS ins = BBL_InsHead(bbl);

	INS_InsertCall(ins, IPOINT_BEFORE,
			AFUNPTR(EmitBasicBlock),
			IARG_THREAD_ID,
			IARG_INST_PTR,
			IARG_END
		      );
}


static VOID MemoryTrace(TRACE trace, INS ins)
{
	if (!KnobTraceMemory)
		return;

	if (INS_IsMemoryRead(ins) ||
	    INS_HasMemoryRead2(ins) ||
	    INS_IsMemoryWrite(ins)
	   ) {
		INS_InsertCall(ins, IPOINT_BEFORE,
				AFUNPTR(EmitMemory),
				IARG_THREAD_ID,
				IARG_INST_PTR,
				IARG_BOOL, INS_IsMemoryWrite(ins),
				(INS_IsMemoryWrite(ins) ?
				 	IARG_MEMORYWRITE_EA :
				 INS_IsMemoryRead(ins) ?
				 	IARG_MEMORYREAD_EA : IARG_MEMORYREAD2_EA),
				IARG_END
			      );
	}
}

VOID ImageLoad(IMG *img, VOID *v)
{
	if (!KnobTraceHeap)
		return;
	//
	// RTN_FindByName(img, "RtlAllocateHeap")
	// RTN_ReplaceSignature();

	// replace RtlAllocateHeap(), RtlReallocateHeap(), RtlFreeHeap()
	// replacement functions should store args, call underlying code,
	// the EmitHeap*() using returned value
}

VOID
Trace(TRACE trace, VOID *v)
{
	for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl)) {
		BasicBlockTrace(trace, bbl);

	 	for (INS ins = BBL_InsHead(bbl); INS_Valid(ins); ins = INS_Next(ins)) {
			CallTrace(trace, ins);
			MemoryTrace(trace, ins);
		}
	}
}

VOID Fini(int, VOID *v)
{
	fflush(OutFile);
	fclose(OutFile);
}

int main(int argc, char **argv)
{
	PIN_InitSymbols();

	if (PIN_Init(argc, argv)) {
		return Usage();
	}

	OutFile = fopen(KnobOutputFile.Value().c_str(), "wb+");

	TRACE_AddInstrumentFunction(Trace, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();

	return 0;
}
