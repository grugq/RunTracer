/* 
 * Copyright 2010, the grugq <the.grugq@gmail.com>
 */

#include "pin.H"
#include <stdio.h>
#include <string.h>
#include <iostream>

namespace WINDOWS
{
#include <windows.h>
}

#include "runtrace.h"
#define stack_alloca(x)		_malloca(x)

static FILE * OutFile;
static TRACE_RECORD_FILE_HEADER FileHeader;


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

// image load address tracer
KNOB<BOOL> KnobTraceLibs(KNOB_MODE_WRITEONCE, "pintool",
		"libs", "0", "track library image addresses");


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

	FileHeader.num_records++;
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

static void
EmitHeapAllocateRecord(THREADID threadid, WINDOWS::PVOID memaddr,
		WINDOWS::PVOID heapHandle, WINDOWS::ULONG size)
{
	TRACE_RECORD_HEAP_ALLOC	record;

	record.heap = (ADDRINT) heapHandle;
	record.size = size;
	record.address = (ADDRINT) memaddr;

	EmitRecord(TRACE_TYPE_HEAP_ALLOC, threadid, &record, sizeof(record));
}

static void
EmitHeapReAllocateRecord(THREADID threadid, WINDOWS::PVOID address,
		WINDOWS::PVOID heapHandle, WINDOWS::PVOID oldaddress,
		WINDOWS::ULONG size)
{
	TRACE_RECORD_HEAP_REALLOC	record;

	record.heap = (ADDRINT) heapHandle;
	record.address = (ADDRINT) address;
	record.size = size;
	record.oldaddress = (ADDRINT) oldaddress;

	EmitRecord(TRACE_TYPE_HEAP_ALLOC, threadid, &record, sizeof(record));
}

static void
EmitHeapFreeRecord(THREADID threadid, WINDOWS::PVOID heapHandle, WINDOWS::PVOID address)
{
	TRACE_RECORD_HEAP_FREE	record;

	record.heap = (ADDRINT) heapHandle;
	record.address = (ADDRINT) address;

	EmitRecord(TRACE_TYPE_HEAP_ALLOC, threadid, &record, sizeof(record));
}

static VOID
EmitLibraryLoadEvent(THREADID threadid, const string& name,
			ADDRINT low, ADDRINT high)
{
	TRACE_RECORD_LIBRARY_LOAD	* record;
	size_t	  size;

	size = sizeof(*record) + name.length();
	record = (TRACE_RECORD_LIBRARY_LOAD *) stack_alloca(size);

	record->low = low;
	record->high = high;
	record->namelen = name.length();
	memcpy(record->name, name.c_str(), name.length());

	EmitRecord(TRACE_TYPE_LIBRARY_LOAD, threadid, record, size);
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


static void *
replacementRtlAllocateHeap(
		AFUNPTR rtlAllocateHeap,
		WINDOWS::PVOID heapHandle,
		WINDOWS::ULONG flags,
		WINDOWS::SIZE_T size,
		CONTEXT * ctx)
{
	WINDOWS::PVOID	retval;

	PIN_CallApplicationFunction(ctx, PIN_ThreadId(),
			CALLINGSTD_DEFAULT, rtlAllocateHeap,
			PIN_PARG(void *), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::SIZE_T), size,
			PIN_PARG_END()
			);

	EmitHeapAllocateRecord(PIN_ThreadId(), retval, heapHandle, size);

	return retval;
};

static WINDOWS::PVOID
replacementRtlReAllocateHeap(
		AFUNPTR rtlReAllocateHeap,
		WINDOWS::PVOID heapHandle,
		WINDOWS::ULONG flags,
		WINDOWS::PVOID memoryPtr,
		WINDOWS::SIZE_T size,
		CONTEXT *ctx)
{
	WINDOWS::PVOID	retval;

	PIN_CallApplicationFunction(ctx, PIN_ThreadId(),
			CALLINGSTD_DEFAULT, rtlReAllocateHeap,
			PIN_PARG(void *), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::PVOID), memoryPtr,
			PIN_PARG(WINDOWS::SIZE_T), size,
			PIN_PARG_END()
			);
	EmitHeapReAllocateRecord(PIN_ThreadId(), retval, heapHandle, memoryPtr, size);

	return retval;
}

static WINDOWS::BOOL
replacementRtlFreeHeap(
		AFUNPTR rtlFreeHeap,
		WINDOWS::PVOID heapHandle,
		WINDOWS::ULONG flags,
		WINDOWS::PVOID memoryPtr,
		CONTEXT *ctx)
{
	WINDOWS::BOOL 	retval;

	PIN_CallApplicationFunction(ctx, PIN_ThreadId(),
			CALLINGSTD_DEFAULT, rtlFreeHeap,
			PIN_PARG(WINDOWS::BOOL), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::PVOID), memoryPtr,
			PIN_PARG_END()
			);
	EmitHeapFreeRecord(PIN_ThreadId(), heapHandle, memoryPtr);

	return retval;
}


