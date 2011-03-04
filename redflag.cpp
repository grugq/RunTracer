/*
 * redflag.c: detect writes to heap memory outside allocated chunks
 *
 * (c) 2011, the grugq <the.grugq@gmail.com>
 */


#include "pin.H"
#include <stdio.h>
#include <algorithm>
#include <iostream>
#include <list>
#include <map>

namespace WINDOWS
{
#include <windows.h>
}

/*
 * GLOBALS
 */

KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
                "o", "redflag.txt", "specifity trace file name");
static FILE * LogFile;

// forward declaration
class chunklist_t;

/*
 * housekeeping classes
 */
class chunk_t {
public:
	chunk_t(unsigned long address, unsigned long size)
		: mAddress(address), mSize(size)
	{};
	chunk_t(const chunk_t &chunk)
		: mAddress(chunk.mAddress), mSize(chunk.mSize)
	{};
	chunk_t(const chunk_t *chunk)
		: mAddress(chunk->mAddress), mSize(chunk->mSize)
	{};
	~chunk_t() {};

	bool contains(unsigned long addr) {
		if (addr >= mAddress && addr <= (mAddress+mSize))
			return true;
		return false;
	}

	bool operator< (chunk_t *rhs) {
		return mAddress < rhs->mAddress;
	}
	bool operator< (const chunk_t &rhs) {
		return mAddress < rhs.mAddress;
	};
	bool operator< (const unsigned long address) {
		return mAddress < address;
	}

	const unsigned long address() { return mAddress; };
	const unsigned long size() { return mSize; };

private:
	unsigned long	mAddress;
	unsigned long	mSize;
};


class chunklist_t {
public:
	chunklist_t() 
		: mInserts(0), mRemoves(0)
	{};
	~chunklist_t() {};

	void insert(unsigned long address, unsigned long size);
	void remove(unsigned long address);
	bool contains(unsigned long address);
	bool has_address(unsigned long address);
	bool in_range(unsigned long address);

	std::list<chunk_t>::iterator	begin() {return mChunks.begin(); };
	std::list<chunk_t>::iterator	end() {return mChunks.end(); };
	unsigned int size() const { return mChunks.size(); }

private:
	std::list<chunk_t>	mChunks;
	unsigned int		mInserts;
	unsigned int		mRemoves;
};


/* 
 * GLOBALS (again)
 */
chunklist_t	 ChunksList;

void
chunklist_t::insert(unsigned long address, unsigned long size)
{
	chunk_t	chunk(address, size);
	std::list<chunk_t>::iterator	low;

	low = std::lower_bound(mChunks.begin(), mChunks.end(), chunk);

	mChunks.insert(low, chunk);
}

void
chunklist_t::remove(unsigned long address)
{
	std::list<chunk_t>::iterator	low;

	low = std::lower_bound(mChunks.begin(), mChunks.end(), address);

	if (low != mChunks.end() && (*low).address() == address)
		mChunks.erase(low);
}

// address is in a chunk range
bool
chunklist_t::contains(unsigned long address)
{
	std::list<chunk_t>::iterator	low;

	low = std::lower_bound(mChunks.begin(), mChunks.end(), address);

	if (low != mChunks.end() && ((*low).contains(address)))
		return true;

	low--; // preceding chunk ? 
	if (low != mChunks.end() && (*low).contains(address))
		return true;
	return false;
}

// has the exact address
bool
chunklist_t::has_address(unsigned long address)
{
	std::list<chunk_t>::iterator	low;

	low = std::lower_bound(mChunks.begin(), mChunks.end(), address);

	if (low != mChunks.end() && ((*low).address() == address))
		return true;
	return false;
}

bool
chunklist_t::in_range(unsigned long address)
{
	if (address >= mChunks.front().address() && 
	    address <= (mChunks.back().address() + mChunks.back().size()))
		return true;
	return false;
}

static void
log_redflag(ADDRINT address, ADDRINT ea)
{
	fprintf(LogFile, "eip:%x ea:%x\n", address, ea);
}

#define STACKSHIFT	(3*8)
#define	is_stack(EA, SP)	(((SP)>>STACKSHIFT)==((EA)>>STACKSHIFT))

