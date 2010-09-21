#!c:\python27\python.exe

import optparse
import os
import subprocess
import sys
import time
import win32api
import win32con
import win32process


pinpath="c:\\PIN\\pin-2.8-33586-msvc9-ia32_intel64-windows"
tracepath=os.path.join(pinpath, "source", "tools", "RunTracer")

pintool = os.path.join(pinpath, "pin.bat")


class Process(object):
    flags = win32con.PROCESS_TERMINATE |\
            win32con.PROCESS_QUERY_INFORMATION |\
            win32con.PROCESS_VM_READ

    def __init__(self, pid):
        self.pid = pid
        self.handle = win32api.OpenProcess(self.flags, False, pid)
        self.name = win32process.GetModuleFileNameEx(self.handle, 0)

    def __contains__(self, name):
        return name.lower() in self.name.lower()

    def terminate(self):
        try:
            win32api.TerminateProcess(self.handle, 1)
        except Exception, e:
            print ">>>", repr(e)


def enum_processes():
    for pid in win32process.EnumProcesses():
        try:
            yield Process(pid)
        except:
            pass

def get_process_by_name(name):
    try:
        for proc in enum_processes():
            if name in proc:
                return proc
    except GeneratorExit:
        pass

def kill_dialogs():
    for app in ['OpusApp', 'winword.exe']:
        for button in ['cancel', 'no', 'close', 'ok']:
            os.system('nircmd dlg "%s" "" click %s' % (app, button))

def run_tracer(tool, args, target):
    tracertool = os.path.join(tracepath, "obj-ia32", "%s.dll" % tool)

    cmd = "%s -t %s %s -- %s" % (pintool, tracertool, args, target)

    proc = subprocess.Popen(cmd.split(), close_fds=True, )
    #time.sleep(timeout)
    #proc.terminate()
    #proc.wait()
    #time.sleep(60)
    #p = get_process_by_name(target.split()[0])
    #p.terminate()

def parse_args(args):
    parser = optparse.OptionParser()

    parser.add_option("-o", "--output", help="output file name",
                      default=None, dest="output")
    parser.add_option("-f", "--file", help="input file name",
                      default=None, dest="fname")
    parser.add_option("-t", "--timeout", help="timeout before kill()",
                      default=300, dest="timeout")

    opts, args = parser.parse_args(args)

    opts.timeout = int(opts.timeout)

    if opts.fname is None:
        if len(args) == 2:
            opts.fname = args[1]
        else:
            parser.error("Missing input filename, either -f or argv[1]")

    return opts, args

def main(args):
    opts, args = parse_args(args)

    if opts.output is not None:
        pin_args = "-o %s" % opts.output
    else:
        pin_args = ""

    target = "WINWORD /q  %s" % opts.fname

    run_tracer("ccovtrace", pin_args, target)
    time.sleep(opts.timeout)

    kill_dialogs()
    os.system('nircmd win close ititle "%s"' % "microsoft word")


if __name__ == "__main__":
    main(sys.argv)
