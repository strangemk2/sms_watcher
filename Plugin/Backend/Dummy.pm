use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

package Plugin::Backend::Dummy;

use utf8;

no warnings 'experimental::signatures';
use feature 'signatures';

# Main staff
sub execute($cfg, $logger, $filename)
{
	$logger->("Dummy process backend of file: $filename.");
}

1;
