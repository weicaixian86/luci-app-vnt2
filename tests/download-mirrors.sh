#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="${ROOT_DIR}/luci-app-vnt2/root/etc/init.d/vnt2"
CBI_SCRIPT="${ROOT_DIR}/luci-app-vnt2/luasrc/model/cbi/vnt2.lua"
DEFAULT_CONFIG="${ROOT_DIR}/luci-app-vnt2/root/etc/config/vnt2"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

load_function() {
	name="$1"
	definition="$(awk -v signature="${name}() {" '
		$0 == signature { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "$INIT_SCRIPT")"
	[ -n "$definition" ] || fail "function ${name} was not found"
	eval "$definition"
}

assert_equal() {
	expected="$1"
	actual="$2"
	message="$3"
	[ "$actual" = "$expected" ] || fail "$message: expected [$expected], got [$actual]"
}

test_mirror_candidates() {
	load_function trim_value
	load_function normalize_download_mirror
	load_function get_download_mirror_candidates

	auto_candidates="$(get_download_mirror_candidates vnt-dev/vnt auto)"
	assert_equal "$(printf '%s\n' gh-proxy github gitee gitlab cloudflare)" "$auto_candidates" \
		"automatic mirror order changed"
	if printf '%s\n' "$auto_candidates" | grep -qx custom; then
		fail "custom mirror was included in automatic mode"
	fi

	custom_candidates="$(get_download_mirror_candidates vnt-dev/vnt custom)"
	assert_equal "$(printf '%s\n' custom github)" "$custom_candidates" \
		"custom mirror fallback changed"
	printf 'PASS: automatic and custom mirror candidate order\n'
}

test_custom_url_handling() {
	GH_PROXY_PREFIX="https://gh-proxy.com/"
	load_function strip_github_proxy_url
	load_function is_github_download_url
	load_function normalize_custom_mirror_url
	load_function get_download_url_candidates_for_mirror

	raw_url="https://github.com/vnt-dev/vnt/releases/download/v2.0.8/file.zip"
	normalized="$(normalize_custom_mirror_url ' https://gh-proxy.com ')"
	assert_equal "https://gh-proxy.com/" "$normalized" "custom mirror normalization failed"

	custom_urls="$(get_download_url_candidates_for_mirror "$raw_url" custom "$normalized")"
	assert_equal "$(printf '%s\n' "${normalized}${raw_url}" "$raw_url")" "$custom_urls" \
		"custom mirror did not fall back only to GitHub"

	proxy_urls="$(get_download_url_candidates_for_mirror "$raw_url" gh-proxy '')"
	assert_equal "${GH_PROXY_PREFIX}${raw_url}" "$proxy_urls" "gh-proxy URL composition failed"
	printf 'PASS: custom mirror normalization and URL composition\n'
}

test_defaults_and_retry_limits() {
	[ "$(grep -c "option download_mirror 'auto'" "$DEFAULT_CONFIG")" -eq 3 ] || \
		fail "CLI, Web, and server defaults are not all auto"
	grep -Fq 'option:value("auto", translate("自动（从上到下）"))' "$CBI_SCRIPT" || \
		fail "automatic option is missing from LuCI"
	grep -Fq 'option:value("cloudflare", "Cloudflare R2")' "$CBI_SCRIPT" || \
		fail "Cloudflare R2 option is missing from LuCI"
	grep -Fq 'option:value("custom", translate("自定义"))' "$CBI_SCRIPT" || \
		fail "custom option is missing from LuCI"
	grep -Fq 'option.placeholder = "https://gh-proxy.com/"' "$CBI_SCRIPT" || \
		fail "custom mirror format example is missing"
	grep -Fq 'DOWNLOAD_MIRROR_RETRIES=3' "$INIT_SCRIPT" || \
		fail "built-in mirror retry limit is not 3"
	grep -Fq '[ "$candidate_mirror" = "custom" ] && mirror_retry_limit=1' "$INIT_SCRIPT" || \
		fail "custom mirror retry limit is not 1"
	printf 'PASS: mirror defaults, UI options, and retry limits\n'
}

test_mirror_candidates
test_custom_url_handling
test_defaults_and_retry_limits
printf 'download-mirror tests passed\n'
