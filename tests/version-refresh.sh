#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONTROLLER="${ROOT_DIR}/luci-app-vnt2web/luasrc/controller/vnt2.lua"
STATUS_VIEW="${ROOT_DIR}/luci-app-vnt2web/luasrc/view/vnt2/vnt2_status.htm"
INIT_SCRIPT="${ROOT_DIR}/luci-app-vnt2web/root/etc/init.d/vnt2"
WORKER="${ROOT_DIR}/luci-app-vnt2web/root/usr/libexec/vnt2/version-worker"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

lua_function() {
	name="$1"
	awk -v signature="function ${name}()" '
		index($0, signature) == 1 { copying = 1; found = 1 }
		copying && found && index($0, signature) != 1 && $0 ~ /^(local )?function / { exit }
		copying { print }
	' "$CONTROLLER"
}

shell_function() {
	name="$1"
	awk -v signature="${name}() {" '
		$0 == signature { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "$INIT_SCRIPT"
}

load_shell_function() {
	name="$1"
	definition="$(shell_function "$name")"
	[ -n "$definition" ] || fail "function ${name} was not found"
	eval "$definition"
}

test_luci_request_is_local_only() {
	definition="$(lua_function act_check_latest)"
	[ -n "$definition" ] || fail "act_check_latest was not found"
	printf '%s\n' "$definition" | grep -Fq 'VERSION_CHECK_PENDING_FILE' || \
		fail "latest-version request does not write the pending marker"
	printf '%s\n' "$definition" | grep -Fq 'os.rename(temp, VERSION_CHECK_PENDING_FILE)' || \
		fail "latest-version request does not atomically replace the pending marker"
	if printf '%s\n' "$definition" | grep -Fq 'fs.writefile(VERSION_CHECK_PENDING_FILE'; then
		fail "latest-version request has a non-atomic direct-write fallback"
	fi
	if printf '%s\n' "$definition" | grep -Eq 'sys\.(call|exec)|curl|wget|uclient-fetch|/etc/init\.d/vnt2'; then
		fail "latest-version LuCI request performs synchronous external work"
	fi
	grep -Fq 'XHR.get(checkLatestUrl' "$STATUS_VIEW" || \
		fail "status page does not queue a latest-version refresh"
	grep -Fq 'text(data.latest_web_tag)' "$STATUS_VIEW" || \
		fail "Web status does not display its own latest-version cache"
	grep -Fq 'e.latest_web_tag = get_vnt2_latest_tag(web_cfg.download_repo' "$CONTROLLER" || \
		fail "controller does not read the Web section latest-version cache"
	printf 'PASS: page load only queues the latest-version worker\n'
}

test_local_version_state() {
	grep -Fq 'local VERSION_STATE_FILE = "/etc/config/vnt2-web.version"' "$CONTROLLER" || \
		fail "controller does not read the version sidecar"
	grep -Fq 'local function parse_version_state(path)' "$CONTROLLER" || \
		fail "controller does not parse the version sidecar"
	grep -Fq 'local function get_local_tag(bin_path)' "$CONTROLLER" || \
		fail "local version helper does not validate against the version sidecar"
	grep -Fq 'e.web_tag = get_local_tag(get_web_bin())' "$CONTROLLER" || \
		fail "status endpoint does not resolve the local version from the sidecar"
	grep -Fq 'state.path ~= bin_path' "$CONTROLLER" || \
		fail "local version helper does not reject a sidecar for a different path"
	grep -Fq 'stat_value_matches(stat.size, state.size)' "$CONTROLLER" || \
		fail "local version helper does not verify the recorded size"
	grep -Fq 'stat_value_matches(stat.mtime, state.mtime)' "$CONTROLLER" || \
		fail "local version helper does not verify the recorded mtime"
	grep -Fq 'VERSION_STATE_FILE="/etc/config/vnt2-web.version"' "$INIT_SCRIPT" || \
		fail "init script does not define the version sidecar path"
	grep -Fq 'write_version_state()' "$INIT_SCRIPT" || \
		fail "init script does not write the version sidecar"
	grep -Fq 'clear_version_state()' "$INIT_SCRIPT" || \
		fail "init script does not clear the version sidecar"
	if grep -Fq 'fallback_state' "$CONTROLLER"; then
		fail "local version helper still depends on a removed fallback tool state"
	fi
	printf 'PASS: local version is validated against the version sidecar\n'
}

test_release_refresh_path() {
	definition="$(shell_function refresh_latest_version_for_section)"
	[ -n "$definition" ] || fail "refresh_latest_version_for_section was not found"
	printf '%s\n' "$definition" | grep -Fq 'get_download_mirror_candidates' || \
		fail "latest-version refresh does not use configured mirror candidates"
	printf '%s\n' "$definition" | grep -Fq 'fetch_release_metadata_from_mirror "$repo" "latest"' || \
		fail "latest-version refresh does not query the latest Release interface"
	printf '%s\n' "$definition" | grep -Fq 'write_latest_release_cache' || \
		fail "latest-version refresh does not update the local cache"
	printf '%s\n' "$definition" | grep -Fq '"$release_tag" "latest"' || \
		fail "latest-version refresh does not identify its cache as a latest query"
	grep -Fq '[ "$cache_scope" = "latest" ] || return 0' "$INIT_SCRIPT" || \
		fail "fixed-tag downloads are not excluded from latest-version cache writes"
	grep -Fq 'fallback:*) ;;' "$INIT_SCRIPT" || \
		fail "built-in fallback metadata is not excluded from latest-version cache writes"
	grep -Fq 'vnt2_latest_v3_' "$CONTROLLER" || fail "controller does not read the canonical latest cache"
	grep -Fq 'vnt2_latest_v3_' "$INIT_SCRIPT" || fail "init script does not write the canonical latest cache"
	if grep -Fq 'vnt2_latest_v2_' "$CONTROLLER"; then
		fail "controller still reads legacy caches that may contain a fixed download tag"
	fi
	grep -Fq 'refresh_latest_versions </dev/null >/dev/null 2>&1' "$WORKER" || \
		fail "version worker does not run independently from LuCI"
	printf 'PASS: worker queries latest Releases through configured mirrors and caches tags\n'
}

test_latest_cache_scope() {
	repo="version-refresh-test-$$/repo"
	cache_key="auto_github_${repo}"
	canonical_key="auto_${repo}"
	legacy_cache="/tmp/vnt2_latest_v2_$(printf '%s' "$cache_key" | sed 's/[^A-Za-z0-9._-]/_/g').tag"
	canonical_cache="/tmp/vnt2_latest_v3_$(printf '%s' "$canonical_key" | sed 's/[^A-Za-z0-9._-]/_/g').tag"
	trap 'rm -f "$legacy_cache" "$canonical_cache"' EXIT INT TERM

	load_shell_function trim_value
	load_shell_function sanitize_name
	load_shell_function normalize_release_tag
	load_shell_function normalize_download_mirror
	load_shell_function normalize_custom_mirror_url
	load_shell_function repo_to_mirror_project
	load_shell_function write_latest_release_cache

	write_latest_release_cache auto github "$repo" "" 1.2.3 fixed
	[ ! -e "$legacy_cache" ] || fail "fixed download tag wrote the legacy latest cache"
	[ ! -e "$canonical_cache" ] || fail "fixed download tag wrote the canonical latest cache"

	write_latest_release_cache auto github "$repo" "" 2.0.9 latest
	[ "$(cat "$legacy_cache")" = "2.0.9" ] || fail "latest query did not write the candidate cache"
	[ "$(cat "$canonical_cache")" = "2.0.9" ] || fail "latest query did not write the canonical cache"

	rm -f "$legacy_cache" "$canonical_cache"
	trap - EXIT INT TERM
	printf 'PASS: only successful latest queries update latest-version caches\n'
}

test_luci_request_is_local_only
test_local_version_state
test_release_refresh_path
test_latest_cache_scope
printf 'version-refresh tests passed\n'
