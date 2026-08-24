#!/usr/bin/perl

# Tests for proxy request cookie controls with ngx_condition_module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite ngx_condition_module
	ngx_http_proxy_filter_module
	ngx_http_proxy_request_cookies_control_module/)->plan(38);

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

        condition special str_eq $arg_mode special;

        location = /ops {
            proxy_request_cookie_control set existing $arg_value;
            proxy_request_cookie_control set created created;
            proxy_request_cookie_control add add-existing ignored;
            proxy_request_cookie_control add add-new added;
            proxy_request_cookie_control append appended extra;
            proxy_request_cookie_control rewrite rewrite rewritten;
            proxy_request_cookie_control rewrite rewrite-missing ignored;
            proxy_request_cookie_control clear clear;
            proxy_request_cookie_control clear session_*;
            proxy_request_cookie_control set -i mixed changed;
            proxy_request_cookie_control set -n chain first;
            proxy_request_cookie_control rewrite chain second;
            proxy_request_cookie_control pass passed;
            proxy_request_cookie_control set passed replaced;
            proxy_request_cookie_control set -b stop hit;
            proxy_request_cookie_control set after-break changed;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /clear-all {
            proxy_request_cookie_control clear *;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /keep {
            proxy_request_cookie_control keep -i keepone keeptwo;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /multi {
            proxy_request_cookie_control set duplicate selected;
            proxy_request_cookie_control append tail appended;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /empty {
            proxy_request_cookie_control set vanish $arg_value;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /add {
            proxy_request_cookie_control add new-cookie $arg_value;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /conditional {
            when special {
                proxy_request_cookie_control set selected condition;
            }

            proxy_request_cookie_control set selected fallback;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /order {
            proxy_request_cookie_control set selected first;

            when special {
                proxy_request_cookie_control set selected second;
            }

            proxy_pass http://127.0.0.1:8081;
        }

        location = /conditional-break {
            when special {
                proxy_request_cookie_control set -b gate hit;
            }

            proxy_request_cookie_control set after continued;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /if-context {
            if ($arg_apply) {
                proxy_request_cookie_control set if-cookie applied;
            }

            proxy_pass http://127.0.0.1:8081;
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  inheritance;

        condition child_selected str_eq $arg_mode special;

        proxy_request_cookie_control set inherited parent;
        proxy_request_cookie_control set unrelated parent-only;

        location = /inherit {
            proxy_pass http://127.0.0.1:8081;
        }

        location = /override {
            proxy_request_cookie_control set inherited child;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /conditional-inherit {
            when child_selected {
                proxy_request_cookie_control set inherited selected;
            }

            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF

$t->run();

###############################################################################

my $ops = response('/ops?value=dynamic', 8080,
	'Cookie: existing=old-one; existing=old-two; add-existing=keep; '
	. 'appended=base; rewrite=old; clear=gone; session_a=1; session_b=2; '
	. 'MiXeD=old; chain=old; passed=keep; after-break=old');

is_deeply([cookie_values($ops, 'existing')], ['dynamic'],
	'set replaces duplicate cookies');
is(cookie_value($ops, 'created'), 'created', 'set creates a missing cookie');
is(cookie_value($ops, 'add-existing'), 'keep',
	'add preserves an existing cookie');
is(cookie_value($ops, 'add-new'), 'added', 'add creates a missing cookie');
is_deeply([cookie_values($ops, 'appended')], [qw/base extra/],
	'append creates a duplicate cookie');
is(cookie_value($ops, 'rewrite'), 'rewritten',
	'rewrite changes an existing cookie');
ok(!defined cookie_value($ops, 'rewrite-missing'),
	'rewrite does not create a missing cookie');
ok(!defined cookie_value($ops, 'clear'), 'clear removes an exact cookie');
ok(!defined cookie_value($ops, 'session_a'),
	'wildcard clear removes the first matching cookie');
ok(!defined cookie_value($ops, 'session_b'),
	'wildcard clear removes the second matching cookie');
is(cookie_value($ops, 'MiXeD'), 'changed',
	'-i matches case-insensitively and preserves the cookie name');
ok(!defined cookie_value($ops, 'mixed'),
	'-i does not replace the original cookie name');
is(cookie_value($ops, 'chain'), 'second',
	'-n allows the next same-name rule to execute');
is(cookie_value($ops, 'passed'), 'keep',
	'pass prevents a later same-name rule');
is(cookie_value($ops, 'after-break'), 'old',
	'-b prevents later rules from executing');
is(cookie_value($ops, 'stop'), 'hit', '-b applies its own rule');

is(cookie_body(response('/clear-all', 8080, 'Cookie: a=1; b=2')), '',
	'clear all removes the Cookie header value');

my $keep = response('/keep', 8080,
	'Cookie: KeepOne=1; keeptwo=2; dropped=3');
is(cookie_body($keep), 'KeepOne=1; keeptwo=2',
	'keep retains only listed cookies with case-insensitive matching');

my $multi = response('/multi', 8080,
	'Cookie: duplicate=first; a=1',
	'Cookie: duplicate=second; b=2');
is(cookie_body($multi), 'duplicate=selected; a=1; b=2; tail=appended',
	'multiple Cookie headers are consolidated after filtering');

is(cookie_body(response('/empty?value=', 8080, 'Cookie: vanish=old')), '',
	'an empty set value removes the cookie');
is(cookie_body(response('/add?value=dynamic', 8080)), 'new-cookie=dynamic',
	'a rule can create the first Cookie header');

is(cookie_value(response('/conditional?mode=special', 8080), 'selected'),
	'condition', 'matching condition selects its rule');
is(cookie_value(response('/conditional?mode=other', 8080), 'selected'),
	'fallback', 'condition miss allows the fallback rule');
is(cookie_value(response('/order?mode=special', 8080), 'selected'), 'first',
	'first unconditional rule wins over a later condition');

my $break_hit = response('/conditional-break?mode=special', 8080);
is(cookie_value($break_hit, 'gate'), 'hit',
	'matching conditional break rule applies');
ok(!defined cookie_value($break_hit, 'after'),
	'matching conditional break rule stops evaluation');

my $break_miss = response('/conditional-break?mode=other', 8080);
ok(!defined cookie_value($break_miss, 'gate'),
	'condition miss does not apply the break rule');
is(cookie_value($break_miss, 'after'), 'continued',
	'condition miss does not stop later rules');

is(cookie_value(response('/if-context?apply=1', 8080), 'if-cookie'),
	'applied', 'directive works in location if context');
ok(!defined cookie_value(response('/if-context?apply=0', 8080),
	'if-cookie'), 'location if rule is absent when its condition misses');

my $inherited = response('/inherit', 8082,
	'Cookie: inherited=old; unrelated=old');
is(cookie_value($inherited, 'inherited'), 'parent',
	'parent rule inherits unchanged');
is(cookie_value($inherited, 'unrelated'), 'parent-only',
	'all parent rules inherit unchanged');

my $overridden = response('/override', 8082,
	'Cookie: inherited=old; unrelated=old');
is(cookie_value($overridden, 'inherited'), 'child',
	'unconditional child rule disables the same parent rule');
is(cookie_value($overridden, 'unrelated'), 'parent-only',
	'unrelated parent rule remains inherited');

my $child = response('/conditional-inherit?mode=special', 8082,
	'Cookie: inherited=old; unrelated=old');
is(cookie_value($child, 'inherited'), 'selected',
	'matching conditional child rule wins');
is(cookie_value($child, 'unrelated'), 'parent-only',
	'conditional child preserves unrelated parent rules');

my $parent = response('/conditional-inherit?mode=other', 8082,
	'Cookie: inherited=old; unrelated=old');
is(cookie_value($parent, 'inherited'), 'parent',
	'parent rule remains when child condition misses');
is(cookie_value($parent, 'unrelated'), 'parent-only',
	'parent fallback preserves unrelated rules');

###############################################################################

sub cookie_body {
	my ($response) = @_;
	my $body = http_content($response);

	$body =~ s/\x0d?\x0a\z//;

	return $body;
}


sub cookie_value {
	my ($response, $name) = @_;
	my ($value) = cookie_values($response, $name);

	return $value;
}


sub cookie_values {
	my ($response, $name) = @_;
	my @values;

	for my $cookie (split /;\s*/, cookie_body($response)) {
		my ($cookie_name, $value) = split /=/, $cookie, 2;

		next if !defined $value || $cookie_name ne $name;
		push @values, $value;
	}

	return @values;
}


sub response {
	my ($uri, $port, @headers) = @_;
	my $headers = join '', map { "$_\x0d\x0a" } @headers;

	return http("GET $uri HTTP/1.1\x0d\x0a"
		. "Host: localhost\x0d\x0a"
		. $headers
		. "Connection: close\x0d\x0a\x0d\x0a",
		PeerAddr => '127.0.0.1:' . port($port));
}

###############################################################################
