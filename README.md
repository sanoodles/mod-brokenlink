To use it, add to apache2.conf (or httpd.conf):

    # Enable BrokenLink module
    PerlSwitches -I/folder/where/the/module/is
    PerlModule BrokenLink
    PerlLogHandler BrokenLink
    Options +ExecCGI

    # Custom notifiable statuses
    NotifiableStatus 404
    NotifiableStatus 410
    NotifiableStatus 500

