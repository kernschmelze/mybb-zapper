#!/usr/bin/env perl
#
# MyBB Zapper v 0.01 [first alpha release]
# a script to assist reconfiguration and cloning of MyBB installations
#
# (c) 2016 kernschmelze
# License: GPL 3
#
# Notes:
# Support for other databases than MySQL can be added on request.
# Written and tested using FreeBSD and MySQL.
# Should need no changes to run on Linux.
# Might run on 64-bit Windows also. Will need modifications to run on Win32.

use strict;
use warnings;
use utf8;
use POSIX;
use Getopt::Long;

my $version = '0.01 alpha';
my $MYBB_DIR = '';
my $BKUP_DIR = '';
my $simulate = 0;
my $verbose = '';

# default runtime constants
my $sqlpwfile = '';
my $sqlbatchfile = '';
my $dbbackupf = '/mybb_backup_db_';
my $phpbackupf = '.backup_';
my $config_php = '';
my $config_php_file = 'config.php';
my $settings_php_file = 'settings.php';
my $ftimestr = strftime("%Y-%m-%d-%H-%M-%S", localtime(time));

# keep it simple and easy to understand, so use a bunch 
# of global vars instead of a hash
my $mybb_conf_type;
my $mybb_conf_database;     my $mybb_newconf_database;
my $mybb_conf_dbprefix;     my $mybb_newconf_dbprefix;
my $mybb_conf_hostname;     my $mybb_newconf_hostname;
my $mybb_conf_username;     my $mybb_newconf_username;
my $mybb_conf_password;     my $mybb_newconf_password;
my $mybb_conf_admin_name;   my $mybb_newconf_admin_name;
my $mybb_conf_admin_dir;    my $mybb_newconf_admin_dir;
my $mybb_conf_super_admins; my $mybb_newconf_super_admins;
my $mybb_conf_encoding;
my $mybb_conf_secret_pin;   my $mybb_newconf_secret_pin;
my $mybb_conf_bburl;        my $mybb_newconf_bburl;
my $mybb_conf_cookiedomain; my $mybb_newconf_cookiedomain;
my $mybb_conf_homeurl;      my $mybb_newconf_homeurl;


GetOptions(
     "mybb_dir|d:s"       => \$MYBB_DIR,
     "backup_dir|b:s"     => \$BKUP_DIR,
     "simulate|s"         => \$simulate,
     "help|h|?"           => \&show_help,
     "version|V"          => \&show_version,
     "verbose"            => \$verbose
);

sub show_version
{
  print "$version\n";
  exit 0;
}

# string read_a_file( string filename)
sub read_a_file
{
  my $fn = shift;
  local $/ = undef;
  open FILE, $fn or die "Couldn't open file '$fn': Error $^E\n";
  my $text = <FILE>;
  close FILE or die "Couldn't close file '$fn': Error $^E\n";
  return $text;
}

# void write_a_file( string filename, string text)
sub write_a_file
{
  my $fn = shift;
  my $tx = shift;
  open my $file, '>', $fn or die "Couldn't open file '$fn' for writing: Error $^E\n";
  print $file $tx or die "Couldn't write file '$fn': Error $^E\n";
  close $file or die "Couldn't close file '$fn': Error : $^E";
}

sub make_sqlpassword_file
{
  $sqlpwfile = rndStr( 12, 'A'..'Z', 'a'..'z', '1'..'9');
  print "Making SQL password file '$sqlpwfile'.\n" if $verbose;
  my $pwf = "[client]\npassword=\"$mybb_conf_password\"\n";
  write_a_file( $sqlpwfile, $pwf);
}

sub remove_sqlpassword_file
{
  print "Removing SQL password file '$sqlpwfile'.\n" if $verbose;
  unlink( $sqlpwfile) or die "Could not delete SQL password file $sqlpwfile! Delete it PLEASE!. Exiting!\n";
}

