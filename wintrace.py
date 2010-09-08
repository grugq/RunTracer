#!c:\python27\python.exe

import sys
import os


pinpath="c:\\PIN\\pin-2.8-33586-msvc9-ia32_intel64-windows"
tracepath=os.path.join(pinpath, "source", "tools", "RunTracer")

pintool = os.path.join(pinpath, "pin.bat")

def run_tracer(tool, args, target):
    tracertool = os.path.join(tracepath, "obj-ia32", "%s.dll" % tool)

    cmd = "%s -t %s %s -- %s" % (pintool, tracertool, args, target)

    print ">>", cmd

    os.system(cmd)

def main(args):
    run_tracer("ccovtrace", "", "winword")

if __name__ == "__main__":
    main(sys.argv)