static void
write_ins(ADDRINT eip, ADDRINT esp, ADDRINT ea)
{
	// is it on the stack?
	if (is_stack(ea, esp))
		return;

	// is it in a known heap region?
	if (!ChunksList.in_range(ea))
		return;

	// is it in the heap?
	if (ChunksList.contains(ea))
		return;

	// is it in a mmap() file?
	// ... not sure how to test this

	log_redflag(eip, ea);
}
#undef STACKSHIFT
#undef is_stack

static void
trace_instructions(INS ins, VOID *arg)
{
	if (INS_IsMemoryWrite(ins))
		INS_InsertCall(ins, IPOINT_BEFORE,
				AFUNPTR(write_ins),
				IARG_INST_PTR,
				IARG_REG_VALUE, REG_STACK_PTR,
				IARG_MEMORYWRITE_EA,
				IARG_END
			       );
}

// on malloc() chunklist.insert(address, size)
// on free() chunklist.remove(address)
// on realloc() chunklist.remove(address), insert(naddress, size)

static WINDOWS::PVOID
replacementRtlAllocateHeap(
		AFUNPTR rtlAllocateHeap,
		WINDOWS::PVOID heapHandle,
		WINDOWS::ULONG flags,
		WINDOWS::SIZE_T size,
		CONTEXT * ctx)
{
	WINDOWS::PVOID	retval;

	PIN_CallApplicationFunction(ctx, PIN_ThreadId(),
			CALLINGSTD_STDCALL, rtlAllocateHeap,
			PIN_PARG(void *), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::SIZE_T), size,
			PIN_PARG_END()
			);

	ChunksList.insert((unsigned long) retval, size);

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
			CALLINGSTD_STDCALL, rtlReAllocateHeap,
			PIN_PARG(void *), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::PVOID), memoryPtr,
			PIN_PARG(WINDOWS::SIZE_T), size,
			PIN_PARG_END()
			);
	// XXX should we check for retval == NULL ?

	ChunksList.remove((unsigned long)memoryPtr);
	ChunksList.insert((unsigned long)retval, size);

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
			CALLINGSTD_STDCALL, rtlFreeHeap,
			PIN_PARG(WINDOWS::BOOL), &retval,
			PIN_PARG(WINDOWS::PVOID), heapHandle,
			PIN_PARG(WINDOWS::ULONG), flags,
			PIN_PARG(WINDOWS::PVOID), memoryPtr,
			PIN_PARG_END()
			);

	ChunksList.remove((unsigned long)memoryPtr);

	return retval;
}

VOID
image_load(IMG img, VOID *v)
{
	RTN rtn;

	// check this image actually has the heap functions.
	if ((rtn = RTN_FindByName(img, "RtlAllocateHeap")) == RTN_Invalid())
		return;

	// hook RtlAllocateHeap
	RTN rtlAllocate = RTN_FindByName(img, "RtlAllocateHeap");

	PROTO protoRtlAllocateHeap = \
		PROTO_Allocate( PIN_PARG(void *),
				CALLINGSTD_STDCALL,
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
			PROTO_Allocate( PIN_PARG(void *), CALLINGSTD_STDCALL,
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
	PROTO protoRtlFreeHeap = 
		PROTO_Allocate( PIN_PARG(void *),
				CALLINGSTD_STDCALL,
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

	PROTO_Free(protoRtlFreeHeap);
}

VOID
finish(int ignored, VOID *arg)
{
	fflush(LogFile);
	fclose(LogFile);
}

UINT32
usage()
{
	std::cout << "RedFlag: tool to detecting out of bounds heap writes";
	std::cout << std::endl;
	std::cout << KNOB_BASE::StringKnobSummary();
	std::cout << std::endl;

	return 2;
}

int
main(int argc, char **argv)
{
	PIN_InitSymbols();

	if (PIN_Init(argc, argv))
		return usage();

	LogFile = fopen(KnobOutputFile.Value().c_str(), "wb+");

	INS_AddInstrumentFunction(trace_instructions, NULL);

	IMG_AddInstrumentFunction(image_load, NULL);

	PIN_AddFiniFunction(finish, NULL);

	// never returns..
	PIN_StartProgram();

	return 0;
}
