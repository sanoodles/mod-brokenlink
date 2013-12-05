=pod
This is going to be a Perl port of mod_brokenlink
http://code.google.com/p/modbrokenlink/
which is written in C.

It runs on top of mod_perl, whose API is:
http://perl.apache.org/docs/2.0/api/index.html

What is not provided by mod_perl API should be provided by 
Perl native or some CPAN module.

Technically, is a mod_perl handler.

The purpose of this software is helping to deal with the
increasing number of links to pages with errors, as shown
in the stats of
http://httparchive.org/trends.php?s=All&minlabel=Nov+15+2010&maxlabel=Dec+15+2012



=head2 Examples of mod_perl handlers

=head3 Basic
http://perl.apache.org/docs/2.0/user/handlers/intro.html
http://modperlbook.org/code/chapters/ch25-next_generation/Book/Eliza2.pm

=head3 With logging
http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlLogHandler
http://search.cpan.org/~stas/DocSet-0.19/examples/site/src/start/tips/logging.pod

=head3 Configuration manual
http://perl.apache.org/docs/2.0/user/config/custom.html#Creating_and_Using_Custom_Configuration_Directives

=head3 With configuration
https://www.google.com/search?q=metacpan+%22package+Apache2:%3A%22+get_config
http://cpan-search.sourceforge.net/Apache2/DocServer.pm.html

=head4 With configuration with arrays
https://svn.apache.org/repos/asf/spamassassin/branches/check_plugin/spamd-apache2/lib/Mail/SpamAssassin/Spamd/Apache2/AclIP.pm



This file contains:
1. Includes
2. Constants
3. Testing helpers
4. Configuration
5. The meat

TODO: test configuration merge.

=cut





package BrokenLink;





use strict;
use warnings;





=pod
1. Includes
=cut

use POSIX qw/strftime/;
use IO::Socket::INET;
use URI;
use URI::Escape;
use Apache2::CmdParms ();
use Apache2::Const -compile => qw(OK RSRC_CONF);
use Apache2::Directive ();
use Apache2::Module ();
use Apache2::RequestRec ();
use Apache2::ServerRec ();
use Apache2::ServerUtil ();
use APR::Const ();
use APR::Socket ();
use APR::Table ();





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
  MBL_DEBUG_MODE => MBL_FALSE
};

# notification sending
use constant {
  MBL_NOTIFY_FILENAME => "/mod_brokenlink_notify",
  MBL_NOTIFY_REFLEXIVE => MBL_FALSE,
  MBL_USER_AGENT => "Apache mod_brokenlink"
};





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
  test($$nf{time});
  test($$nf{from}->as_string);
  test($$nf{to}->as_string);
  test($$nf{status});
}

sub tabletest_row {
  my ($key, $value) = @_;
  test("$key: $value");
  return 1;
}

sub tabletest {
  test("tabletest");
  shift->do("tabletest_row");
}





=pod
4. Configuration
=cut

our $notifiable_statuses_default = [
  300,
  301,
  400,
  403,
  404,
  410,
  414,
  415,
  501,
  502,
  503,
  504,
  505,
];

# @see http://perl.apache.org/docs/2.0/user/config/custom.html#Directive_Scope_Definition_Constants
my @directives = (
  {
    name => "NotifiableStatus",
    # req_override => Apache2::Const::RSRC_CONF,
  },
);
Apache2::Module::add(__PACKAGE__, \@directives);

# @see perl.apache.org/docs/2.0/user/config/custom.html#C_args_how_
sub NotifiableStatus { 
  push_val('notifiable_statuses', @_);
}

# @return Module config.
sub config_get {
  my $r = shift;
  my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server);
  return $cfg;
}

# @see http://perl.apache.org/docs/2.0/user/config/custom.html#C_SERVER_CREATE_
sub SERVER_CREATE {
  test("SERVER_CREATE");
  my ($class, $parms) = @_;

  test("class: " . $class);

  return bless { notifiable_statuses => [] }, $class;
}

=pod
@see SERVER_MERGE, push_val, and merge are taken from
http://perl.apache.org/docs/2.0/user/config/custom.html#Examples
=cut
sub SERVER_MERGE { 
  test("SERVER_MERGE");

  merge(@_);
}

sub push_val {
  test("push_val ini");
  my ($key, $self, $parms, $arg) = @_; 

  test("key: " . $key . ", arg: " . $arg);

  push @{ $self->{$key} }, $arg;
  unless ($parms->path) {
      my $srv_cfg = Apache2::Module::get_config($self, $parms->server);
      push @{ $srv_cfg->{$key} }, $arg;
  }

  test("push_val end");
}

