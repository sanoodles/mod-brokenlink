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

This file contains:
1, Includes
2. Constants
3. Testing helpers
4. The meat
=cut


