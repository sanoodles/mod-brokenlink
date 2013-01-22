To use it, add to apache2.conf (or httpd.conf):

    # Enable BrokenLink module
    PerlSwitches -I/folder/where/the/module/is
    PerlLoadModule BrokenLink
    PerlLogHandler BrokenLink
    Options +ExecCGI

The default list of notifiable statuses is: 

* 300
* 301
* 400
* 403
* 404
* 410
* 414
* 415
* 501
* 502
* 503
* 504
* 505

But you can override this list by declaring your own list of notifiable statuses in apache2.conf like this:

    # Custom notifiable statuses
    NotifiableStatus 301
    NotifiableStatus 404
    NotifiableStatus 410

local change
.