# string do_sql_query( string query, string database)
sub do_sql_query
{
  my $qu = shift;
  my $db = shift;
  $sqlbatchfile = rndStr( 12, 'A'..'Z', 'a'..'z', '1'..'9');;
  print "Creating SQL batch file: $sqlbatchfile\n" if $verbose;
  write_a_file( $sqlbatchfile, $qu);
  make_sqlpassword_file;
  my $qstr = "mysql --defaults-extra-file='$sqlpwfile' --user=$mybb_conf_username --execute='source $sqlbatchfile' $db";
  print "Executing SQL query:\n$qstr\n" if $verbose;
  my $qansw = qx{ $qstr };
  my $qerr = $?;
  remove_sqlpassword_file;
  print "Deleting SQL batch file: $sqlbatchfile\n" if $verbose;
  unlink( $sqlbatchfile) or die "Could not delete SQL batch file $sqlbatchfile! Delete it PLEASE!. Exiting!\n";
  die "Error return '$qerr' from mysql!\n" if $qerr;
  return $qansw;
}

sub read_mbybb_config
{
  $config_php = read_a_file( $MYBB_DIR . '/inc/' . $config_php_file);
  ($mybb_conf_type)         = $config_php =~ /\$\Qconfig['database']['type'] = '\E(\S+)\Q';\E/s;
  die "Oups! This is a $mybb_conf_type database. I only speak mysqli! Exiting.\n" if ($mybb_conf_type ne 'mysqli');
  ($mybb_conf_database)     = $config_php =~ /\$\Qconfig['database']['database'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_dbprefix)     = $config_php =~ /\$\Qconfig['database']['table_prefix'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_hostname)     = $config_php =~ /\$\Qconfig['database']['hostname'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_username)     = $config_php =~ /\$\Qconfig['database']['username'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_password)     = $config_php =~ /\$\Qconfig['database']['password'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_admin_dir)    = $config_php =~ /\$\Qconfig['admin_dir'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_super_admins) = $config_php =~ /\$\Qconfig['super_admins'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_encoding)     = $config_php =~ /\$\Qconfig['database']['encoding'] = '\E(\S+)\Q';\E/s;
  ($mybb_conf_secret_pin)   = $config_php =~ /\$\Qconfig['secret_pin'] = '\E(\S+)\Q';\E/s;
  my $tl                    = do_sql_query( 'SELECT value from '.$mybb_conf_dbprefix."settings where name='bburl';", $mybb_conf_database);
  ($mybb_conf_bburl)        = $tl =~ /^(http\S+?)$/m;
  $tl                       = do_sql_query( 'SELECT value from '.$mybb_conf_dbprefix."settings where name='cookiedomain';", $mybb_conf_database);
  ($mybb_conf_cookiedomain) = $tl =~ /^(\.\S+?)$/m;
  $tl                       = do_sql_query( 'SELECT value from '.$mybb_conf_dbprefix."settings where name='homeurl';", $mybb_conf_database);
  ($mybb_conf_homeurl)      = $tl =~ /^(http\S+?)$/m;
  $tl                       = do_sql_query( 'SELECT username from '.$mybb_conf_dbprefix."users where uid='1';", $mybb_conf_database);
  ($mybb_conf_admin_name)   = $tl =~ /^(?!username)(\S+?)$/m;
}

sub print_mbybb_config
{
  print "MySQL hostname:       '$mybb_conf_hostname'\n";
  print "MySQL database name:  '$mybb_conf_database'\n";
  print "MySQL database type:  '$mybb_conf_type'\n";
  print "MySQL database prefix:'$mybb_conf_dbprefix'\n";
  print "MySQL username:       '$mybb_conf_username'\n";
  print "MySQL password:       '$mybb_conf_password'\n";
  print "MyBB board URL:       '$mybb_conf_bburl'\n";
  print "MyBB cookie domain:   '$mybb_conf_cookiedomain'\n";
  print "MyBB home URL:        '$mybb_conf_homeurl'\n";
  print "MyBB admin name:      '$mybb_conf_admin_name'\n";
  print "MyBB admin dir:       '$mybb_conf_admin_dir'\n";
  print "MyBB super admins:    '$mybb_conf_super_admins'\n";
  print "MyBB secret PIN:      '$mybb_conf_secret_pin'\n";
  print "MyBB encoding:        '$mybb_conf_encoding'\n";
}

