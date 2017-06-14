use 5.024;
use lib qw(/home/void/sms_watcher/extlib/lib/perl5);
use lib qw(/home/void/sms_watcher/extlib/lib/perl5/x86_64-linux);

no warnings 'experimental::signatures';
use feature 'signatures';

use utf8;
use Linux::Inotify2;
use Email::Simple;
use Net::SMTP;
use POSIX qw(strftime);
use File::Find;
use File::Basename;
use Encode;
use MIME::Base64;

use Data::Dumper;

use constant
{
	WATCH_FOLDER => "/home/void/sms_watcher/a",
	LOG_FILE => "log.txt",

	MAIL_FROM => '13611941185@v2mail.net',
	RCPT_TO => 'strangemk3@gmail.com',

	SMTP_DEBUG => 1,
	SMTP_TIMEOUT => 30,

	SMTP_SERVER => '127.0.0.1',
	SMTP_PORT => '465',
	SMTP_USER => '13611941185',
	SMTP_PASSWORD => 'wh@tEveR',
};

# Logger staff
sub get_current_time()
{
	strftime "%Y/%m/%d %H:%M:%S", localtime;
}

sub get_logger($filename)
{
	open (my $fh, ">>", $filename) or die "Open log file $filename error.";
	return sub
	{
		say {$fh} get_current_time() . " [log] $$: @_";
	}
}

# Misc staff
sub partial
{
	my $f = shift;
	my @args = @_;
	return sub
	{
		$f->(@args, @_);
	}
}

sub read_file($filename)
{
    local $/ = undef;
    open my $fh, "<", $filename or die "Could not open $filename: $!";
    <$fh> // '';
}

# Main staff
sub main
{
	my $logger = get_logger(LOG_FILE);
	$logger->("sms_watcher started.");

	my $inotify = Linux::Inotify2->new() or die "Unable to create new inotify object: $!" ;
	$inotify->watch (WATCH_FOLDER, IN_MODIFY|IN_MOVED_TO|IN_CREATE) or die "Watch creation failed" ;

	my $sms_mail_f = partial(\&send_sms_mail, get_smtp_info());
	my $sms_watcher = partial(\&check_sms, $sms_mail_f, WATCH_FOLDER);

	while (1)
	{
		my $timestamp = time();
		my @events = $inotify->read();
		die "read error: $!" if (@events == 0);
		$sms_watcher->($timestamp);
	}

	$logger->("sms_watcher ended.");
}

sub sms_file_to_subject($sms_file)
{
	basename($sms_file);
}

sub sms_file_to_email($sms_file)
{
	my $email = Email::Simple->create(
		header =>
		[
			From    => MAIL_FROM,
			To      => RCPT_TO,
			Subject => sms_file_to_subject($sms_file),
			'Content-type' => 'text/plain; charset=UTF-8',
			'Content-Transfer-Encoding' => 'base64',
		],
		body => encode_base64(read_file($sms_file)),
	);
	$email->as_string();
}

sub check_sms($send_mail_f, $sms_folder, $timestamp)
{
	my $wanted = sub
	{
		my $n = $File::Find::name;
		$send_mail_f->(sms_file_to_email($n)) if (-f $n and (stat($n))[9] > $timestamp);
	};

	find($wanted, $sms_folder);
}

sub send_sms_mail($smtp_info, $sms_data)
{
	say Dumper($smtp_info);
	say Dumper($sms_data);
	return;

	my $smtp = Net::SMTP->new($smtp_info->{host},
		Port => $smtp_info->{port},
		SSL     => 1,
		Timeout => SMTP_TIMEOUT,
		Debug   => SMTP_DEBUG,
	);
	$smtp->auth($smtp_info->{user}, $smtp_info->{password});
	$smtp->mail(MAIL_FROM);
    $smtp->to(RCPT_TO);
    $smtp->data();
    $smtp->datasend($sms_data);
    $smtp->dataend();
	$smtp->quit();
}

sub get_smtp_info()
{
	{ ip => SMTP_SERVER, port => SMTP_PORT, user => SMTP_USER, password => SMTP_PASSWORD };
}

main();
