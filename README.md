= RunTrace - Prospector components (part of COSEINC's BugMine)

== RunTracers ==

=== ccovtrace ===

Code coverage tracer.

=== runtrace ===

Complex runtime trace analysis tool with more options that necessary.

=== exceptiondump ===

RunTracer to dump the last basic block executed before a first chance execption (windows only).

== INSTALLATION ==

Requirements:
* PIN (http://www.pintool.org/)
* Compiler suite (Visual Studio Express)

Procedure:
# Place this source code in the ${PIN}/tools/source/ directory.
# ..\nmake.bat ccovtrace

== USAGE ==

Launch using the pin.bat tool in the ${PIN}/tools/ directory. See the --help output for more specific command line handling directions.
