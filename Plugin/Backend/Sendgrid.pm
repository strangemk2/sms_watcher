use 5.024;
use FindBin qw($Bin);
use lib qw/./;
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Sendgrid;

use utf8;
use File::Basename;
use Try::Tiny;

use Email::SendGrid::V3;

use Plugin::Utils;

no warnings 'experimental::signatures';
use feature 'signatures';

# Main staff
sub execute($cfg, $logger, $filename)
{
	my $sg = Email::SendGrid::V3->new(api_key => $cfg->param('SENDGRID.KEY'));
	my $result = $sg->from($cfg->param('SENDGRID.FROM'))
	                ->subject(sms_file_to_subject($filename))
	                ->add_content('text/plain', read_file($filename))
	                ->add_envelope( to => [ $cfg->param('SENDGRID.TO') ] )
	                ->send;
	if ($result->{success})
	{
		$logger->("Send sendgrid mail succeeded.");
	}
	else
	{
		$logger->("Send sendgrid mail failed. $_");
		die;
	}
}

sub sms_file_to_subject($sms_file)
{
	my @suffixes = ('.txt');
	basename($sms_file, @suffixes);
}

1;
