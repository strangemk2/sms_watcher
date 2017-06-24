use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Http;

use utf8;
use LWP::UserAgent;
use Try::Tiny;

use Plugin::Utils;

no warnings 'experimental::signatures';
use feature 'signatures';

# Main staff
sub execute($cfg, $logger, $filename)
{
	try
	{
		my $url = $cfg->param('HTTP.URL');

		my $ua = LWP::UserAgent->new();
		my $data = join (',', $filename, read_file($filename));
		my $res = $ua->post($url,
			'Content-Type' => 'text/plain; charset=utf-8',
			'Content' => $data);
		if ($res->is_success)
		{
			$logger->("Http send succeeded. file: $filename.");
		}
		else
		{
			die $res->status_line;
		}
	}
	catch
	{
		$logger->("Http send failed. file: $filename, $_");
		die;
	};
}

1;