sub merge {
  test("merge ini");
  my ($base, $add) = @_;
  my %mrg = {};

  # code to merge %$base and %$add
  for my $key (keys %$base, keys %$add) {
    next if exists ($mrg{$key});
    if ($key eq 'notifiable_statuses') {
      push @{ $mrg{$key} },
          @{ $base->{$key} || [] }, @{ $add->{$key} || [] };
    }
  }


  test("merge end");
  return bless \%mrg, ref($base);
}





=pod
5. The meat
=cut

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
  test("nf_common_create ini");
  $$res{id} = $id;
  $$res{time} = defined $time ? $time : "";
  $$res{qtt} = $qtt;
  $$res{status} = $status;
  $$res{from} = defined $from ? $from : "";
  $$res{to} = defined $to ? $to : "";
  test("status: $status from: " . $from->as_string . " to: " . $to->as_string);
  test("nf_common_create end");
}

=pod
Creates a (dis)trusted notification object from raw data
=cut
sub nf_create {
  my ($id, $time, $qtt, $trust, $status, $from, $to) = @_;
  test("nf_create ini");
  my %res;
  $res{trust} = $trust;
  nf_common_create(\%res, $id, $time, $qtt, $status, $from, $to);
  test("nf_create end");
  return \%res;
}

=pod
Socket connection
@param sock output parameter. A new IO:Socket::INET socket to $hostname:$port.
@param hostname
@param port
@see http://www.thegeekstuff.com/2010/07/perl-tcp-udp-socket-programming/
=cut
sub socket_open {
  my ($r, $sock, $hostname, $port) = @_;
  test("socket_open ini");

  $| = 1;

  $_[1] = new IO::Socket::INET (
    PeerHost => $hostname,
    PeerPort => $port,
    Proto => 'tcp',
    # Timeout => DEF_SOCK_TIMEOUT
  ) or die "ERROR in Socket Creation : $!\n";

  test("socket_open end: " . MBL_TRUE);
  return MBL_TRUE;
}

=pod
Creates a notification object from the data of the current request
@param r Current request_rec
@return Notification object
=cut
sub nf_pack {
  my ($r) = @_;
  test("nf_pack ini");
  tabletest($r->headers_in);

  my $notification;

  my $time = "";

  my $referer = $r->headers_in->get("Referer");

  if (!defined $referer || $referer eq "") {
    test("Void referer. Can not pack notification.");
    return undef;
  }

  my $from = URI->new($referer);

# The Referer could be an absolute URI, but also a partial URI, or any thing.
# If the Referer header is a partial URI, it will have no protocol nor host.
# In such cases we assume that the protocol is "http" and the host 
#     is the Host header (a reflexive notification).
  if (!$from->can('host')) {
    $referer = "http://" . $r->headers_in->get("Host") . $referer;
    $from = URI->new($referer);
  }
  test("from: " . $from->as_string);

  my $to = URI->new($r->unparsed_uri);
  test("to: " . $to->as_string);

  my $status = $r->status;
  test("status: $status");

  $notification = nf_create(0, $time, 1, MBL_TRUE, $status, $from, $to);

  test("nf_pack end");
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
      "?from=" . urlencode($$nf{from}->as_string) . 
      "&status=" . $$nf{status} . 
      "&to=" . urlencode($$nf{to}->as_string);

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
  test("http_get_compose ini");

  my $res = "GET $uri HTTP/1.1" . CRLF_STR . 
            "Host: $host" . CRLF_STR . 
            "Referer: $referer" . CRLF_STR .
            "User-Agent: $user_agent" . CRLF_STR .
            CRLF_STR;

  test("http_get_compose end");
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
  test("nf_xraw2req ini");

  my $resource = nf_xraw2uri($nf);
  my $host = $$nf{from}->host;
  my $referer = $$nf{to}->as_string;
  my $user_agent = MBL_USER_AGENT;
  my $res = http_get_compose($resource, $host, $referer, $user_agent);

  test("nf_xraw2req end");
  return $res;
}

=pod
Transmits notification to referer
Test case: Access to http://localhost/a_non_existent_page.html
=cut
sub nf_tx {
  my ($r, $nf) = @_;
  test("nf_tx ini");

  my $socket;

  my $referer_hostname = $$nf{from}->host;
  test("referer_hostname: $referer_hostname");

  my $referer_port = $$nf{from}->port;
  test("referer_port:  $referer_port");

  if (socket_open($r, $socket, $referer_hostname, $referer_port) == MBL_FALSE) {
    test("nf_tx return with error at socket_open");
    return MBL_FALSE;
  }

  my $req_header = nf_xraw2req($nf);

  my $len = length $req_header;

  test("**** SENDING NOTIFICATION ****");
  my $ret = print $socket $req_header;
  test("socket->send returned: $ret");

  if (!$ret) {
    test("socket->send returned an error.");
    return MBL_FALSE;
  }

  $socket->close();

  test("nf_tx end: " . MBL_TRUE);
  return MBL_TRUE;
}

