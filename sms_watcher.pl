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
use Try::Tiny;
use List::MoreUtils qw(apply);

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
		my $l = get_current_time() . " [log] $$: @_";
		chomp($l);
		say {$fh} $l;
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
	$inotify->watch($cfg->param('COMMON.WATCH_FOLDER'), IN_MODIFY|IN_MOVED_TO|IN_CREATE) or die "Watch creation failed";

	my $sms_mail_f = partial(\&send_sms_mail, $cfg, $logger);
	my $sms_mail_retry_f = partial(
		sms_process_retry($cfg->param('COMMON.RETRY'), $cfg->param('COMMON.INTERVAL')),
		$sms_mail_f, $logger);
	my $convert_mail_f = partial(\&sms_file_to_email,
		$cfg->param('MAIL.FROM'),
		$cfg->param('MAIL.TO'),
		domain_name($cfg->param('MAIL.FROM')));
	my $sms_watcher = partial(\&check_sms,
		$sms_mail_retry_f,
		$convert_mail_f,
		$cfg->param('COMMON.WATCH_FOLDER'),
		$logger);

	if (@ARGV > 0)
	{
		my $timestamp = $ARGV[0];
		$logger->("Enter recovery mode, recovery from epoch time $timestamp");
		$sms_watcher->($timestamp);
		$logger->("Recovery completed.");
	}
	else
	{
		my $loop = 1;
		$SIG{INT} = sub { $loop = 0 };
		# this try block is to prevent "Interrupted system call" error.
		try
		{
			while ($loop)
			{
				my $timestamp = time();
				my @events = $inotify->read();
				die "read error: $!" if (@events == 0);
				$logger->("Got folder inotified: " . $cfg->param('COMMON.WATCH_FOLDER'));
				$sms_watcher->($timestamp);
			}
		};
	}

	$logger->("sms_watcher stopped.");
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
	my @sms_list;
	my $wanted = sub
	{
		my $n = $File::Find::name;
		if (-f $n and (stat($n))[9] > $timestamp)
		{
			push @sms_list, $n;
		}
	};
	find($wanted, $sms_folder);

	apply
	{
		$logger->("Found new sms: $_");
		$process_sms_f->($convert_mail_f->($_));
	}
	sort (@sms_list);
}

sub send_sms_mail($cfg, $logger, $sms_data)
{
	try
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

		$logger->("Sms mail have been sucessfully delivered.");
	}
	catch
	{
		$logger->("Sms mail encounted error. $_");
		die;
	};
}

# TODO: there's a definetely memory leak that anonymous function "$do_with_retry" will never freed.
# Though Scalar::Util::weaken count decrease the reference counter,
# the anonymous function will be freed right after outer function returns.
# In the use case in this script, the call to make_retry is limited, so nothing
# to worry about the slightly leaks.
#use Scalar::Util qw(weaken);
sub sms_process_retry($max_retry, $retry_interval)
{
	my $max = $max_retry;
	my $interval = $retry_interval;
	my $do_with_retry;
	$do_with_retry = sub($sms_process_f, $logger, $arg, $count = $max)
	{
		try
		{
			return $sms_process_f->($arg);
		}
		catch
		{
			if ($count == 0)
			{
				$logger->("Retry aborted.");
				return;
			}
			$logger->("Retry " . ($max - $count + 1) . ".");
			sleep($interval);
			return $do_with_retry->($sms_process_f, $logger, $arg, $count - 1);
		};
	};
	#weaken($do_with_retry);
	return $do_with_retry;
}

main();
