#!/usr/bin/perl

# Cookie boundaries and empty names, with or without ngx_expr_module.

use warnings;
use strict;
use Test::More;
BEGIN { use FindBin; chdir($FindBin::Bin); }
use Test::Nginx qw/ :DEFAULT http_content /;

my @rules = (
    [clear => 'clear a'], [rewrite => 'rewrite a changed'],
    [set => 'set a changed'], [keep => 'keep a'],
    [append => 'append c 3'], [all => 'clear *'],
    [clear_empty => 'clear ""'], [keep_empty => 'keep ""'],
    [rewrite_empty => 'rewrite "" changed'], [set_empty => 'set "" changed'],
    [append_empty => 'append "" added'], [add_empty => 'add "" added'],
    [pass_empty => 'pass ""; proxy_request_cookie_control clear ""'],
);
my @cases = (
    [clear => 'a; a=1; b=2', 'a; b=2'],
    [clear => 'junk; a=1; b=2', 'junk; b=2'],
    [rewrite => 'junk; a=1; b=2', 'junk; a=changed; b=2'],
    [set => 'junk; a=1; b=2', 'junk; a=changed; b=2'],
    [keep => 'junk; a=1; b=2', 'a=1'],
    [append => 'a=1; tail', 'a=1; tail; c=3'],
    [append => 'tail', 'tail; c=3'],
    [all => 'tail', ''],
    [all => 'a; a=1; tail', ''],
    [clear_empty => 'a; a=1; =other; tail', 'a=1'],
    [keep_empty => 'a; a=1; =other; tail', 'a; =other; tail'],
    [rewrite_empty => 'a; a=1; tail', 'changed; a=1'],
    [rewrite_empty => '=a; a=1', '=changed; a=1'],
    [set_empty => 'a=1', 'a=1; changed'],
    [append_empty => 'a; a=1', 'a; a=1; added'],
    [add_empty => 'tail; a=1', 'tail; a=1'],
    [add_empty => 'a=1', 'a=1; added'],
    [pass_empty => 'tail; a=1', 'tail; a=1'],
    [append => 'a=; =; tail', 'a=; =; tail; c=3'],
    [append => 'a=x=y; tail', 'a=x=y; tail; c=3'],
    [clear => ';;; a=1; ; tail;;', 'tail'],
    [clear => " \tbare \t; a \t= \t1\t ; b=2 ", 'bare; b=2'],
    [clear => ['junk', 'a=1; tail'], 'junk; tail'],
    [clear_empty => ['junk', '=other; a=1; tail'], 'a=1'],
);
my $t = Test::Nginx->new()->has(qw/http proxy rewrite
    ngx_http_proxy_request_cookies_control_module/)->plan(scalar @cases);
my $locations = join '', map {
    "location /$_->[0] { proxy_request_cookie_control $_->[1]; "
        . "proxy_pass http://127.0.0.1:8081; }\n"
} @rules;
$t->write_file_expand('nginx.conf', <<EOF);
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8081;
        return 200 "[\$http_cookie]";
    }
    server {
        listen 127.0.0.1:8080;
        $locations
    }
}
EOF
$t->run();
for my $case (@cases) {
    my ($rule, $input, $expected) = @$case;
    my @headers = ref $input ? @$input : ($input);
    my $request = "GET /$rule HTTP/1.0\r\nHost: localhost\r\n"
        . join('', map { "Cookie: $_\r\n" } @headers) . "\r\n";
    is(http_content(http($request)), "[$expected]", "$rule: " . join(' / ', @headers));
}
