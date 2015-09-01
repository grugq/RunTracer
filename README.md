RunTrace - Prospector components (part of COSEINC's BugMine)
============================================================

RunTracers
----------

### ccovtrace

Code coverage tracer.

### runtrace

Complex runtime trace analysis tool with more options that necessary.

### exceptiondump

RunTracer to dump the last basic block executed before a first chance execption (windows only).

### redflag
Heap corruption trace tool, logs writes to areas outside allocated heap chunks (windows only).

INSTALLATION
------------

Requirements:

*   PIN (http://www.pintool.org/)
*   Compiler suite (Visual Studio Express) (Windows only)

Procedure:

1. Put the source code under the `${PIN_ROOT}/source/tools/RunTracer/` directory:
    * `cd ${PIN_ROOT}/source/tools/`
    * `git clone https://github.com/grugq/RunTracer/`
    * `cd RunTracer`
2. On Windows, run `..\nmake.bat ccovtrace`
3. On Linux, run `make`

USAGE
-----

Launch using the `pin.bat` or `pin.sh` tool in the `${PIN_ROOT}` directory. See the --help output for more specific command line handling directions.
