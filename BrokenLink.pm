=pod
This is going to be a Perl port of mod_brokenlink
http://code.google.com/p/modbrokenlink/
which is written in C.

It runs on top of mod_perl, whose API is:
http://perl.apache.org/docs/2.0/api/index.html

What is not provided by mod_perl API should be provided by 
Perl native or some CPAN module.

Technically, is a mod_perl handler.

Examples of mod_perl handlers:
http://perl.apache.org/docs/2.0/user/handlers/intro.html
http://modperlbook.org/code/chapters/ch25-next_generation/Book/Eliza2.pm
http://cpan-search.sourceforge.net/Apache2/DocServer.pm.html
https://svn.apache.org/repos/asf/spamassassin/branches/check_plugin/spamd-apache2/lib/Mail/SpamAssassin/Spamd/Apache2/Config.pm
http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlLogHandler
http://search.cpan.org/~stas/DocSet-0.19/examples/site/src/start/tips/logging.pod

This file contains:
1, Includes
2. Constants
3. Testing helpers
4. The meat
=cut



package BrokenLink;



use strict;
use warnings;



=pod
1. Includes
=cut
use POSIX qw/strftime/;
use IO::Socket::INET;
use URI::Escape;
use Apache2::Module ();
use Apache2::RequestRec ();
use Apache2::ServerRec ();
use APR::Const ();
use APR::Socket ();
use APR::Table ();
use APR::URI ();



=pod
2. Constants
=cut

use constant {
  MBL_FALSE => 0,
  MBL_TRUE => 1,
  DEF_SOCK_TIMEOUT => 30 * (10 ** 6),
  CRLF_STR => "\r\n",
  TIME_FORMAT => "%Y-%m-%d %H:%M:%S",
  TIME_FORMAT_ISO => "%Y-%m-%dT%H:%M:%S%z",
  MODULE => "mod_brokenlink",
  URISIZE => 1024
};

# debugging
use constant {
  MBL_DEBUG_MODE => MBL_TRUE
};

# notification sending
use constant {
  MBL_NOTIFY_FILENAME => "/mod_brokenlink_notify",
  MBL_NOTIFY_REFLEXIVE => MBL_FALSE,
  MBL_USER_AGENT => "Apache mod_brokenlink"
};

use Apache2::Const -compile => qw(OK);



=pod
3. Testing helpers
=cut

# @return Current datetime in TIME_FORMAT. eg: "2009-06-15 19:58:13".
sub now {
  return strftime(TIME_FORMAT, localtime);
}

# Prints a string to the STDERR iif MBL_DEBUG_MODE is MBL_TRUE.
sub test {
  my $string = shift;
  if (MBL_DEBUG_MODE == MBL_TRUE) {
    print STDERR "mbltest " . now() . ": $string\n";
  }
}

# Prints the fields of a notification object to the STDERR.
sub nftest {
  my $nf = shift;
  test("nftest");
  test($$nf{"time"});
  test($$nf{"from"});
  test($$nf{"to"});
  test($$nf{"status"});
}

# Prints one row of an APR table to the STDERR.
sub tabletest_row {
  my ($rec, $key, $value) = @_;

  test("tabletest_row");
  test("key: $key");
  test("value: $value");

  return 1; # return 1 so the iteration continues
}

sub tabletest {
  test("tabletest");
  my $t = shift;

  $t->do(tabletest_row);
}



=pod
4. The meat
=cut

# @return Module config.
sub config_get {
  my $r = shift;
  
  my $cfg = Apache2::Module->get_config(__PACKAGE__, 
      $r->server, 
      $r->per_dir_config);

  return $cfg;
}

=pod
Fills a (dis)trusted notification object with given data
@param res Notification to fill
@param id Notification id
@param time Notification's "time" field
@param qtt Quantity field. > 1 if represents a group of notifications
@param from Notification's "from" field
@param to Notification's "to" field
@param status Notifications "status" field
=cut
sub nf_common_create {
  my ($res, $id, $time, $qtt, $status, $from, $to) = @_;
  test("nf_common_create");

  $$res{"id"} = $id;

  $$res{"time"} = defined $time ? $time : "";
  
  $$res{"qtt"} = $qtt;

  $$res{"status"} = $status;

  $$res{"from"} = defined $from ? $from : "";

  $$res{"to"} = defined $to ? $to : "";

  test("status: $status from: $from to: $to");
  test("nf_common_create return");
}