=pod
@param referer_uri {URI object} URI of the referer.
@return {MBL_BOOL} Whether the referer_uri belongs to the localhost.
The current design makes no distinction between:
* Servers under the same hostname.
* "localhost" and the current server.
* "127.0.0.1" and the current server.
=cut
sub is_it_me {
  my ($r, $referer_uri) = @_;
  test("is_it_me ini");

  my $res;

  if ($referer_uri->as_string eq "") {
    test("Subject host is \"\"");
    return MBL_FALSE;
  }

  my $localhostname = $r->server()->server_hostname();

  my $referer_hostname = $referer_uri->host;

  test("localhostname: $localhostname");
  test("referer_hostname: $referer_hostname");

  if (!defined $referer_hostname) {
    test("No referer explicited; assuming localhost.");
    return MBL_TRUE;
  }

  if ($localhostname eq $referer_hostname) {
    test("Referer host is localhost");
    return MBL_TRUE;
  }

  if ("localhost" eq $referer_hostname) {
    test("Referer host is localhost");
    return MBL_TRUE;
  }

  if ("127.0.0.1" eq $referer_hostname) {
    test("Referer host is localhost");
    return MBL_TRUE;
  }

  test("Referer host is NOT localhost");
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
  test("able_to ini");

  my $res;

  my $to_filename = substr $to, 0, length MBL_NOTIFY_FILENAME;

  if ($to_filename eq MBL_NOTIFY_FILENAME) {
    test("Sweet-dude dialog responsibly avoided.");
    $res = MBL_FALSE;
  } else {
    $res = MBL_TRUE;
  }

  test("able_to end: $res");
  return $res;
}

=pod
@return Whether the status of the ongoing request is potentially notifiable or not.
If there is not a user defined list of notifiable statuses
  It uses defaults
Else
  It uses the user list
=cut
sub able_status {
  my ($r, $status) = @_;
  test("able_status ini (status: $status)");

  my $res;
  my $cfg = config_get($r);
  my $t = $$cfg{notifiable_statuses} || [];
  test("scalar t: " . scalar @$t);

  if (scalar(@$t) == 0) {
    test("scalar t was zero");
 
    $t = $notifiable_statuses_default;;
 
    test("scalar t now: " . scalar @$t);
  }

  foreach my $elem (@$t) {
    test("elem: " . $elem);
  }

  if (grep /$status/, @$t) {
    $res = MBL_TRUE;
  } else {
    $res = MBL_FALSE;
  }

  test("able_status end: $res");
  return $res;
}

# @return Whether the referer of the ongoing request is potentially notifiable or not.
sub able_from {
  my ($r, $from) = @_;
  test("able_from ini");
  
  my $res;

  if (!defined $from || $from eq "") {
    test("From was null or \"\"");
    return MBL_FALSE;
  }

  if (MBL_NOTIFY_REFLEXIVE == MBL_FALSE && is_it_me($r, $from)) {
    test("Reflexive notification sending is NOT potentially notifiable");
    return MBL_FALSE;
  }

  test("able_from end: " . MBL_TRUE);
  return MBL_TRUE;
}

# @return Whether the ongoing request is nofitiable or not.
sub nf_txable {
  my ($r, $nf) = @_;
  test("nf_txable ini");

  my $res;

  if (able_from($r, $$nf{from}) == MBL_TRUE &&
      able_status($r, $$nf{status}) == MBL_TRUE &&
      able_to($r, $$nf{to}) == MBL_TRUE) {
    $res = MBL_TRUE
  } else {
    $res = MBL_FALSE;
  }

  test("nf_txable return: $res");
  return $res;
}

sub nfy_if_needed {
  my ($r, $n) = @_;
  test("nfy_if_needed ini");

  if (nf_txable($r, $n) == MBL_TRUE) {
    nf_tx($r, $n);
  }

  test("nfy_if_needed end");
}

sub handler {
  my $r = shift;
  test("handler --------------------------------");

  my $n = nf_pack($r);

  if (defined $n) {  
    nfy_if_needed($r, $n);
  }
  
  test("handler end ----------------");
  return Apache2::Const::OK;
}
1;
