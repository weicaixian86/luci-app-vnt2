#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="${ROOT_DIR}/luci-app-vnt2/root/etc/init.d/vnt2"
WORKER_INIT_SCRIPT="${ROOT_DIR}/luci-app-vnt2/root/etc/init.d/vnt2-worker"
WORKER_SCRIPT="${ROOT_DIR}/luci-app-vnt2/root/usr/libexec/vnt2/restart-worker"
PACKAGE_MAKEFILE="${ROOT_DIR}/luci-app-vnt2/Makefile"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

function_definition() {
	name="$1"
	awk -v signature="${name}() {" '
		$0 == signature { copying = 1 }
		copying { print }
		copying && $0 == "}" { exit }
	' "$INIT_SCRIPT"
}

load_function() {
	name="$1"
	definition="$(function_definition "$name")"
	[ -n "$definition" ] || fail "function ${name} was not found"
	eval "$definition"
}

test_reload_only_queues_marker() {
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT INT TERM

	reload_definition="$(function_definition reload_service)"
	schedule_definition="$(function_definition schedule_restart)"
	[ -n "$reload_definition" ] || fail "reload_service was not found"
	[ -n "$schedule_definition" ] || fail "schedule_restart was not found"

	if printf '%s\n%s\n' "$reload_definition" "$schedule_definition" | grep -Eq '(^|[[:space:]])sleep([[:space:]]|$)'; then
		fail "reload path contains sleep"
	fi
	if printf '%s\n%s\n' "$reload_definition" "$schedule_definition" | grep -Fq '/etc/init.d/vnt2 restart'; then
		fail "reload path directly restarts vnt2"
	fi
	if printf '%s\n%s\n' "$reload_definition" "$schedule_definition" | grep -Eq '(^|[[:space:]])&([[:space:]]|$)'; then
		fail "reload path creates a background process"
	fi

	load_function schedule_restart
	load_function reload_service
	RESTART_PENDING_FILE="$dir/vnt2-restart.pending"
	reload_service
	[ -s "$RESTART_PENDING_FILE" ] || fail "reload did not create the pending marker"
	case "$(sed -n '1p' "$RESTART_PENDING_FILE")" in
		''|*[!0-9]*) fail "pending marker does not contain a timestamp" ;;
	esac
	[ "$(find "$dir" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 1 ] || fail "reload left a temporary marker behind"

	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: reload only writes the restart marker\n'
}

test_worker_package_lifecycle() {
	grep -Fq 'START=98' "$WORKER_INIT_SCRIPT" || fail "worker does not start before the main service"
	grep -Fq 'START=99' "$INIT_SCRIPT" || fail "main service start priority changed unexpectedly"
	grep -Fq 'RESTART_DELAY="${VNT2_RESTART_DELAY:-15}"' "$WORKER_SCRIPT" || fail "worker debounce is not 15 seconds"

	for path in \
		'/etc/init.d/vnt2' \
		'/etc/init.d/vnt2-worker' \
		'/usr/libexec/vnt2/restart-worker'
	do
		grep -Fq "$path" "$PACKAGE_MAKEFILE" || fail "package lifecycle omits $path"
	done
	grep -Fq '/etc/init.d/vnt2-worker enable' "$PACKAGE_MAKEFILE" || fail "postinst does not enable the worker"
	grep -Fq '/etc/init.d/vnt2-worker restart' "$PACKAGE_MAKEFILE" || fail "postinst does not start the worker"
	grep -Fq '/etc/init.d/vnt2-worker stop' "$PACKAGE_MAKEFILE" || fail "prerm does not stop the worker"
	grep -Fq '/etc/init.d/vnt2-worker disable' "$PACKAGE_MAKEFILE" || fail "prerm does not disable the worker"

	printf 'PASS: package installs and manages the restart worker\n'
}

test_apply_stop_keeps_network() {
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT INT TERM
	calls="$dir/calls"

	load_function stop_service
	ensure_log_files() { :; }
	log_cli() { :; }
	log_web() { :; }
	log_server() { :; }
	log_download() { :; }
	cleanup_network() { printf '%s\n' cleanup_network >>"$calls"; }
	cleanup_web_firewall() { printf '%s\n' cleanup_web_firewall >>"$calls"; }
	cleanup_server_firewall() { printf '%s\n' cleanup_server_firewall >>"$calls"; }
	CLI_TIME="$dir/cli-time"
	WEB_TIME="$dir/web-time"
	SERVER_TIME="$dir/server-time"

	VNT2_RESTART_MODE=apply
	stop_service
	[ ! -s "$calls" ] || fail "apply stop invoked network or firewall cleanup"

	unset VNT2_RESTART_MODE
	stop_service
	[ "$(wc -l <"$calls" | tr -d ' ')" -eq 3 ] || fail "normal stop did not invoke all cleanup functions"

	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: apply stop preserves network and normal stop cleans it\n'
}

test_idempotent_uci_helpers() {
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT INT TERM
	calls="$dir/calls"

	load_function uci_set_if_changed
	load_function uci_delete_if_exists

	uci() {
		if [ "${1:-}" = "-q" ]; then
			shift
		fi
		command="$1"
		shift
		case "$command" in
			get)
				key="$(printf '%s' "$1" | tr '.[]' '___')"
				[ -f "$dir/$key" ] || return 1
				cat "$dir/$key"
			;;
			set)
				assignment="$1"
				key="${assignment%%=*}"
				value="${assignment#*=}"
				key="$(printf '%s' "$key" | tr '.[]' '___')"
				printf '%s\n' "$value" >"$dir/$key"
				printf '%s\n' set >>"$calls"
			;;
			delete)
				key="$(printf '%s' "$1" | tr '.[]' '___')"
				rm -f "$dir/$key"
				printf '%s\n' delete >>"$calls"
			;;
			*)
				return 1
			;;
		esac
	}

	printf '%s\n' interface >"$dir/network_VNT2"
	uci_set_if_changed network.VNT2 interface
	[ ! -s "$calls" ] || fail "unchanged UCI value was rewritten"

	uci_set_if_changed network.VNT2 bridge
	[ "$(grep -c '^set$' "$calls" || true)" -eq 1 ] || fail "changed UCI value was not written exactly once"

	uci_delete_if_exists firewall.missing
	[ "$(grep -c '^delete$' "$calls" || true)" -eq 0 ] || fail "missing UCI section was deleted"

	printf '%s\n' rule >"$dir/firewall_vnt2web"
	uci_delete_if_exists firewall.vnt2web
	[ "$(grep -c '^delete$' "$calls" || true)" -eq 1 ] || fail "existing UCI section was not deleted exactly once"

	rm -rf "$dir"
	trap - EXIT INT TERM
	printf 'PASS: unchanged UCI state produces no write\n'
}

test_reload_only_queues_marker
test_worker_package_lifecycle
test_apply_stop_keeps_network
test_idempotent_uci_helpers
printf 'init-service tests passed\n'
