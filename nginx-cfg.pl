#!/usr/bin/perl

=pod =======================================================

=head1 SYNOPSIS

MODULE NAME: er-nginx-admin 

DESCRIPTION: Utility to add and remove ER domains in Nginx

NOTES: 

AUTHOR: Troy Conrad, LBOX LLC. troy.conrad@lbox.com

=VERSIONS: See end for version history

=cut =======================================================

package LBOX::NginxCfg;

$SCRIPT_NAME = 'nginx-cfg';

$VERSION = '0.1.0';

use feature qw(switch unicode_strings);
use Cwd;
use Getopt::Std;
use Template;
#use Net::DNS;
use Term::ANSIColor qw(:constants);
#use Net::Ping;
#use Time::HiRes;
#use JSON::PP
#use strict 'vars';

binmode(STDOUT, ":utf8"); # suppresses UTF-related warnings

######### CONFIGURATION #########

my $cwd = getcwd;

######### MAIN PROGRAM #########

getopts('a:c:l:r:t:u:hnv:'); # -d(ebug level) argument

our($opt_a,$opt_c,$opt_l,$opt_n,$opt_r,$opt_v,$opt_h,$opt_t,$opt_u);

our $VERBOSITY = $opt_v ||= 1;

our($action,$comment,$vhost,$proxy_pass_url,$updateNginx);

our $comment = $opt_c;

$config_file = '/opt/nginx-cfg/config.pl';

-f $config_file or fail("Sorry, I can't find the required 'config.pl' file!\nPlease make sure it's at '$config_file'.");

require $config_file;

our $templateFile = $opt_t ||= 'default';
$templateFile .= '.tt2';

if ($opt_a)
{
	$vhost = $opt_a;
	if ($opt_u)
	{
		$proxy_pass_url = $opt_u;
	}
	else
	{
		#print "You must specify an upstream URL with -u when using the -a (add) option.\n";
		$opt_h = 1;
	}
}
elsif ($opt_l)
{
	$vhost = $opt_l;
}
elsif ($opt_r)
{
	$vhost = $opt_r;
}
else
{
	#print "You must specify -a (add), -l (list) or -r (remove).\n";
	$opt_h = 1;
}

if ($opt_h)
{
	print <<EOS;
$SCRIPT_NAME version $VERSION

Add, list and remove Nginx site configuration files.

Usage:

$SCRIPT_NAME [-a|-l|-r <site-name>] [-c comment] [-u <upstream-URL>] [-t <config-template>] [-h] [-n] [-v <1-4>]

Options:

  -a <site-name>          Add a configuration for the site named 'site-name'.
                          If the configuration already exists, update it.

  -c <comment>            Optional comment string to add to top of configuration file.

  -h                      Show this Help screen and exit.

  -l <site-name>          List the configuration file contents for the site named 'site-name'.
  
  -n                      Do Not update the running Nginx configuration after using -a or -r.

  -r <site-name>          Remove the configuration for the site named 'site-name'.

  -t <config-template>    Optional configuration Template (in '$templates_dir')
                          to use when adding/updating a site.
                          Default is the 'default' template.

  -u <upstream-URL>       The Upstream URL to proxy traffic to. Required when using the -a option.

  -v <0-4>                Specify the verbosity of console output, higher numbers are more verbose. Default is 1.

Examples:

- Add/update configuration for 'some.example.com', proxied to URL 'somehost',
  using the default template:

	$SCRIPT_NAME -a some.example.com -u http://somehost

- Add/update configuration for 'another.example.com', proxied to URL 'anotherhost' port 8080,
  using the 'ssl-redirect' template:

	$SCRIPT_NAME -a another.example.com -u http://anotherhost:8080 -t ssl-redirect

- List configuration for 'some.example.com':

	$SCRIPT_NAME -l some.example.com:

- Remove configuration file for 'another.example.com' but don't reload Nginx.

	$SCRIPT_NAME -r another.example.com -n
EOS

	exit;
}

