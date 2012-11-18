To use it, add to apache.conf:

    PerlSwitches -I/path/to/the/module
    PerlModule BrokenLink
    PerlLogHandler BrokenLink
    Options +ExecCGI

