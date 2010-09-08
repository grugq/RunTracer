#!/usr/bin/env python
#
# (c) 2010, the grugq <the.grugq@gmail.com>

import struct


class Record(object):
    def __init__(self, threadid):
        self.threadid = threadid

class CallRecord(object):
    def __init__(self, threadid, address, target):
        super(CallRecord, self).__init__(threadid)
        self.address = address
        self.target = target

class DirectCallRecord(CallRecord): pass
class IndirectCallRecord(CallRecord): pass

class ReturnRecord(Record):
    def __init__(self, threadid, address, retval):
        super(ReturnRecord, self).__init__(threadid)
        self.address = address
        self.retval = retval


class TraceRecord(object):
    def __init__(self, fname):
        self.fp = open(fname)

    def read_header(self, fp):
        header = struct.Struct('II')
        buf = fp.read(header.size)
        if buf == '':
            raise RuntimeError
        typ,threadid = header.unpack(buf)
        return typ,threadid

    def read_call(self, fp):
        record = struct.Struct('PPP')
        buf = fp.read(record.size)
        address,target,esp = record.unpack(buf)
        return address,target,esp

    def read_return(self, fp):
        record = struct.Struct('PPP')
        buf = fp.read(record.size)
        address,retval,esp = record.unpack(buf)
        return address,retval,esp

    def read_basicblock(self, fp):
        record = struct.Struct('P')
        buf = fp.read(record.size)
        address = record.unpack(buf)[0]
        return address

    def read_memory(self, fp):
        record = struct.Struct('PIP')
        buf = fp.read(record.size)
        address, store, target= record.unpack(buf)
        return address, store, target

    def read_record(self, fp):
        typ,threadid = self.read_header(fp)

        if typ == 1:
            addr,target,esp = self.read_call(fp)
            print "[%d] 0x%x CALL 0x%x {%x}" % (threadid, addr, target, esp)
        elif typ == 2:
            addr,target,esp = self.read_call(fp)
            print "[%d] 0x%x BRANCH 0x%x {%x}" % (threadid, addr, target, esp)
        elif typ == 3:
            addr, retval, esp = self.read_return(fp)
            print "[%d] 0x%x RETURN (%x) {%x}" % (threadid, addr, retval, esp)
        elif typ == 4:
            addr = self.read_basicblock(fp)
            print "[%d] 0x%x BBL" % (threadid, addr)
        elif typ == 8:
            address, store, target = self.read_memory(fp)
            d = "STORE" if store else "LOAD"
            print "[%d] %x %s -> %x" % (threadid, address, d, target)

    def process(self):
        try:
            while True:
                self.read_record(self.fp)
        except RuntimeError:
            return

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print "usage: dumptrace.py <tracefile>"
        sys.exit(1)

    records = TraceRecord(sys.argv[1])
    records.process()
