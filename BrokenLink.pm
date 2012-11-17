=pod
This is going to be a Perl port of mod_brokenlink
http://code.google.com/p/modbrokenlink/
which is written in C.

It runs on top of mod_perl. Its API is:
http://perl.apache.org/docs/2.0/api/index.html

Examples of mod_perl handlers:
http://perl.apache.org/docs/2.0/user/handlers/intro.html
http://modperlbook.org/code/chapters/ch25-next_generation/Book/Eliza2.pm
http://cpan-search.sourceforge.net/Apache2/DocServer.pm.html
https://svn.apache.org/repos/asf/spamassassin/branches/check_plugin/spamd-apache2/lib/Mail/SpamAssassin/Spamd/Apache2/Config.pm
http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlLogHandler

File contents:
1, Includes
2. Constants
3. Testing helpers
4. The meat
=cut



=pod
1. Includes
=cut
use POSIX qw/strftime/;
use IO::Socket::INET;



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
}

# debugging
use constant {
  MBL_DEBUG_MODE => MBL_FALSE
}

# notification sending
use constant {
  MBL_NOTIFY_FILENAME => "/mod_brokenlink_notify",
  MBL_NOTIFY_REFLEXIVE => MBL_FALSE,
  MBL_USER_AGENT => "Apache mod_brokenlink"
}



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
    print STDERR, "mbltest " . now() . ": " . $string . "\n";
  }
}

# Prints the fields of a notification object to the STDERR.
sub nftest {
  my $nf = shift;
  test("nftest");
  test($nf{"time"});
  test($nf{"from"});
  test($nf{"to"});
  test($nf{"status"});
}

# Prints one row of an APR table to the STDERR.
sub tabletest_row {
  my ($rec, $key, $value) = @_;

  test("tabletest_row");
  test("key: " . $key);
  test("value: " . $value);

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

  $res{"id"} = $id;

  $res{"time"} = defined $time ? $time : "";
  
  $res{"qtt"} = $qtt;

  $res{"status"} = $status;

  $res{"from"} = defined $from ? $from : "";

  $res{"to"} = defined $to ? $to : "";

  test("status: " . $status . " from: " . $from . " to: " . $to);
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

  my %notification;
  my $can = MBL_TRUE;

  my $time = "";

  myi $from = $r->header_in{"Referer"};
  test("from: " . $from);
  if ($from == undef || $from eq "") {
    test("Void referer. Can not pack notification.");
    $can = MBL_FALSE;
  }

  my $to = $r->unparsed_uri;
  test("to: " . $to);

  my $status = $r->status;
  test("status: " . $status);

  if ($can == MBL_TRUE) {
    %notification = nf_create(0, $time, 1, MBL_TRUE, $status, $from, $to);
  }

  test("nf_pack return");
  return \%notification;
}


