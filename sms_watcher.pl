use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

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
use Email::MessageID;
use Config::Simple;

use Data::Dumper;

# Logger staff
sub get_current_time()
{
	strftime "%Y/%m/%d %H:%M:%S", localtime;
}

sub get_logger($filename)
{
	open (my $fh, ">>", $filename) or die "Open log file $filename error.";
	$fh->autoflush();
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

sub domain_name($s)
{
	$s =~ s/.*@//;
	$s;
}

# Main staff
sub main
{
	my $cfg = Config::Simple->new('sms_watcher.ini') or die Config::Simple->error();
	my $logger = get_logger($cfg->param('COMMON.LOG_FILE'));
	$logger->("sms_watcher started.");

	my $inotify = Linux::Inotify2->new() or die "Unable to create new inotify object: $!" ;
	$inotify->watch ($cfg->param('COMMON.WATCH_FOLDER'), IN_MODIFY|IN_MOVED_TO|IN_CREATE) or die "Watch creation failed" ;

	my $sms_mail_f = partial(\&send_sms_mail, $cfg, $logger);
	my $convert_mail_f = partial(\&sms_file_to_email,
		$cfg->param('MAIL.FROM'),
		$cfg->param('MAIL.TO'),
		domain_name($cfg->param('MAIL.FROM')));
	my $sms_watcher = partial(\&check_sms, $sms_mail_f, $convert_mail_f, $cfg->param('COMMON.WATCH_FOLDER'), $logger);

	while (1)
	{
		my $timestamp = time();
		my @events = $inotify->read();
		die "read error: $!" if (@events == 0);
		$logger->("Got folder inotified: " . $cfg->param('COMMON.WATCH_FOLDER'));
		$sms_watcher->($timestamp);
	}

	$logger->("sms_watcher ended.");
}

sub sms_file_to_subject($sms_file)
{
	my @suffixes = ('.txt');
	basename($sms_file, @suffixes);
}

sub sms_file_to_email($from, $to, $host, $sms_file)
{
	my $email = Email::Simple->create(
		header =>
		[
			From    => $from,
			To      => $to,
			Subject => sms_file_to_subject($sms_file),
			'Message-ID' => Email::MessageID->new(host => $host)->in_brackets(),
			'Content-type' => 'text/plain; charset=UTF-8',
			'Content-Transfer-Encoding' => 'base64',
		],
		body => encode_base64(read_file($sms_file)),
	);
	$email->as_string();
}

sub check_sms($process_sms_f, $convert_mail_f, $sms_folder, $logger, $timestamp)
{
	my $wanted = sub
	{
		my $n = $File::Find::name;
		if (-f $n and (stat($n))[9] > $timestamp)
		{
			$logger->("Found new sms: $n");
			$process_sms_f->($convert_mail_f->($n));
		}
	};

	find($wanted, $sms_folder);
}

sub send_sms_mail($cfg, $logger, $sms_data)
{
	eval
	{
		my $smtp = Net::SMTP->new($cfg->param('SMTP.SERVER'),
			Port => $cfg->param('SMTP.PORT'),
			SSL     => 1,
			Timeout => $cfg->param('SMTP.TIMEOUT'),
			Debug   => $cfg->param('SMTP.DEBUG'),
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
		) or die $!;
		$smtp->auth($cfg->param('SMTP.USER'), $cfg->param('SMTP.PASSWORD'));
		$smtp->mail($cfg->param('MAIL.FROM'));
		$smtp->to($cfg->param('MAIL.TO'));
		$smtp->data();
		$smtp->datasend($sms_data);
		$smtp->dataend();
		$smtp->quit();
	};
	if ($@)
	{
		$logger->("Sms mail encounted error. $@");
	}
	else
	{
		$logger->("Sms mail have been sucessfully delivered.");
	}
}

main();