sub print_mbybb_config_mod
{
  my $ts = ($mybb_conf_hostname eq $mybb_newconf_hostname) ? "[unchanged]" : "--> '$mybb_newconf_hostname'";
  print "MyBB hostname:       '$mybb_conf_hostname' $ts\n";
  $ts = ($mybb_conf_database eq $mybb_newconf_database) ? "[unchanged]" : "--> '$mybb_newconf_database'";
  print "MyBB database name:   '$mybb_conf_database' $ts\n";
  $ts = ($mybb_conf_dbprefix eq $mybb_newconf_dbprefix) ? "[unchanged]" : "--> '$mybb_newconf_dbprefix'";
  print "MyBB database prefix:'$mybb_conf_dbprefix' $ts\n";
  $ts = ($mybb_conf_password eq $mybb_newconf_password) ? "[unchanged]" : "--> '$mybb_newconf_password'";
  print "MyBB password:       '$mybb_conf_password' $ts\n";
  $ts = ($mybb_conf_bburl eq $mybb_newconf_bburl) ? "[unchanged]" : "--> '$mybb_newconf_bburl'";
  print "MyBB board URL:      '$mybb_conf_bburl' $ts\n";
  $ts = ($mybb_conf_cookiedomain eq $mybb_newconf_cookiedomain) ? "[unchanged]" : "--> '$mybb_newconf_cookiedomain'";
  print "MyBB cookie domain:  '$mybb_conf_cookiedomain' $ts\n";
  $ts = ($mybb_conf_homeurl eq $mybb_newconf_homeurl) ? "[unchanged]" : "--> '$mybb_newconf_homeurl'";
  print "MyBB home URL:       '$mybb_conf_homeurl' $ts\n";
  $ts = ($mybb_conf_admin_name eq $mybb_newconf_admin_name) ? "[unchanged]" : "--> '$mybb_newconf_admin_name'";
  print "MyBB admin name:     '$mybb_conf_admin_name' $ts\n";
  $ts = ($mybb_conf_admin_dir eq $mybb_newconf_admin_dir) ? "[unchanged]" : "--> '$mybb_newconf_admin_dir'";
  print "MyBB admin dir:      '$mybb_conf_admin_dir' $ts\n";
  $ts = ($mybb_conf_super_admins eq $mybb_newconf_super_admins) ? "[unchanged]" : "--> '$mybb_newconf_super_admins'";
  print "MyBB super admins:   '$mybb_conf_super_admins' $ts\n";
  $ts = ($mybb_conf_secret_pin eq $mybb_newconf_secret_pin) ? "[unchanged]" : "--> '$mybb_newconf_secret_pin'";
  print "MyBB secret PIN:     '$mybb_conf_secret_pin' $ts\n";
}

# void make_mybb_db_backup
sub make_mybb_db_backup
{
  make_sqlpassword_file;
  my $cmd = "mysqldump --defaults-extra-file=$sqlpwfile -h $mybb_conf_hostname -u $mybb_conf_username --add-drop-database --add-drop-table --routines $mybb_conf_database";
  my $dbbackupfile = $BKUP_DIR . $dbbackupf . $ftimestr;
  print "Creating backup file $dbbackupfile using the command:\n<$cmd>\n Please wait...\n";
  my $dbbkup;
  my $qerr;
  if (!$simulate) {
    $dbbkup = qx{ $cmd };
    $qerr = $?;
  }
  remove_sqlpassword_file;
  if (!$simulate) {
    die "Error return '$qerr' from mysqldump!\n" if $qerr;
    write_a_file( $dbbackupfile, $dbbkup);
  }
  print "Finished creating database backup.\n";
}  

# string sub askvalue (string itemname, string oldvalue, string sanityregexp, string repeatmsg)
sub askvalue
{
  my $itemname = shift;
  my $oldvalue = shift;
  my $sanityregexp = shift;
  my $repeatmsg = shift;

  print "The old $itemname is <$oldvalue>.\nEnter a new $itemname: ";
  my $ts;
  for (my $sane = 0; !$sane ;) {
    $ts = <STDIN>; chomp $ts;
    $sane = !( $ts =~ /{$sanityregexp}/ );
    print $repeatmsg if !$sane;
  }
  return ($ts =~ /^\S+$/) ? $ts : $oldvalue;
}

