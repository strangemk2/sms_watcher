use 5.024;
use FindBin qw($Bin);
use lib qw/./;
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

no warnings 'experimental::signatures';
use feature 'signatures';
no warnings 'experimental::smartmatch';
use feature "switch";

use utf8;
use Linux::Inotify2;
use POSIX qw(strftime);
use File::Find;
use Config::Simple;
use List::MoreUtils qw(apply);
use Try::Tiny;

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

# Main staff
sub main
{
	my $cfg = Config::Simple->new('sms_watcher.ini') or die Config::Simple->error();
	my $logger = get_logger($cfg->param('COMMON.LOG_FILE'));
	$logger->("sms_watcher started.");

	my $inotify = Linux::Inotify2->new() or die "Unable to create new inotify object: $!" ;
	$inotify->watch($cfg->param('COMMON.WATCH_FOLDER'), IN_MODIFY|IN_MOVED_TO|IN_CREATE) or die "Watch creation failed";

	my @sms_process_funcs = map
	{
		my $process_f = partial(get_process_func($_), $cfg, $logger);
		partial(sms_process_retry($cfg->param('COMMON.RETRY'), $cfg->param('COMMON.INTERVAL')),
			$process_f, $logger);
	}
	$cfg->param('COMMON.BACKEND');

	my $sms_watcher = partial(\&check_sms,
		\@sms_process_funcs,
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
				sleep $cfg->param('COMMON.INTERVAL');
				$sms_watcher->($timestamp);
			}
		};
	}

	$logger->("sms_watcher stopped.");
}

sub check_sms($sms_process_funcs, $sms_folder, $logger, $timestamp)
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
		my $sms = $_;
		$logger->("Found new sms: $_");
		apply { $_->($sms) } @$sms_process_funcs;
	}
	sort (@sms_list);
}

sub get_process_func($type)
{
	my $module_type = ucfirst(lc($type));
	my $func;
	try
	{
		require "$Bin/Plugin/Backend/$module_type.pm";
		$func = "Plugin::Backend::${module_type}::execute";
	}
	catch
	{
		require "$Bin/Plugin/Backend/Dummy.pm";
		$func = "Plugin::Backend::Dummy::execute";
	};
	return \&{$func};
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