static VOID
LogImageLoad(IMG img)
{
	const string name = IMG_Name(img);
	ADDRINT low 	= IMG_LowAddress(img);
	ADDRINT high	= IMG_HighAddress(img);

	EmitLibraryLoadEvent(PIN_ThreadId(), IMG_Name(img), 
				IMG_LowAddress(img), IMG_HighAddress(img));
}

static VOID
HookHeapFunctions(IMG img)
{
	RTN rtn;

	// check this image actually has the heap functions.
	if ((rtn = RTN_FindByName(img, "RtlAllocateHeap")) == RTN_Invalid())
		return;

	// hook RtlAllocateHeap
	RTN rtlAllocate = RTN_FindByName(img, "RtlAllocateHeap");

	PROTO protoRtlAllocateHeap = \
		PROTO_Allocate( PIN_PARG(void *),
				CALLINGSTD_DEFAULT,
				"RtlAllocateHeap",
				PIN_PARG(WINDOWS::PVOID), // HeapHandle
				PIN_PARG(WINDOWS::ULONG),    // Flags
				PIN_PARG(WINDOWS::SIZE_T),   // Size
				PIN_PARG_END()
				);

	RTN_ReplaceSignature(rtlAllocate,(AFUNPTR)replacementRtlAllocateHeap,
			IARG_PROTOTYPE, protoRtlAllocateHeap,
			IARG_ORIG_FUNCPTR,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
			IARG_CONTEXT,
			IARG_END
			);

	PROTO_Free(protoRtlAllocateHeap);

	// replace RtlReAllocateHeap()
	RTN rtlReallocate = RTN_FindByName(img, "RtlReAllocateHeap");
	PROTO protoRtlReAllocateHeap = \
			PROTO_Allocate( PIN_PARG(void *), CALLINGSTD_DEFAULT,
					"RtlReAllocateHeap",
					PIN_PARG(WINDOWS::PVOID), // HeapHandle
					PIN_PARG(WINDOWS::ULONG), // Flags
					PIN_PARG(WINDOWS::PVOID), // MemoryPtr
					PIN_PARG(WINDOWS::SIZE_T),// Size
					PIN_PARG_END()
					);

	RTN_ReplaceSignature(rtlReallocate,(AFUNPTR)replacementRtlReAllocateHeap,
			IARG_PROTOTYPE, protoRtlReAllocateHeap,
			IARG_ORIG_FUNCPTR,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 3,
			IARG_CONTEXT,
			IARG_END
			);

	PROTO_Free(protoRtlReAllocateHeap);

	// replace RtlFreeHeap
	RTN rtlFree = RTN_FindByName(img, "RtlFreeHeap");
	PROTO protoRtlFreeHeap = \
		PROTO_Allocate( PIN_PARG(void *), CALLINGSTD_DEFAULT,
				"RtlFreeHeap",
				PIN_PARG(WINDOWS::PVOID), // HeapHandle
				PIN_PARG(WINDOWS::ULONG),    // Flags
				PIN_PARG(WINDOWS::PVOID),   // MemoryPtr
				PIN_PARG_END()
				);

	RTN_ReplaceSignature(rtlFree,(AFUNPTR)replacementRtlFreeHeap,
			IARG_PROTOTYPE, protoRtlFreeHeap,
			IARG_ORIG_FUNCPTR,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 0,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 1,
			IARG_FUNCARG_ENTRYPOINT_VALUE, 2,
			IARG_CONTEXT,
			IARG_END
			);

	PROTO_Free(protoRtlAllocateHeap);
}

VOID ImageLoad(IMG img, VOID *v)
{
	if (KnobTraceLibs)
		LogImageLoad(img);

	if (KnobTraceHeap)
		HookHeapFunctions(img);
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
	FileHeader.filesize = ftell(OutFile);
	fseek(OutFile, 0, SEEK_SET);
	fwrite(&FileHeader, sizeof(FileHeader), 1, OutFile);

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

	FileHeader.addrsize = sizeof(ADDRINT);
	FileHeader.magic = TRACE_RECORD_MAGIC;
	FileHeader.filesize = sizeof(FileHeader);

	fwrite(&FileHeader, sizeof(FileHeader), 1, OutFile);

	TRACE_AddInstrumentFunction(Trace, 0);

	IMG_AddInstrumentFunction(ImageLoad, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();

	return 0;
}
