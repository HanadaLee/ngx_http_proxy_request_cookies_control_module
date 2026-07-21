# ngx_http_proxy_request_cookies_control_module

# Name
ngx_http_proxy_request_cookies_control_module

A NGINX module for fine-grained proxy request cookies control.

# Table of Content

- [ngx\_http\_proxy\_request\_cookies\_control\_module](#ngx_http_proxy_request_cookies_control_module)
- [Name](#name)
- [Table of Content](#table-of-content)
- [Status](#status)
- [Synopsis](#synopsis)
- [Installation](#installation)
- [Conditional syntax](#conditional-syntax)
- [Directives](#directives)
  - [proxy\_request\_cookie\_control](#proxy_request_cookie_control)
- [Author](#author)
- [License](#license)

# Status

This Nginx module is currently considered experimental. Issues and PRs are welcome if you encounter any problems.

# Synopsis

```nginx
http {
    server {
        listen 80;
        server_name example.com;

        proxy_request_cookie_control append form_server_level 1;

        location / {
            # If a cookie named "a" exists, set it to 1. Otherwise, add a cookie named "a" with value 1.
            proxy_request_cookie_control set a 1;

            # If a cookie named "b" exists, do nothing. Otherwise, add a cookie named "b" with value 2.
            proxy_request_cookie_control add b 2;

            # If a cookie named "c" exists, set it to 3. Otherwise, do nothing.
            proxy_request_cookie_control rewrite c 3;
    
            # If a cookie named "d" exists, clear it. Otherwise, do nothing.
            proxy_request_cookie_control clear d;

            # Clear all cookies.
            proxy_request_cookie_control clear *;

            # Clear cookies with a prefix.
            proxy_request_cookie_control clear session_*;

            # Keep cookies. Other cookies will be cleared.
            proxy_request_cookie_control keep e f g;

            # Pass a cookie through and disable later same-name rules.
            proxy_request_cookie_control pass token;

            # With ngx_condition_module.
            condition has_header_a is_not_empty $http_a;
            when has_header_a {
                proxy_request_cookie_control set h 4;
            }

            # If has `-i` option, the cookie name will be case-insensitive.
            proxy_request_cookie_control set -i i 1;

            # If has `-b`, stop evaluating subsequent rules and output the final result.
            proxy_request_cookie_control set -b j 5;

            proxy_pass http://127.0.0.1:8080;
        }
    }
}
```

# Installation

This module requires [ngx_http_proxy_filter_module](https://github.com/your-repo/ngx_http_proxy_filter_module) to be compiled first.

To use theses modules, configure your nginx branch with:

```bash
./configure \
    --add-module=/path/to/ngx_http_proxy_filter_module \
    --add-module=/path/to/ngx_http_proxy_request_cookies_control_module
```

To enable named conditions, add `--add-module=/path/to/ngx_condition_module` to the same static nginx build.

# Conditional syntax

Conditional syntax is selected at compile time:

- With `ngx_condition_module`, use named `condition` expressions and place `proxy_request_cookie_control` inside an `http`, `server`, or `location` `when` block. `if=` and `if!=` parameters are rejected.
- Without `ngx_condition_module`, `when` is unavailable and legacy `if=`/`if!=` parameters remain supported. `if=` matches a non-empty value other than `"0"`; `if!=` matches an empty value or `"0"`.

If a condition does not match, the rule is skipped and does not stop later rules for the same cookie. The directive also remains valid in nginx's native `if` block inside a location; that context is separate from a condition-module `when` block.

# Directives

## proxy_request_cookie_control

**Syntax:** `proxy_request_cookie_control operator [-i] [-n] [-b] cookie_name [value ...];`

**Legacy syntax (without ngx_condition_module):** `proxy_request_cookie_control operator [-i] [-n] [-b] cookie_name [value ...] [if=condition | if!=condition];`

**Default:** —

**Context:** http, server, location, location if; http when, server when, location when (with ngx_condition_module)

Filters cookies in the upstream request headers. All filter rules are applied in the order they are defined. The result directly modifies the `Cookie` header sent to the upstream.

The following operators are supported:

| Operator  | Description                                                                                                           |
|-----------|-----------------------------------------------------------------------------------------------------------------------|
| `set`     | Sets the value of a cookie. If the cookie already exists, it will be rewritten.                                       |
| `add`     | Adds a new cookie. If the cookie already exists, the operation is ignored.                                            |
| `append`  | Appends a new cookie even if the cookie already exists.                                                               |
| `rewrite` | Rewrites the value of a cookie. If the cookie doesn't exist, the operation is ignored.                                |
| `clear`   | Removes a cookie from the request headers. Prefix wildcards such as `session_*` are supported. If cookie name is `*`, all cookies will be cleared. |
| `keep`    | Keeps specified cookies. Multiple cookie names can be provided. Other cookies will be cleared.                        |
| `pass`    | No-op; explicitly passes a cookie through and disables later same-name rules.                                         |

The following parameters are supported:

| Parameter | Description |
|-----------|-------------|
| `-i` | Makes the cookie name case-insensitive. When an existing cookie is matched and needs to be set or rewritten, only its value is modified. The original name is preserved. |
| `-n` | By default, once a cookie name is matched, subsequent rules for that name are skipped. This flag continues evaluating later rules for the same cookie name after this rule is applied. Wildcard `clear` and `keep` rules are not affected and always continue. |
| `-b` | Stops evaluating subsequent cookie rules and outputs the final result after this rule applies. |
| `if=condition` | Legacy-only: evaluates the rule if the value is non-empty and not `0`. |
| `if!=condition` | Legacy-only: evaluates the rule if the value is empty or `0`. |

# Author

Hanada im@hanada.info

# License

This Nginx module is licensed under [BSD 2-Clause License](LICENSE).