sub askuserinput
{
  print "\nNow the script will show you the current configuration values one-by-one\n" .
      "and ask you for the values you want to change them to. To leave a value\n" .
      "unchanged, just hit 'Enter'. After all configuration values have been changed,\n" .
      "you will be shown the changes and asked for confirmation to convert the\n" .
      "database to the new values. Only then permanent changes will be made.\n";
  my $defrepeatmsg = "Please use only letters, numbers and - or _ characters! Enter again: \n";
  my $numsrepeatmsg = "Please use only numbers, separated by whitespace! Enter again: \n";
  my $htmrepeatmsg = "Please use only letters, numbers,-,_,. and / characters! Enter again: \n";
  $mybb_newconf_hostname    = askvalue( 'hostname', $mybb_conf_hostname, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_database    = askvalue( 'database name', $mybb_conf_database, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_password    = askvalue( 'database password', $mybb_conf_password, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_dbprefix    = askvalue( 'database prefix', $mybb_conf_dbprefix, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_username    = askvalue( 'database username', $mybb_conf_username, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_super_admins= askvalue( 'super admin(s)', $mybb_conf_super_admins, '[^\d\s]', $numsrepeatmsg);
  $mybb_newconf_admin_name  = askvalue( 'admin name', $mybb_conf_admin_name, '[^\w\d\/]', $defrepeatmsg);
  $mybb_newconf_admin_dir   = askvalue( 'admin directory', $mybb_conf_admin_dir, '[^\w\d\/]', $defrepeatmsg);
  $mybb_newconf_secret_pin  = askvalue( 'Secret PIN', $mybb_conf_secret_pin, '[^\w\d]', $defrepeatmsg);
  $mybb_newconf_bburl       = askvalue( 'BB URL', $mybb_conf_bburl, '[^\w\d\/\\:]', $htmrepeatmsg);

  $mybb_newconf_bburl =~ s/^(http[s]?:\/\/[^\/]*)[\/]?/$1/;
  my ($httph, $turl) = $mybb_newconf_bburl =~ /^(http[s]?:\/\/)([^\/]*)/;
  $mybb_newconf_cookiedomain  = '.' . $turl;
  $mybb_newconf_homeurl       = $httph . $turl . '/index.php';
}

# int sub yesno
sub yesno
{
  print '[yN] ';
  my $ts = <STDIN>; chomp $ts;
  return $ts =~ /^[yY]/;
}

# zaps original mybb database
sub mybbdb_zap
{
  my $mcmd .= "DELETE FROM mybb_users WHERE uid!='1';\n" .
              "DELETE FROM mybb_adminoptions WHERE uid!='1';\n" .
              "UPDATE mybb_forums SET threads='0' WHERE threads!='0';\n" .
              "UPDATE mybb_forums SET posts='0' WHERE posts!='0';\n" .
              "UPDATE mybb_forums SET lastpost='0' WHERE lastpost!='0';\n" .
              "UPDATE mybb_forums SET unapprovedposts='0' WHERE unapprovedposts!='0';\n" .
              "UPDATE mybb_forums SET unapprovedthreads='0' WHERE unapprovedthreads!='0';\n" .
              "UPDATE mybb_forums SET lastpostsubject='' WHERE lastpost!='0';\n" .
              "UPDATE mybb_forums SET lastposter='' WHERE lastpost!='0';\n" .
              "UPDATE mybb_forums SET lastposteruid='0' WHERE lastpost!='0';\n" .
              "UPDATE mybb_forums SET lastposttid='0' WHERE lastpost!='0';\n";
  $mcmd =~ s/mybb_/$mybb_conf_dbprefix/gm;

  my @mybb_tblnames = qw( adminlog adminviews attachments announcements awaitingactivation 
          banned buddyrequests calendars delayedmoderation events forumsread forumsubscriptions 
          groupleaders joinrequests mailerrors maillogs mailqueue massemails moderatorlog 
          moderators pollvotes posts polls privatemessages promotionlogs promotions 
          questionsessions reportedcontent reputation searchlog sessions stats tasklog 
          threads threadsread threadratings threadviews threadsubscriptions userfields
          warnings );
  foreach (@mybb_tblnames) {
    $mcmd .= "TRUNCATE $mybb_conf_dbprefix$_;\n";
  }
  # banfilters - maybe an option to keep some or all of them could be useful?
  $mcmd .= 'TRUNCATE ' . $mybb_conf_dbprefix . "banfilters;\n";
  
  print "Zapping the database... please wait.\n";
  print "This is the command batch executed to MySQL to zap the DB:\n$mcmd\n" if ($verbose);
  do_sql_query( $mcmd, $mybb_conf_database) if (!$simulate);
}

# string rndStr( int length, array fromchars [, array fromchars2 ...])
sub rndStr
{
  join '', @_[ map{ rand @_ } 1 .. shift ]
}

# void sub backup_and_write_a_file( string filename, string text, string path)
sub backup_and_write_a_file
{
  my $fn = shift;
  my $tx = shift;
  my $pa = shift;
  my $fnbk = shift;
  my $txbk = read_a_file( $pa . $fn);
    my $dbbackupfile = $BKUP_DIR . $dbbackupf . $ftimestr;

  write_a_file( $BKUP_DIR . '/' . $fn . $phpbackupf . $ftimestr, $txbk);
  write_a_file( $pa . $fn, $tx);
}

sub show_help
{
  print <<END_HELP;
Project "MyBB Zapper"
A perl script which assists you with cloning and zapping
existing MyBB installations.

Usage: $0 [OPTIONS]
Options:
  -h, --help                show this help and exit
  -V, --version             show version and exit
  -d DIR, --mybb_dir DIR    root directory of the MyBB installation
  -b DIR, --backup_dir      directory to place backups in
  -s, --simulate            Simulate: do not do change config
  --verbose                 display the actual commands being executed
END_HELP
  print '<Enter> for more...'; <STDIN>; print "\n";
  print <<END_HELP;
Examples:

  # $0 -d webroot
    shows the current configuration of the MyBB installation which is 
    in sub directory 'webroot' of the current directory.

  # $0 -d webroot -b mybbbackups
    Does a full run, backup the original files in the 'mybbbackups' sub 
    directory of the current directory. The backup directory specified,
    in this case 'mybbbackups', must exist and be writable.

  # $0 -d webroot -b . -s --verbose
    Simulation run, lets you enter.change a configuration and see the SQL
    commands that would be run when not simulating, without actually
    making changes to the database or configuration files.
    
ATTENTION:
1.This script should never be placed in any web-accessible script-enabled 
  directory because its' abuse can be very damaging. To protect you, 
  it will attempt to delete itself if it detects being run from inside those.
2.The web server should be not be running while using this script.
  Because, if pages are serviced while the conversions run, this 
  might result in errors and possibly an inconsistent database .
END_HELP
  exit 0;
}


############################################################################
# main section
############################################################################

# this check is very cursory and could be improved
if ((-e 'index.php' && -e 'showthread.php' && -d 'inc') or
    (-d 'plugins' && -d 'languages' && -d 'class_parser.php'))
{
  print "Error: Please NEVER have this script in web-accessible directories!\n" .
        "This is VERY dangerous! Self-destructing to avoid security risks.\n";
#      "Move it outside of the publicly accessible web space NOW before continuing!\n";
  # maybe ask the user about self-deletion of the script?
  unlink $0;
  exit (0);
}

die "Error: Specify a valid MyBB directory using the -d option, please.\n" if (!length($MYBB_DIR));
die "Error: Invalid MyBB directory specified.\n" if (not -e $MYBB_DIR || not -d $MYBB_DIR);
die "Error: Invalid backup directory.\n" if (length($BKUP_DIR) && (not -e $BKUP_DIR || not -d $BKUP_DIR));
die "Error: backup directory not writable for me.\n" if (length($BKUP_DIR) && not -w $BKUP_DIR);

print "NOTICE: You have set the simulate option. No permanent changes will be made!\n";

read_mbybb_config;
print_mbybb_config;

die "This MyBB installation is not encoded in UTF8.\nNo other charsets supported by this script yet. Exiting.\n"
  if ($mybb_conf_encoding ne 'utf8');
die "This script only talks mysqli.\nBut this MyBB installation uses $mybb_conf_type. Exiting.\n"
  if ($mybb_conf_type ne 'mysqli');
if (!length($BKUP_DIR)) {
  print "Usage notice: To modify the settings, you must also use the -b backup option!\n";
  exit (0);
}
print 'As next step you can (optionally) change the configuration. Continue ? ';
exit (0) if (!yesno());

askuserinput;

print "\nThis is the summary of the changes you entered:\n";
print_mbybb_config_mod;
print 'Do you accept these changes? ';
if (!yesno()) {
  print "You rejected the changes. Exiting.\n";
  exit (0);
}

print "\nNow the database and configuration files will be backed up and then modified\n" .
      "so they match the changes you specified. Continue? ";
exit (0) if (!yesno());
make_mybb_db_backup;

if (($mybb_conf_database ne $mybb_newconf_database) or
    ($mybb_conf_dbprefix ne $mybb_newconf_dbprefix) or
    ($mybb_conf_hostname ne $mybb_newconf_hostname) or
    ($mybb_conf_username ne $mybb_newconf_username) or
    ($mybb_conf_password ne $mybb_newconf_password) or
    ($mybb_conf_admin_dir ne $mybb_newconf_admin_dir) or
    ($mybb_conf_super_admins ne $mybb_newconf_super_admins) or
    ($mybb_conf_secret_pin ne $mybb_newconf_secret_pin)) {
#  print "Backing up config.php\n" if ($verbose);
  print "Backing up config.php.\n";
  if (!$simulate) {
    $config_php =~ s/(\$\Qconfig['database']['database'] = '\E)($mybb_conf_database)(\Q';\E)/$1$mybb_newconf_database$3/s;
    $config_php =~ s/(\$\Qconfig['database']['table_prefix'] = '\E)($mybb_conf_dbprefix)(\Q';\E)/$1$mybb_newconf_dbprefix$3/s;
    $config_php =~ s/(\$\Qconfig['database']['hostname'] = '\E)($mybb_conf_hostname)(\Q';\E)/$1$mybb_newconf_hostname$3/s;
    $config_php =~ s/(\$\Qconfig['database']['username'] = '\E)($mybb_conf_username)(\Q';\E)/$1$mybb_newconf_username$3/s;
    $config_php =~ s/(\$\Qconfig['database']['password'] = '\E)($mybb_conf_password)(\Q';\E)/$1$mybb_newconf_password$3/s;
    $config_php =~ s/(\$\Qconfig['admin_dir'] = '\E)($mybb_conf_admin_dir)(\Q';\E)/$1$mybb_newconf_admin_dir$3/s;
    $config_php =~ s/(\$\Qconfig['super_admins'] = '\E)($mybb_conf_super_admins)(\Q';\E)/$1$mybb_newconf_super_admins$3/s;
    $config_php =~ s/(\$\Qconfig['secret_pin'] = '\E)($mybb_conf_secret_pin)(\Q';\E)/$1$mybb_newconf_secret_pin$3/s;
    backup_and_write_a_file( $config_php_file, $config_php, $MYBB_DIR . '/inc/');
} }

if ($mybb_conf_bburl ne $mybb_newconf_bburl) {
#  print "Backing up settings.php\n" if ($verbose);
  print "Backing up settings.php.\n";
  if (!$simulate) {
    my $settings_php = read_a_file( $MYBB_DIR . '/inc/' . $settings_php_file);
    $settings_php =~ s/(\$\Qsettings['bburl'] = '\E)($mybb_conf_bburl)[\/]?';/$1$mybb_newconf_bburl;/s;
    $settings_php =~ s/(\$\Qsettings['cookiedomain'] = '\E)($mybb_conf_cookiedomain)(\Q';\E)/$1$mybb_newconf_cookiedomain$3/s;
    $settings_php =~ s/(\$\Qsettings['homeurl'] = '\E)($mybb_conf_homeurl)(\Q';\E)/$1$mybb_newconf_homeurl$3/s;
    backup_and_write_a_file( $settings_php_file, $settings_php, $MYBB_DIR . '/inc/');
} }

# rename admin dir if user chose so
if ($mybb_conf_admin_dir ne $mybb_newconf_admin_dir) {
  print "Renaming $mybb_conf_admin_dir to $mybb_newconf_admin_dir.\n" if $verbose;
  rename $MYBB_DIR . '/' . $mybb_conf_admin_dir, $MYBB_DIR . '/' . $mybb_newconf_admin_dir if !$simulate;
}

print "\nNow you have the option to zap the database from all threads, posts, users\n" .
      "(leaving only the admin user) etc. So that you get an exact fresh clone of\n" .
      "your board with all configuration things kept from the original one.\n" .
      "Do you want to zap the database? ";
mybbdb_zap if yesno();

# check whether we need to create/rename/delete database
if ($mybb_newconf_database ne $mybb_conf_database || $mybb_newconf_dbprefix ne $mybb_conf_dbprefix ) {
  # if I had been intelligent I would have installed MariaDB, Percona or some other good DB.
  # I didn't know about the peculiarities of MySQL. For MySQL there is no way to rename tables 
  # without creating a new database. This means, if we want just to change the MyBB prefix
  # then we need to create+copy the database twice...
  # With MariaDB or Percona we could just rename the db and the tables without such brainless tort...
  my $copytwice = ($mybb_newconf_database eq $mybb_conf_database);
  print "It's MySQL, so we must copy the whole DB TWICE!\n" if $copytwice;
  print "Copying DB. Please wait...\n";
  
  my $mysqlsux = 'Mysqlsux_' . rndStr( 7, 'A'..'Z', 'a'..'z', '1'..'9');
  my $targetdbname = ($copytwice) ? $mysqlsux : $mybb_newconf_database;
  my $srcdbname = $mybb_conf_database;
  
  # get a list of the tables from mysql
  make_sqlpassword_file;
  my $cmd = "mysql --defaults-extra-file=$sqlpwfile -h $mybb_conf_hostname -u $mybb_conf_username $srcdbname -sNe 'show tables'";
  my $fldlist = qx{ $cmd };
  my $qerr = $?;
  remove_sqlpassword_file;
  die "Error return '$qerr' from mysql!\n" if $qerr;

  my $cmdlist = $fldlist;
  $cmdlist =~ s/^$mybb_conf_dbprefix(.*?)$/RENAME TABLE $srcdbname.$mybb_conf_dbprefix$1 TO $targetdbname.$mybb_newconf_dbprefix$1;/gm;
  $cmdlist = "USE $srcdbname;\nCREATE DATABASE $targetdbname;\nUSE $targetdbname;\n" . $cmdlist . "DROP DATABASE $srcdbname;\n";
  
  print "Command for renaming :\n$cmdlist\n" if $verbose;
  do_sql_query( $cmdlist, $srcdbname) if (!$simulate);
  if ($copytwice) {
    # now prepare copyback...
    $targetdbname = $mybb_newconf_database;
    $srcdbname = $mysqlsux;
    $cmdlist = $fldlist;
    $cmdlist =~ s/^$mybb_conf_dbprefix(.*?)$/RENAME TABLE $srcdbname.$mybb_newconf_dbprefix$1 TO $targetdbname.$mybb_newconf_dbprefix$1;/gm;
    $cmdlist = "USE $srcdbname;\nCREATE DATABASE $targetdbname;\nUSE $targetdbname;\n" . $cmdlist . "DROP DATABASE $srcdbname;\n";
    print "Copying DB back. Please wait...\n";
    print "Command for copying back:\n$cmdlist\n" if $verbose;
    do_sql_query( $cmdlist, $srcdbname) if (!$simulate);
} }

# Now apply the changes in the database
my $cmd = '';
if ($mybb_conf_password ne $mybb_newconf_password) {
  $cmd .= "SET PASSWORD FOR '$mybb_conf_username'\@'$mybb_conf_hostname' = PASSWORD('$mybb_newconf_password');\n";
}
if ($mybb_conf_username ne $mybb_newconf_username || $mybb_conf_hostname ne $mybb_newconf_hostname) {
  $cmd .= "RENAME USER '$mybb_conf_username'\@'$mybb_conf_hostname' TO '$mybb_newconf_username'\@'$mybb_newconf_hostname';\n";
}
$cmd .= "USE $mybb_newconf_database;\n";
if ($mybb_conf_admin_name ne $mybb_newconf_admin_name) {
  $cmd .= 'UPDATE ' . $mybb_newconf_dbprefix . "users SET username='$mybb_newconf_admin_name' WHERE uid='1';\n";
}
if ($mybb_conf_admin_name ne $mybb_newconf_admin_name) {
  $cmd .= 'UPDATE ' . $mybb_newconf_dbprefix . "users SET username='$mybb_newconf_admin_name' WHERE uid='1';\n";
}
if ($mybb_newconf_bburl ne $mybb_conf_bburl) {
  $cmd .= 'UPDATE ' . $mybb_newconf_dbprefix . "settings SET value='$mybb_newconf_bburl' WHERE name='bburl';\n";
  $cmd .= 'UPDATE ' . $mybb_newconf_dbprefix . "settings SET value='$mybb_newconf_cookiedomain' WHERE name='cookiedomain';\n";
  $cmd .= 'UPDATE ' . $mybb_newconf_dbprefix . "settings SET value='$mybb_newconf_homeurl' WHERE name='homeurl';\n";
}
if (length($cmd)) {
  print "Executing SQL query:\n$cmd" if ($verbose);
  do_sql_query( $cmd, $mybb_newconf_database) if (!$simulate);
}


print "$0: Finished.\n";