=pod
Creates a (dis)trusted notification object from raw data
=cut
sub nf_create {
  my ($id, $time, $qtt, $trust, $status, $from, $to) = @_;

  my %res;

  $res{"trust"} = $trust;

  nf_common_create(\%res, $id, $time, $qtt, $status, $from, $to);

  test("nf_create return");
  return \%res;
}

=pod
Here were:
config_server_create
config_server_merge
cmd_able_status
cmds[]

Not ported yet because don't recall exactly what they did, and don't know how to port them yet.
=cut

# Socket connection
# @see http://www.thegeekstuff.com/2010/07/perl-tcp-udp-socket-programming/
sub socket_open {
  my ($r, $sock, $hostname, $port) = @_;

  $| = 1;

  $sock = new IO::Socket::INET (
    PeerHost => $hostname,
    PeerPort => $port,
    Proto => 'tcp',
    # Timeout => DEF_SOCK_TIMEOUT
  ) or die "ERROR in Socket Creation : $!\n";

  return MBL_TRUE;
}

=pod
Creates a notification object from the data of the current request
@param r Current request_rec
@return Notification object
=cut
sub nf_pack {
  my ($r) = @_;

  my $notification;

  my $time = "";

  my $from = $r->headers_in->get("Referer");

  if (!defined $from || $from eq "") {
    test("Void referer. Can not pack notification.");
    return undef;
  }
  test("from: $from");

  my $to = $r->unparsed_uri;
  test("to: $to");

  my $status = $r->status;
  test("status: $status");

  $notification = nf_create(0, $time, 1, MBL_TRUE, $status, $from, $to);

  test("nf_pack return");
  return $notification;
}

=pod
Alias for uri_escape
@see http://search.cpan.org/dist/URI/URI/Escape.pm
=cut
sub urlencode {
  my $str = shift;

  return uri_escape($str);
}

# Alias for uri_unescape
sub urldecode {
  my $str = shift;

  return uri_unescape($str);
}

# @return A URI-like serialization of a notification object
sub nf_xraw2uri {
  my $nf = shift;

  my $res = MBL_NOTIFY_FILENAME . 
      "?from=" . urlencode($$nf{"from"}) . 
      "&status=" . $$nf{"status"} . 
      "&to=" . $$nf{"to"};

  return $res;
}

=pod
Composes a generic HTTP GET request from discrete fields.
@param uri The resource (tipically a web page) requested
@param host The host to request to
@param referer Value for the HTTP Referer field
@param user_agent Value for the HTTP User-Agent field
@see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.htmlç
=cut
sub http_get_compose {
  my ($uri, $host, $referer, $user_agent) = @_;
  test("http_get_compose");

  my $res = "GET $uri HTTP/1.1" . CRLF_STR . 
            "Host: $host" . CRLF_STR . 
            "Referer: $referer" . CRLF_STR .
            "User-Agent: $user_agent" . CRLF_STR .
            CRLF_STR;

  test("http_get_compose return");
  return $res;
}

=pod
Converts a notification hash with fields:
time
from
to
status

To an HTTP request like
GET MBL_NOTIFY_FILENAME?from=<from>&status=<status>
Host: <from.hostname>
Referer: <to>
User-Agent: MBL_USER_AGENT
=cut
sub nf_xraw2req {
  my $nf = shift;

  my $resource = nf_xraw2uri($nf);

  my $host = APR::URI->parse($$nf{from})->hostname; 
  # TODO test if it works without quotes, and do the same in the whole code

  my $referer = $$nf{"to"};

  my $user_agent = MBL_USER_AGENT;

  my $res = http_get_compose($resource, $host, $referer, $user_agent);

  test("nf_xraw2req return");
  return $res;
}

=pod
Transmits notification to referer
Test case: Access to http://localhost/a_non_existent_page.html
=cut
sub nf_tx {
  my ($r, $nf) = @_;
  test("nf_tx");

  my $socket ;

  my $parsed_uri = APR::URI->parse($$nf{"from"});

  my $referer_hostname = $parsed_uri->hostname;
  test("referer_hostname: $referer_hostname");

  my $referer_port = $parsed_uri->port;
  test("referer_port:  $referer_port");

  if (socket_open($r, $socket, $referer_hostname, $referer_port) == MBL_FALSE) {
    test("nf_tx return with error at socket_open");
    return MBL_FALSE;
  }

  my $req_header = nf_xraw2req($nf);

  my $len = length $req_header;

  my $ret = $socket->send($req_header);
  test("socket->send returned: $ret");

  test("**** SENDING NOTIFICATION ****");
  if ($ret == 0) { # assuming 0 is send error
    test("socket->send returned an error.");
    return MBL_FALSE;
  }

  $socket->close();

  test("nf_tx return");
  return MBL_TRUE;
}

