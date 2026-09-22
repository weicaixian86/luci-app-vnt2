#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORKER="${ROOT_DIR}/luci-app-vnt2web/root/usr/libexec/vnt2/restart-worker"

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

test_debounce() {
	dir="$(mktemp -d)"
	trap 'stop_worker "$dir"; rm -rf "$dir"' EXIT INT TERM

	VNT2_RESTART_PENDING_FILE="$dir/pending" \
	VNT2_RESTART_CLAIMED_FILE="$dir/claimed" \
	VNT2_RESTART_LOG_FILE="$dir/log" \
	VNT2_RESTART_COMMAND=/usr/bin/true \
	VNT2_RESTART_DELAY=2 \
	VNT2_RESTART_POLL_INTERVAL=1 \
		sh "$WORKER" &
	echo "$!" >"$dir/pid"

	date +%s >"$dir/pending"
	sleep 1
	date +%s >"$dir/pending"
	sleep 5

	starts="$(grep -c 'worker starts queued restart' "$dir/log" || true)"
	completed="$(grep -c 'worker completed queued restart' "$dir/log" || true)"
	[ "$starts" -eq 1 ] || fail "debounce started $starts restarts"
	[ "$completed" -eq 1 ] || fail "debounce completed $completed restarts"
	[ ! -e "$dir/pending" ] || fail "debounce left a pending marker"
	[ ! -e "$dir/claimed" ] || fail "debounce left a claimed marker"

	stop_worker "$dir"
	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: repeated requests were merged\n'
}

test_request_during_restart() {
	dir="$(mktemp -d)"
	trap 'stop_worker "$dir"; rm -rf "$dir"' EXIT INT TERM

cat >"$dir/mock-restart" <<'EOF'
#!/bin/sh
printf '%s\n' "${VNT2_RESTART_MODE:-}" >"$MOCK_STATE_DIR/mode"
count="$(cat "$MOCK_STATE_DIR/count" 2>/dev/null || printf '0')"
count=$((count + 1))
printf '%s\n' "$count" >"$MOCK_STATE_DIR/count"
touch "$MOCK_STATE_DIR/entered"
sleep 2
EOF
	chmod 0755 "$dir/mock-restart"

	MOCK_STATE_DIR="$dir" \
	VNT2_RESTART_PENDING_FILE="$dir/pending" \
	VNT2_RESTART_CLAIMED_FILE="$dir/claimed" \
	VNT2_RESTART_LOG_FILE="$dir/log" \
	VNT2_RESTART_COMMAND="$dir/mock-restart" \
	VNT2_RESTART_DELAY=1 \
	VNT2_RESTART_POLL_INTERVAL=1 \
		sh "$WORKER" &
	echo "$!" >"$dir/pid"

	date +%s >"$dir/pending"
	remaining=10
	while [ ! -f "$dir/entered" ] && [ "$remaining" -gt 0 ]; do
		sleep 1
		remaining=$((remaining - 1))
	done
	[ -f "$dir/entered" ] || fail "first restart did not begin"
	mode="$(cat "$dir/mode" 2>/dev/null || true)"
	[ "$mode" = "apply" ] || fail "restart mode was not isolated from normal stop cleanup"

	date +%s >"$dir/pending"
	wait_for_count "$dir/count" 2 10 || fail "request received during restart was lost"
	sleep 3

	starts="$(grep -c 'worker starts queued restart' "$dir/log" || true)"
	completed="$(grep -c 'worker completed queued restart' "$dir/log" || true)"
	[ "$starts" -eq 2 ] || fail "expected 2 starts, got $starts"
	[ "$completed" -eq 2 ] || fail "expected 2 completions, got $completed"
	[ ! -e "$dir/pending" ] || fail "second run left a pending marker"
	[ ! -e "$dir/claimed" ] || fail "second run left a claimed marker"

	stop_worker "$dir"
	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: a request received during restart was retained\n'
}

test_debounce
test_request_during_restart
printf 'restart-worker tests passed\n'
