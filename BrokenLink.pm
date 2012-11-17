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
  MBL_DEBUG_MODE => MBL_FALSE,
  DEBUG => MBL_DEBUG_MODE
}

# sending
use constant {
  MBL_NOTIFY_FILENAME => "/mod_brokenlink_notify",
  MBL_NOTIFY_REFLEXIVE => MBL_FALSE,
  MBL_USER_AGENT => "Apache mod_brokenlink"
}