=pod
@param uri URI
@return Whether the URI host is the localhost
=cut
sub is_it_me {
  my ($r, $uri) = @_;
  test("is_it_me");

  my $res;

  if ($uri eq "") {
    test("Asked host is \"\"");
    return MBL_FALSE;
  }

  my $localhostname = $r->server()->server_hostname();

  my $parsed_uri = APR::URI->parse($uri);

  my $uri_hostname = $parsed_uri->hostname;

  test("localhostname: $localhostname");
  test("uri_hostname: $uri_hostname");

  if (!defined $uri_hostname) {
    test("No host referer explicited; assuming localhost.");
    return MBL_TRUE;
  }

  if ($localhostname eq $uri_hostname) {
    test("Asked host is localhost");
    return MBL_TRUE;
  }

  if ("localhost" eq $uri_hostname) {
    test("Asked host is localhost");
    return MBL_TRUE;
  }

  if ("127.0.0.1" eq $uri_hostname) {
    test("Asked host is localhost");
    return MBL_TRUE;
  }

  test("Asked host is NOT localhost");
  return MBL_FALSE;
}

=pod
@return Whether the target of the ongoing request is potentially notifiable or not.
Since the notifications are performed as an ordinary access to a non-existent
file, receiving a notification would cause in turn to send back a 
notification and a sweet-dude dialog would start.
http://www.imdb.com/title/tt0242423/quotes#qt0397841
=cut
sub able_to {
  my ($r, $to) = @_;
  test("able_to");

  my $res;

  my $to_filename = substr $to, 0, length MBL_NOTIFY_FILENAME;

  if ($to_filename eq MBL_NOTIFY_FILENAME) {
    $res = MBL_FALSE;
  } else {
    $res = MBL_TRUE;
  }

  test("res: $res");
  test("able_to return");
  return $res;
}

=pod
@return Whether the status of the ongoing request is potentially notifiable or not.
If notifiable status list is empty
  It uses the default notifiable status list
Else
  It uses the list ones
=cut
sub able_status {
  my ($r, $status) = @_;
  test("able_status");

  my $res;

  my $cfg = config_get($r->server());

  my $t = $$cfg{"notifiable_status"};

  # I totally don't know what I'm doing
  if (length $t == 0) {
    $t = $$cfg{"notifiable_status_default"};
  }

  if (!defined $t->get($status)) {
    $res = MBL_TRUE;
  } else {
    $res = MBL_FALSE;
  }

  test("res: $res");
  test("able_status return");
  return $res;
}

# @return Whether the referer of the ongoing request is potentially notifiable or not.
sub able_from {
  my ($r, $from) = @_;
  test("able_from");
  
  my $res;

  if (!defined $from || $from eq "") {
    test("From was null or \"\"");
    return MBL_FALSE;
  }

  if (MBL_NOTIFY_REFLEXIVE == MBL_FALSE && is_it_me($r, $from)) {
    test("Reflexive notification sending is NOT potentially notifiable");
    return MBL_FALSE;
  }

  test("able_from return");
  return MBL_TRUE;
}

# @return Whether the ongoing request is nofitiable or not.
sub nf_txable {
  my ($r, $nf) = @_;
  test("nf_txable");

  my $res;

  if (able_from($r, $$nf{"from"}) == MBL_TRUE &&
      able_status($r, $$nf{"status"}) == MBL_TRUE &&
      able_to($r, $$nf{"to"}) == MBL_TRUE) {
    $res = MBL_TRUE
  } else {
    $res = MBL_FALSE;
  }

  test("res: $res");
  test("nf_txable return");
  return $res;
}

sub nfy_if_needed {
  my ($r, $n) = @_;
  test("nfy_if_needed");

  if (nf_txable($r, $n) == MBL_TRUE) {
    nf_tx($r, $n);
  }

  test("nfy_if_needed return");
}

sub handler {
  my $r = shift;
  test("logging --------------------------------");

  my $n = nf_pack($r);

  if (defined $n) {  
    nfy_if_needed($r, $n);
  }
  
  test("logging return");
  return Apache2::Const::OK;
}
1;
