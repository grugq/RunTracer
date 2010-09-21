/*BEGIN_LEGAL 
Intel Open Source License 

Copyright (c) 2002-2010 Intel Corporation. All rights reserved.
 
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.  Redistributions
in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.  Neither the name of
the Intel Corporation nor the names of its contributors may be used to
endorse or promote products derived from this software without
specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
END_LEGAL */

#include <stdio.h>
#include <map>
#include <iostream>
#include <utility>
#include "pin.H"


KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
		"o", "trace.out", "specifity trace file name");

FILE	* traceFile;
std::map<std::pair<ADDRINT,ADDRINT>, int>	basicBlocks;
std::map<THREADID, ADDRINT> addressLog;


UINT32 Usage()
{
	cout << "RunTrace tool for monitoring program execution" << endl;
	cout << KNOB_BASE::StringKnobSummary();
	cout << endl;
	return 2;
}

static void
LogBasicBlock(ADDRINT address, THREADID tid)
{
	ADDRINT	currentAddress;

	currentAddress = addressLog[tid];
	addressLog[tid] = address;

	basicBlocks[std::make_pair(currentAddress, address)]++;
}

static VOID BasicBlockTrace(TRACE trace, BBL bbl)
{
	INS ins = BBL_InsHead(bbl);

	INS_InsertCall(ins, IPOINT_BEFORE,
			AFUNPTR(LogBasicBlock),
			IARG_INST_PTR,
			IARG_THREAD_ID,
			IARG_END
		      );
}

VOID
Trace(TRACE trace, VOID *v)
{
	for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl)) {
		BasicBlockTrace(trace, bbl);
	}
}

VOID Fini(int ignored, VOID *v)
{
	for (std::map<std::pair<ADDRINT,ADDRINT>,int>::iterator it = basicBlocks.begin();
			it != basicBlocks.end(); it++) {

		fprintf(traceFile, "%#lx\t%#lx\t%d\n", (*it).first.first, (*it).first.second, (*it).second);
	}
	PIN_ExitProcess(-1);
}

int main(int argc, char **argv)
{
	PIN_InitSymbols();

	if (PIN_Init(argc, argv)) {
		return Usage();
	}

	traceFile = fopen(KnobOutputFile.Value().c_str(), "wb+");

	TRACE_AddInstrumentFunction(Trace, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();

	return 0;
}
