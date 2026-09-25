#!/usr/bin/perl

# Tests for legacy proxy request cookie predicates without ngx_expr_module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite
	ngx_http_proxy_filter_module
	ngx_http_proxy_request_cookies_control_module/);

plan(skip_all => 'legacy predicate build required')
	if $t->has_module('ngx_expr_module');

$t->plan(12);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8081;
        server_name  backend;

        location / {
            return 200 "$http_cookie";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_request_cookie_control set inherited parent;

        location = /predicates {
            proxy_request_cookie_control set positive yes if=$arg_apply;
            proxy_request_cookie_control set negative yes if!=$arg_skip;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /inherit {
            proxy_request_cookie_control set inherited child if=$arg_apply;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /break {
            proxy_request_cookie_control set -b gate hit if=$arg_apply;
            proxy_request_cookie_control set after continued;
            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF

$t->run();

###############################################################################

my $hit = response('/predicates?apply=1&skip=0');
is(cookie_value($hit, 'positive'), 'yes',
	'if= applies a rule to a truthy value');
is(cookie_value($hit, 'negative'), 'yes',
	'if!= applies a rule to a false value');

my $miss = response('/predicates?apply=0&skip=1');
ok(!defined cookie_value($miss, 'positive'),
	'if= skips a rule for zero');
ok(!defined cookie_value($miss, 'negative'),
	'if!= skips a rule for a truthy value');

is(cookie_value(response('/inherit?apply=1', 'Cookie: inherited=old'),
	'inherited'), 'child', 'matching legacy child rule wins');
is(cookie_value(response('/inherit?apply=0', 'Cookie: inherited=old'),
	'inherited'), 'parent',
	'parent rule remains when legacy child condition misses');

my $break_hit = response('/break?apply=1');
is(cookie_value($break_hit, 'gate'), 'hit',
	'matching legacy break rule applies');
ok(!defined cookie_value($break_hit, 'after'),
	'matching legacy break rule stops evaluation');

my $break_miss = response('/break?apply=0');
ok(!defined cookie_value($break_miss, 'gate'),
	'legacy condition miss skips the break rule');
is(cookie_value($break_miss, 'after'), 'continued',
	'legacy condition miss allows later rules');

my $empty = response('/predicates?apply=&skip=', 'Cookie: positive=old');
is(cookie_value($empty, 'positive'), 'old',
	'if= treats an empty value as false');
is(cookie_value($empty, 'negative'), 'yes',
	'if!= treats an empty value as false');

###############################################################################

sub cookie_value {
	my ($response, $name) = @_;
	my $body = http_content($response);

	for my $cookie (split /;\s*/, $body) {
		my ($cookie_name, $value) = split /=/, $cookie, 2;

		return $value if defined $value && $cookie_name eq $name;
	}

	return undef;
}


sub response {
	my ($uri, @headers) = @_;
	my $headers = join '', map { "$_\x0d\x0a" } @headers;

	return http("GET $uri HTTP/1.1\x0d\x0a"
		. "Host: localhost\x0d\x0a"
		. $headers
		. "Connection: close\x0d\x0a\x0d\x0a");
}

###############################################################################
