#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORKER="${ROOT_DIR}/luci-app-vnt2web/root/usr/libexec/vnt2/version-worker"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

stop_worker() {
	if [ -f "$1/pid" ]; then
		kill "$(cat "$1/pid")" 2>/dev/null || true
		wait "$(cat "$1/pid")" 2>/dev/null || true
	fi
}

wait_for_count() {
	file="$1"
	wanted="$2"
	remaining="${3:-10}"

	while [ "$remaining" -gt 0 ]; do
		count="$(cat "$file" 2>/dev/null || printf '0')"
		[ "$count" -ge "$wanted" ] && return 0
		sleep 1
		remaining=$((remaining - 1))
	done
	return 1
}

make_mock_check() {
	dir="$1"
	cat >"$dir/mock-check" <<'EOF'
#!/bin/sh
[ "${1:-}" = "refresh_latest_versions" ] || exit 2
count="$(cat "$MOCK_STATE_DIR/count" 2>/dev/null || printf '0')"
count=$((count + 1))
printf '%s\n' "$count" >"$MOCK_STATE_DIR/count"
touch "$MOCK_STATE_DIR/entered"
sleep "${MOCK_CHECK_DELAY:-0}"
EOF
	chmod 0755 "$dir/mock-check"
}

start_worker() {
	dir="$1"
	check_delay="$2"
	debounce_delay="$3"
	MOCK_STATE_DIR="$dir" \
	MOCK_CHECK_DELAY="$check_delay" \
	VNT2_VERSION_PENDING_FILE="$dir/pending" \
	VNT2_VERSION_CLAIMED_FILE="$dir/claimed" \
	VNT2_VERSION_LOG_FILE="$dir/log" \
	VNT2_VERSION_CHECK_COMMAND="$dir/mock-check" \
	VNT2_VERSION_DELAY="$debounce_delay" \
	VNT2_VERSION_POLL_INTERVAL=1 \
		sh "$WORKER" &
	echo "$!" >"$dir/pid"
}

test_repeated_requests_merge() {
	dir="$(mktemp -d)"
	trap 'stop_worker "$dir"; rm -rf "$dir"' EXIT INT TERM
	make_mock_check "$dir"
	start_worker "$dir" 0 2

	date +%s >"$dir/pending"
	sleep 1
	date +%s >"$dir/pending"
	wait_for_count "$dir/count" 1 10 || fail "merged version check did not run"
	sleep 3

	[ "$(cat "$dir/count")" -eq 1 ] || fail "repeated page loads started more than one version check"
	[ ! -e "$dir/pending" ] || fail "merged check left a pending marker"
	[ ! -e "$dir/claimed" ] || fail "merged check left a claimed marker"

	stop_worker "$dir"
	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: repeated page-load requests were merged\n'
}

test_request_during_check_is_retained() {
	dir="$(mktemp -d)"
	trap 'stop_worker "$dir"; rm -rf "$dir"' EXIT INT TERM
	make_mock_check "$dir"
	start_worker "$dir" 2 1

	date +%s >"$dir/pending"
	remaining=10
	while [ ! -f "$dir/entered" ] && [ "$remaining" -gt 0 ]; do
		sleep 1
		remaining=$((remaining - 1))
	done
	[ -f "$dir/entered" ] || fail "first version check did not begin"

	date +%s >"$dir/pending"
	wait_for_count "$dir/count" 2 12 || fail "request received during version check was lost"
	sleep 3

	[ "$(cat "$dir/count")" -eq 2 ] || fail "expected exactly two version checks"
	[ ! -e "$dir/pending" ] || fail "second check left a pending marker"
	[ ! -e "$dir/claimed" ] || fail "second check left a claimed marker"

	stop_worker "$dir"
	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: request received during a version check was retained\n'
}

test_repeated_requests_merge
test_request_during_check_is_retained
printf 'version-worker tests passed\n'
