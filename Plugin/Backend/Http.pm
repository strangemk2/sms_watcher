use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Http;

use utf8;
use LWP::UserAgent;
use Try::Tiny;
use File::Basename;

use Plugin::Utils;

use Config::Simple;
use WeixinMPEncrypt;

no warnings 'experimental::signatures';
use feature 'signatures';

# Main staff
sub execute($cfg, $logger, $filename)
{
	try
	{
		my $url = $cfg->param('HTTP.URL');

		my $ua = LWP::UserAgent->new();
		my $data = join (',', basename($filename, '.txt'), read_file($filename));
		my $res = $ua->post($url,
			'Content-Type' 	=> 'text/plain; charset=utf-8',
			'Content' 	=> WeixinMPEncrypt::encrypt($cfg->param('AES.KEY'),
								$cfg->param('HTTP.OPENID') . ",$data",
								$cfg->param('AES.APPID')));
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
