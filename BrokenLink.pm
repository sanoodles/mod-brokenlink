=pod
This is going to be a Perl port of mod_brokenlink
http://code.google.com/p/modbrokenlink/
which is written in C.

Examples of mod_perl handlers:
http://perl.apache.org/docs/2.0/user/handlers/intro.html
http://modperlbook.org/code/chapters/ch25-next_generation/Book/Eliza2.pm
http://cpan-search.sourceforge.net/Apache2/DocServer.pm.html
https://svn.apache.org/repos/asf/spamassassin/branches/check_plugin/spamd-apache2/lib/Mail/SpamAssassin/Spamd/Apache2/Config.pm
http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlLogHandler

=cut

=pod
Contents:
1, Includes
2. Constants
3. Testing helpers
4. The meat
=cut



=pod
1. Includes
=cut
use POSIX qw/strftime/;



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


