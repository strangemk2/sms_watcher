use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Email;

use utf8;
use Email::Simple;
use Net::SMTP;
use Encode;
use MIME::Base64;
use Email::MessageID;
use File::Basename;
use Try::Tiny;

no warnings 'experimental::signatures';
use feature 'signatures';

# Misc staff
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
sub execute($cfg, $logger, $filename)
{
	my $sms_data = sms_file_to_email(
		{ from      => $cfg->param('MAIL.FROM'),
		  to        => $cfg->param('MAIL.TO'),
		  host      => domain_name($cfg->param('MAIL.FROM')), },
		$filename);
	send_sms_mail(
		{ server    => $cfg->param('SMTP.SERVER'),
		  port      => $cfg->param('SMTP.PORT'),
		  timeout   => $cfg->param('SMTP.TIMEOUT'),
		  debug     => $cfg->param('SMTP.DEBUG'),
		  user      => $cfg->param('SMTP.USER'),
		  password  => $cfg->param('SMTP.PASSWORD'),
		  from      => $cfg->param('MAIL.FROM'),
		  to        => $cfg->param('MAIL.TO'), },
		$logger, $sms_data);
}

sub sms_file_to_subject($sms_file)
{
	my @suffixes = ('.txt');
	basename($sms_file, @suffixes);
}

sub sms_file_to_email($params, $sms_file)
{
	my $email = Email::Simple->create(
		header =>
		[
			From    => $params->{from},
			To      => $params->{to},
			Subject => sms_file_to_subject($sms_file),
			'Message-ID' => Email::MessageID->new(host => $params->{host})->in_brackets(),
			'Content-type' => 'text/plain; charset=UTF-8',
			'Content-Transfer-Encoding' => 'base64',
		],
		body => encode_base64(read_file($sms_file)),
	);
	$email->as_string();
}

sub send_sms_mail($params, $logger, $sms_data)
{
	try
	{
		my $smtp = Net::SMTP->new($params->{server},
			Port => $params->{port},
			SSL     => 1,
			Timeout => $params->{timeout},
			Debug   => $params->{debug},
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
		) or die $!;
		$smtp->auth($params->{user}, $params->{password});
		$smtp->mail($params->{from});
		$smtp->to($params->{to});
		$smtp->data();
		$smtp->datasend($sms_data);
		$smtp->dataend();
		$smtp->quit();

		$logger->("Send sms mail succeeded.");
	}
	catch
	{
		$logger->("Send sms mail failed. $_");
		die;
	};
}

1;
