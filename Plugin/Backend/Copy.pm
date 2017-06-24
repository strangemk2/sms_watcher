use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Copy;

use utf8;
use File::Basename;
use File::Copy;
use Try::Tiny;

no warnings 'experimental::signatures';
use feature 'signatures';

# Main staff
sub execute($cfg, $logger, $filename)
{
	try
	{
		copy($filename, $cfg->param('COPY.DEST')) or die $!;
		$logger->("Copy succeeded. file: $filename.");
	}
	catch
	{
		$logger->("Copy failed. file: $filename, $_");
	};
}

1;
