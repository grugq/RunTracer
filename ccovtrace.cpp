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
#include <stdlib.h>
#include <map>
#include <list>
#include <iostream>
#include <utility>
#include "pin.H"

class Module {
public:
	Module(string *name, ADDRINT start, ADDRINT end)
		: start(start), end(end)
	{
		this->name = name;
	}

	int compare(ADDRINT addr) { 
		if (addr < this->start) return -1;
		if (addr > this->end) return 1;
		return 0;
	}

	BOOL contains(ADDRINT addr) {
		return ((addr > start) && (addr < end));
	}

	ADDRINT offset(ADDRINT addr) { return addr - start; }

	const string * Name(VOID) { return name; }
	ADDRINT Start(VOID) { return start; }
	ADDRINT End(VOID) { return end; }

private:
	const string	* name;
	ADDRINT		  start;
	ADDRINT		  end;
};

KNOB<string> KnobOutputFile(KNOB_MODE_WRITEONCE, "pintool",
		"o", "trace.out", "specifity trace file name");

FILE	* traceFile;
std::map<std::pair<ADDRINT,ADDRINT>, int>	basicBlocks;
std::map<THREADID, ADDRINT> addressLog;

std::list<Module *>	moduleList;


UINT32
Usage()
{
	cout << "CodeCoverage tool for dumping BBL control flows" << endl;
	cout << KNOB_BASE::StringKnobSummary();
	cout << endl;
	return 2;
}

static VOID
LogBasicBlock(ADDRINT address, THREADID tid)
{
	ADDRINT	currentAddress;

	currentAddress = addressLog[tid];
	addressLog[tid] = address;

	basicBlocks[std::make_pair(currentAddress, address)]++;
}

static VOID
BasicBlockTrace(TRACE trace, BBL bbl)
{
	INS ins = BBL_InsHead(bbl);

	INS_InsertCall(ins, IPOINT_BEFORE,
			AFUNPTR(LogBasicBlock),
			IARG_INST_PTR,
			IARG_THREAD_ID,
			IARG_END
		      );
}

static VOID
Trace(TRACE trace, VOID *v)
{
	for (BBL bbl = TRACE_BblHead(trace); BBL_Valid(bbl); bbl = BBL_Next(bbl)) {
		BasicBlockTrace(trace, bbl);
	}
}

static string *
basename(const string &fullpath)
{
	size_t	found;

	found = fullpath.rfind("\\");
	return new string(fullpath.substr(found + 1));
}

static VOID
ImageLoad(IMG img, VOID *v)
{
	ADDRINT	start = IMG_LowAddress(img);
	ADDRINT	end = IMG_HighAddress(img);
	const string &fullpath = IMG_Name(img);
	string 	* name = basename(fullpath);

	Module	* module = new Module(name, start, end);

	moduleList.push_back(module);
	return;
}

static const string *
lookupSymbol(ADDRINT addr)
{
	std::list<Module *>::iterator	it;
	char	s[256];
	int	found = 0;

	// have to do this whole thing because the IMG_* functions don't work here
	for (it = moduleList.begin(); it != moduleList.end(); it++) {
		if ((*it)->contains(addr)) {

			sprintf(s, "%s+%x", (*it)->Name()->c_str(),
					(*it)->offset(addr));
			found = 1;
			break;
		}
	}

	if (!found) {
		sprintf(s, "?%x", addr);
	}

	return new string(s);
}

static VOID
Fini(int ignored, VOID *v)
{
	for (std::map<std::pair<ADDRINT,ADDRINT>,int>::iterator it = basicBlocks.begin();
			it != basicBlocks.end(); it++) {
		const string	* symbol1 = lookupSymbol((*it).first.first);
		const string 	* symbol2 = lookupSymbol((*it).first.second);

		fprintf(traceFile, "%s\t%s\t%d\n",
				symbol1->c_str(), symbol2->c_str(),
				(*it).second);

		delete symbol1;
		delete symbol2;

	}

        fflush(traceFile);
        fclose(traceFile);
}

int main(int argc, char **argv)
{
	PIN_InitSymbols();

	if (PIN_Init(argc, argv)) {
		return Usage();
	}

	traceFile = fopen(KnobOutputFile.Value().c_str(), "wb+");

	TRACE_AddInstrumentFunction(Trace, 0);

	IMG_AddInstrumentFunction(ImageLoad, 0);

	PIN_AddFiniFunction(Fini, 0);

	PIN_StartProgram();

	return 0;
}
