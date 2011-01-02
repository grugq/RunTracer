#!c:\python\python.exe 

import struct
from collections import namedtuple

TRACE_RECORD_MAGIC = 0x0A0BABE0

TRACE_RECORD_CALL = namedtuple.NamedTuple("address target esp")
TRACE_RECORD_RETURN = namedtuple.NamedTuple("address retval esp")
TRACE_RECORD_BBL = namedtuple.NamedTuple("address ")
TRACE_RECORD_HEAP_ALLOC = namedtuple.NamedTuple("heap size address")
TRACE_RECORD_HEAP_REALLOC = namedtuple.NamedTuple("heap oldaddress size address")
TRACE_RECORD_HEAP_FREE = namedtuple.NamedTuple("heap address")
TRACE_RECORD_MEMORY = namedtuple.NamedTuple("address isstore target")
TRACE_RECORD_LIBRARY_LOAD = namedtuple.NamedTuple("low high namelen name")

class StructMixin(object):
    _struct = None
    def __new__(self, buf):
        args = self._struct.unpack_from(buf)
        ntup = super(self)
        return ntup.__new__(self, *args)
    def __len__(self):
        return self._struct.size

class TraceCall(StructMixin, TRACE_RECORD_CALL):
    _struct = struct.Struct('III')
class TraceIndirectCall(TraceCall): pass
class TraceDirectCall(TraceCall): pass
class TraceReturn(StructMixin, TRACE_RECORD_RETURN):
    _struct = struct.Struct('III')
class TraceBBL(StructMixin, TRACE_RECORD_BBL):
    _struct = struct.Struct('I')
class TraceHeapAlloc(StructMixin, TRACE_RECORD_HEAP_ALLOC):
    _struct = struct.Struct('III')
class TraceHeapReAlloc(StructMixin, TRACE_RECORD_HEAP_REALLOC):
    _struct = struct.Struct('IIII')
class TraceHeapFree(StructMixin, TRACE_RECORD_FREE):
    _struct = struct.Struct('II')
class TraceMemory(StructMixin, TRACE_RECORD_MEMORY):
    _struct = struct.Struct('III')
class TraceLibraryLoad(StructMixin, TRACE_RECORD_LIBRARY_LOAD):
    _struct = struct.Struct('III')
    def __new__(self, buf):
        args = self._struct.unpack_from(buf)
        offset = self._struct.size
        name = buf[off:off+args[-1]]
        return super(self).__new__(self, *args, name)
    def __len__(self):
        return self._struct.size + self.namelen

TraceRecordFactory = {
        1 : TraceIndirectCall,
        2 : TraceDirectCall, 
        3 : TraceReturn,
        4 : TraceBBL,
        5 : TraceHeapAlloc,
        6 : TraceHeapReAlloc,
        7 : TraceHeapFree,
        8 : TraceMemory,
        9 : TraceLibraryLoad
}

class TraceRecord(object):
    def __init__(self, rectype, threadid, record):
        self.rectype = rectype
        self.threadid = threadid
        self.record = record

class RunTraceFile(object):
    def __init__(self, fp):
        self.fp = fp
        buf = fp.read(16)
        magic,filesize,addrsize,num_records = struct.unpack('4I', buf)
        if magic != TRACE_RECORD_MAGIC:
            raise RunTimeError("Bad Magic, not a TRACER output file: %s\n", magic)

        self.filesize = filesize
        self.addrsize = addrsize
        self.num_records = num_records

    def read_record(self):
        buf = self.fp.read(8)
        record_type, threadid = struct.unpack('II', buf)