&logger(1,"$SCRIPT_NAME version $VERSION started.");

if ($vhost)
{
	$vhost =~ m/\w+\.\w+/ || fail("'$vhost' is not a valid fully qualified domain name."); 
}
else
{
	fail("Please specifiy a fully qualified domain name (FQDN) to add/update or remove.");
}

if ($opt_a)
{
	&logger(1,"Adding site '$vhost'... ");
	&addDomain($vhost,$templateFile,$comment) || fail("Configuration failed.");
	&logger(2,GREEN . 'OK' . RESET);
	&updateNginx();
}
if ($opt_l)
{
	&logger(1,"Listing site '$vhost'... ");
	&listDomain($vhost) || fail("Query failed.");
	&logger(2,GREEN . 'OK' . RESET);
}

if ($opt_r)
{
	&logger(1,"Removing site '$vhost'... ");
	&removeDomain($vhost) || fail("Configuration failed.");
	&logger(2,GREEN . 'OK' . RESET);
	&updateNginx();
}

######### CORE FUNCTIONS #########

sub addDomain
{
	my $domain_name = shift;
	my $templateFile = shift;

	my $filename = $domain_name;
	$filename =~ tr'.'_';

	my $nginx_filename = "$filename.conf";

	my $t_config = {
		ABSOLUTE => 1,
		POST_CHOMP => 1	# cleanup whitespace
	};
	
	# create Template object
	my $template = Template->new($t_config);

	$comment ||= $domain_name;

	# define template variables for replacement
	my $t_vars = {
	    filename			=> $filename,
	    comment				=> $comment,
	    server_name			=> $domain_name,
	    proxy_pass_url		=> $proxy_pass_url,
	    common_config		=> $common_config
	 };
	
	my $destFile = "$nginx_sites_dir/$nginx_filename";

	if (-e $destFile)
	{
		unlink($destFile) || die "Could not delete '$destFile': $!\n";
	}

	$template->process("$templates_dir/$templateFile", $t_vars, $destFile)
		|| die $template->error(), "\n";
}

#

sub listDomain
{
	my $domain_name = shift;

	my $filename = $domain_name;
	$filename =~ tr'.'_';

	my $nginx_filename = "$nginx_sites_dir/$filename.conf";

	-f $nginx_filename or fail("Could not read '$nginx_filename'");

	print "Showing '$nginx_filename':\n\n" . `cat $nginx_filename`;
}

#

sub removeDomain
{
	my $domain_name = shift;

	my $filename = $domain_name;
	$filename =~ tr'.'_';

	my $nginx_filename = "$filename.conf";

	unlink("$nginx_sites_dir/$nginx_filename")
		|| die "Could not delete '$nginx_sites_dir/$nginx_filename': $!\n";
}

#

sub updateNginx
{

	return if $opt_n;
	&logger(1,"Verifying Nginx configuration...");
	my $testResult = `sudo nginx -t 2>&1`;
	chomp $testResult;
	if ($testResult =~ /test is successful/)
	{
		&logger(1,"Reloading Nginx...");
		`sudo service nginx reload`;
	}
	else
	{
		die "Sorry, there is an issue with the Nginx configuration:\n$testResult\nNginx was NOT reloaded.\n";
	}
}

######### SUPPORT FUNCTIONS #########

sub GREEN_CHAR	{ "\x{2705}" } # Unicode Green Checkbox
sub RED_CHAR	{ "\x{2757}" } # Unicode Red Exclamation

#

sub fail { die RED . shift . RESET . "\nExiting.\n"; }

#

sub logger
{
	my($level,$msg,$noNewLine) = @_;
	if ($VERBOSITY >= $level)
	{
		print '>' x ($level-1) , "\t" x ($level-1) , $msg;
		print "\n" unless $noNewLine;
	}
}

__END__