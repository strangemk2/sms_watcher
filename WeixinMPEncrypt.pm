use 5.024;

package PKCS7;

use bytes;

no warnings 'experimental::signatures';
use feature 'signatures';

sub padding($data, $k)
{
	my $padding = $k - (length($data) % $k);
	return $data . pack('C*', map {$padding} 1..$padding);
}

sub unpadding($data)
{
	return substr($data, 0, length($data) - ord(substr($data, -1)));
}

package WeixinMPEncrypt;

use bytes;
use MIME::Base64;
use Crypt::CBC;
use Crypt::Cipher::AES;

use Data::Dumper;

no warnings 'experimental::signatures';
use feature 'signatures';

sub encrypt($key, $data, $appid)
{
	my $decoded_key = decode_base64("${key}=");
	my $encoded = PKCS7::padding(
		pack("a16Na*", pack('C*', map {int(rand(256))} 1..16), length($data), $data) . $appid,
		32);

	my $cbc = Crypt::CBC->new(-cipher => 'Cipher::AES',
			-key => $decoded_key,
			-iv => pack('C*', map {int(rand(256))} 1..16),
			-header => 'none',
			-padding => 'none',
			-keysize => 32,
			-literal_key => 1);
	return encode_base64($cbc->encrypt($encoded), '');
}

sub decrypt($key, $data, $appid)
{
	my $decoded_key = decode_base64("${key}=");

	my $cbc = Crypt::CBC->new(-cipher => 'Cipher::AES',
			-key => $decoded_key,
			-iv => pack('C*', map {int(rand(256))} 1..16),
			-header => 'none',
			-padding => 'none',
			-keysize => 32,
			-literal_key => 1);
	my $decoded = $cbc->decrypt(decode_base64($data));
	my (undef, $length, $data) = unpack("a16Na*", $decoded);
	my $unpadding_data = PKCS7::unpadding($data);
	return substr($unpadding_data, $length) eq $appid ? substr($unpadding_data, 0, $length) : undef;
}

1;
