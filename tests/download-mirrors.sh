#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="${ROOT_DIR}/luci-app-vnt2web/root/etc/init.d/vnt2"
CBI_SCRIPT="${ROOT_DIR}/luci-app-vnt2web/luasrc/model/cbi/vnt2.lua"
DEFAULT_CONFIG="${ROOT_DIR}/luci-app-vnt2web/root/etc/config/vnt2"

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
	[ "$(grep -c "option download_mirror 'auto'" "$DEFAULT_CONFIG")" -eq 1 ] || \
		fail "Web default is not auto"
	grep -Fq 'option:value("auto", translate("自动"))' "$CBI_SCRIPT" || \
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

test_release_tag_matching() {
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT INT TERM
	definition="$(awk '
		/^extract_release_object_by_tag\(\) \{/ { copying = 1 }
		/^fetch_release_metadata_from_mirror\(\) \{/ { exit }
		copying { print }
	' "$INIT_SCRIPT")"
	[ -n "$definition" ] || fail "extract_release_object_by_tag was not found"
	eval "$definition"

	cat >"$dir/releases.json" <<'EOF'
[
  {"tag_name":"v2.0.53","assets":[{"name":"current"}]},
  {"tag_name":"2.0.52","assets":[{"name":"previous"}]}
]
EOF
	extract_release_object_by_tag "$dir/releases.json" "$dir/matched.json" "2.0.53" || \
		fail "normalized tag did not match a v-prefixed release"
	grep -Fq '"tag_name":"v2.0.53"' "$dir/matched.json" || fail "wrong release object was selected"

	extract_release_object_by_tag "$dir/releases.json" "$dir/matched.json" "v2.0.52" || \
		fail "v-prefixed requested tag did not match a normalized release"
	grep -Fq '"tag_name":"2.0.52"' "$dir/matched.json" || fail "wrong normalized release object was selected"

	if extract_release_object_by_tag "$dir/releases.json" "$dir/matched.json" "2.0.5"; then
		fail "partial release tag matched unexpectedly"
	fi

	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: release list tag matching normalizes only the v prefix\n'
}

test_download_timeouts_and_archive_checks() {
	download_definition="$(awk '
		/^download_file\(\) \{/ { copying = 1 }
		copying { print }
		copying && /^}$/ { exit }
	' "$INIT_SCRIPT")"
	printf '%s\n' "$download_definition" | grep -Fq 'connect_timeout=10' || fail "API connect timeout is not bounded"
	printf '%s\n' "$download_definition" | grep -Fq 'transfer_timeout=30' || fail "API transfer timeout is not bounded"
	printf '%s\n' "$download_definition" | grep -Fq 'transfer_timeout=600' || fail "asset transfer timeout changed unexpectedly"
	grep -Fq 'archive_is_safe "$asset_file" || return 1' "$INIT_SCRIPT" || fail "release extraction bypasses archive safety checks"
	printf 'PASS: API timeouts and release archive checks are enabled\n'
}

test_archive_safety() {
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT INT TERM
	definition="$(awk '
		/^archive_paths_are_safe\(\) \{/ { copying = 1 }
		/^validate_asset_file\(\) \{/ { exit }
		copying { print }
	' "$INIT_SCRIPT")"
	[ -n "$definition" ] || fail "archive safety functions were not found"
	eval "$definition"

	mkdir -p "$dir/source"
	printf 'binary\n' >"$dir/source/vnt2_web"
	tar -czf "$dir/safe.tar.gz" -C "$dir/source" vnt2_web
	archive_is_safe "$dir/safe.tar.gz" || fail "safe tar archive was rejected"

	tar -czf "$dir/traversal.tar.gz" -C "$dir/source" --transform='s#vnt2_web#../vnt2_web#' vnt2_web 2>/dev/null
	if archive_is_safe "$dir/traversal.tar.gz"; then
		fail "tar archive containing parent traversal was accepted"
	fi

	ln -s vnt2_web "$dir/source/vnt2_link"
	if [ -L "$dir/source/vnt2_link" ]; then
		tar -czf "$dir/link.tar.gz" -C "$dir/source" vnt2_link
		if archive_is_safe "$dir/link.tar.gz"; then
			fail "tar archive containing a symbolic link was accepted"
		fi
	fi

	if mkfifo "$dir/source/vnt2_fifo" 2>/dev/null; then
		tar -czf "$dir/special.tar.gz" -C "$dir/source" vnt2_fifo
		if archive_is_safe "$dir/special.tar.gz"; then
			fail "tar archive containing a special file was accepted"
		fi
	fi

	printf 'not an archive\n' >"$dir/broken.tar.gz"
	if archive_is_safe "$dir/broken.tar.gz"; then
		fail "corrupted tar archive was accepted"
	fi

	if [ -n "${VNT2_TEST_RELEASE_ARCHIVE:-}" ]; then
		[ -f "$VNT2_TEST_RELEASE_ARCHIVE" ] || fail "real Release archive does not exist"
		archive_is_safe "$VNT2_TEST_RELEASE_ARCHIVE" || fail "real Release archive was rejected"
		printf 'PASS: real Release archive passed project safety checks\n'
	fi

	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: release archive path and link protections reject unsafe input\n'
}

test_mirror_candidates
test_custom_url_handling
test_defaults_and_retry_limits
test_release_tag_matching
test_download_timeouts_and_archive_checks
test_archive_safety
printf 'download-mirror tests passed\n'
