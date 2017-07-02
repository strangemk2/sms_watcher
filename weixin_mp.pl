use 5.024;
use FindBin qw($Bin);
use lib qq($Bin/extlib/lib/perl5);
use lib qq($Bin/extlib/lib/perl5/x86_64-linux);

use utf8;
use Digest::SHA1 qw(sha1_hex);
use Config::Simple;

use Mojolicious::Lite;
use Mojo::DOM;

use Data::Dumper;

no warnings 'experimental::signatures';
use feature 'signatures';

# Route with placeholder

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

sub check_clear_signature($c, $token)
{
	return check_signature($c->param('signature'),
		$token, $c->param('timestamp'), $c->param('nonce'));
}

sub check_aes_signature($c, $msg, $token)
{
	return check_signature($c->param('msg_signature'),
		$token, $c->param('timestamp'), $c->param('nonce'), $msg);
}

sub check_signature
{
	my $a = shift;
	my $b = calc_signature(@_);
	return $a eq $b;
}

sub calc_signature
{
	return sha1_hex(join('', sort(@_)));
}

sub render_certificate($c)
{
	say Dumper($c->tx->req->params);

	if (!check_signature($c))
	{
		$c->render(text => '', status => 503) 
	}
	else
	{
		$c->render(text => $c->param('echostr'));
	}

	#say Dumper($c->tx->req->params);
};

sub make_response_xml($to_user_name, $from_user_name, $create_time, $msg_type, $content)
{
	return "<xml>
	<ToUserName><![CDATA[$to_user_name]]></ToUserName>
	<FromUserName><![CDATA[$from_user_name]]></FromUserName>
	<CreateTime>$create_time</CreateTime>
	<MsgType><![CDATA[$msg_type]]></MsgType>
	<Content><![CDATA[$content]]></Content>
	</xml>";
}

sub make_encrypted_xml($encrypt, $msg_signature, $timestamp, $nonce)
{
	return "<xml>
	<Encrypt><![CDATA[$encrypt]]></Encrypt>
	<MsgSignature><![CDATA[$msg_signature]]></MsgSignature>
	<TimeStamp><![CDATA[$timestamp]]></TimeStamp>
	<Nonce><![CDATA[$nonce]]></Nonce>
	</xml>";
}

sub weixin_mp_encrypt
{
}

sub weixin_mp_decrypt
{
}

sub render_mp($c, $cfg)
{
	if (!check_clear_signature($c, $cfg->param('AES.TOKEN')))
	{
		$c->render(text => '', status => 503);
		return;
	}

	say Dumper($c->tx->req->params);
	say $c->req->body;

	$c->render(text => "success");
	return;

	if ($c->param('encrypt_type') ne 'aes')
	{
		$c->render(text => "success");
		return;
	}

	my $outer_dom = Mojo::DOM->new->xml(1)->parse($c->req->body);

	my $encrypted = $outer_dom->at('Encrypt')->text;
	if (!check_aes_signature($c, $encrypted, $cfg->param('AES.TOKEN')))
	{
		$c->render(text => '', status => 503);
		return;
	}

	my $decrypted = weixin_mp_decrypt($cfg->param('AES.KEY'), $encrypted);
	my $inner_dom =  Mojo::DOM->new->xml(1)->parse($decrypted);

	if ($inner_dom->at('MsgType')->text ne 'text')
	{
		$c->render(text => "success");
	}
	else
	{
		my $response_encrypted = weixin_mp_encrypt($cfg->param('AES.KEY'),
					make_response_xml(
					$inner_dom->at('FromUserName')->text,
					$inner_dom->at('ToUserName')->text,
					$inner_dom->at('CreateTime')->text,
					$inner_dom->at('MsgType')->text,
					"i'm very ok.\n我非常 ok."));
		my $response_signature = calc_signature($cfg->param('AES.TOKEN'),
					$c->param('timestamp'),
					$c->param('nonce'),
					$response_encrypted);
		$c->render(text => make_encrypted_xml($response_encrypted,
					$response_signature,
					$c->param('timestamp'),
					$c->param('nonce')));
	}
}

sub render_503($c)
{
	$c->render(text => '', status => 503);
};

sub get_render_function($func)
{
	my $cfg = Config::Simple->new('weixin_mp.ini') or die Config::Simple->error();
	return partial($func, $cfg);
}

get '/helloworld' => \&render_certificate;
post '/helloworld' => get_render_function(\&render_mp);
get '*' => \&render_503;
get '/' => \&render_503;

# Start the Mojolicious command system
app->start;
