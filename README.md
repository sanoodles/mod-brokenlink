To use it, add to apache.conf:

    # Enable BrokenLink module
    PerlSwitches -I/path/to/the/module/folder
    PerlModule BrokenLink
    PerlLogHandler BrokenLink
    Options +ExecCGI

