use 5.024;

package Plugin::Utils;
use Exporter 'import';
our @EXPORT = qw(read_file domain_name);

use utf8;

no warnings 'experimental::signatures';
use feature 'signatures';

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

1;
