#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACKAGE_NAME="${PACKAGE_NAME:-luci-app-vnt2web}"
SOURCE_DIR=""
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

resolve_source_dir() {
	if [ -n "${APP_SOURCE_DIR:-}" ]; then
		case "$APP_SOURCE_DIR" in
			/*)
				SOURCE_DIR="$APP_SOURCE_DIR"
			;;
			*)
				SOURCE_DIR="${ROOT_DIR}/${APP_SOURCE_DIR}"
			;;
		esac
	else
		source_makefile="$(
			find "$ROOT_DIR" -type f -name Makefile -print | LC_ALL=C sort |
			while IFS= read -r makefile; do
				if grep -Eq "^[[:space:]]*PKG_NAME[[:space:]]*:=[[:space:]]*${PACKAGE_NAME}[[:space:]]*$" "$makefile"; then
					printf '%s\n' "$makefile"
					break
				fi
			done
		)"
		[ -n "$source_makefile" ] || fail "unable to locate ${PACKAGE_NAME}/Makefile"
		SOURCE_DIR="${source_makefile%/Makefile}"
	fi

	[ -d "$SOURCE_DIR" ] || fail "package source directory does not exist: ${SOURCE_DIR}"
	[ -f "$SOURCE_DIR/Makefile" ] || fail "package Makefile does not exist: ${SOURCE_DIR}/Makefile"
	grep -Eq "^[[:space:]]*PKG_NAME[[:space:]]*:=[[:space:]]*${PACKAGE_NAME}[[:space:]]*$" "$SOURCE_DIR/Makefile" ||
		fail "unexpected package name in ${SOURCE_DIR}/Makefile"
	printf 'Using package source directory: %s\n' "${SOURCE_DIR#${ROOT_DIR}/}"
}

check_project_contracts() {
	legacy_pattern='vnt2[_-](cli|ctrl)|vnts2'
	legacy_matches="$(
		grep -REIl --exclude=validate-source.sh "$legacy_pattern" \
			"$SOURCE_DIR" "${ROOT_DIR}/tests" "${ROOT_DIR}/.github" "${ROOT_DIR}/README.md" 2>/dev/null || true
	)"
	if [ -n "$legacy_matches" ]; then
		printf '%s\n' "$legacy_matches" >&2
		fail "removed component references were found"
	fi

	grep -Fq 'PKG_NAME:=luci-app-vnt2web' "$SOURCE_DIR/Makefile" ||
		fail "package name is not luci-app-vnt2web"
	grep -Fq 'PKG_VERSION:=2.0.53' "$SOURCE_DIR/Makefile" ||
		fail "package version is not 2.0.53"
	grep -Fq 'PKG_RELEASE:=2' "$SOURCE_DIR/Makefile" ||
		fail "package release is not 2"
	grep -Fq 'WEB_CONF_DEFAULT="/etc/config/vnt2.toml"' "$SOURCE_DIR/root/etc/init.d/vnt2" ||
		fail "runtime TOML path is not fixed in the init script"
	grep -Fq 'M.TOML_FILE = "/etc/config/vnt2.toml"' "$SOURCE_DIR/luasrc/model/vnt2_toml.lua" ||
		fail "runtime TOML path is not fixed in the Lua TOML module"
	if grep -Fq 'web_conf_file' \
		"$SOURCE_DIR/root/etc/config/vnt2" \
		"$SOURCE_DIR/root/etc/init.d/vnt2" \
		"$SOURCE_DIR/luasrc/model/vnt2_toml.lua"; then
		fail "runtime TOML path remains configurable through UCI"
	fi

	workflow="${WORKFLOW_DIR}/build.yml"
	[ -f "$workflow" ] || fail "build workflow is missing"
	grep -Fq 'workflow_dispatch:' "$workflow" ||
		fail "build workflow is not manually triggered"
	grep -Fq "printf '编译时间: %s\\n'" "$workflow" ||
		fail "release body does not contain the expected build time label"
	printf 'PASS: package identity, fixed TOML path, and removed-component checks passed\n'
}

check_line_endings() {
	cr="$(printf '\r')"
	{
		find "$SOURCE_DIR" "${ROOT_DIR}/tests" "${ROOT_DIR}/.github" -type f -print
		printf '%s\n' "${ROOT_DIR}/README.md" "${ROOT_DIR}/.gitattributes"
	} | LC_ALL=C sort | while IFS= read -r file; do
		[ -f "$file" ] || continue
		if LC_ALL=C grep -q "$cr" "$file"; then
			printf 'FAIL: CRLF line ending found: %s\n' "$file" >&2
			exit 1
		fi
	done
	printf 'PASS: project source files use LF line endings\n'
}

check_shell_syntax() {
	find "$SOURCE_DIR" "${ROOT_DIR}/tests" -type f -print | LC_ALL=C sort |
	while IFS= read -r script; do
		first_line="$(sed -n '1p' "$script" || true)"
		case "$first_line" in
			'#!'*'sh'*)
				dash -n "$script"
			;;
		esac
	done
	printf 'PASS: all Shell scripts pass dash -n\n'
}

run_tests() {
	for test_script in "${ROOT_DIR}"/tests/*.sh; do
		[ -f "$test_script" ] || continue
		[ "$test_script" != "${ROOT_DIR}/tests/validate-source.sh" ] || continue
		printf 'Running %s\n' "${test_script#${ROOT_DIR}/}"
		sh "$test_script"
	done
	printf 'PASS: all automated tests passed\n'
}

find_lua_compiler() {
	for candidate in luac5.1 luac; do
		command -v "$candidate" >/dev/null 2>&1 || continue
		version="$("$candidate" -v 2>&1 || true)"
		case "$version" in
			*5.1*)
				printf '%s\n' "$candidate"
				return 0
			;;
		esac
	done
	return 1
}

check_lua_syntax() {
	lua_compiler="$(find_lua_compiler || true)"
	find "$SOURCE_DIR" -type f -name '*.lua' -print | LC_ALL=C sort |
	while IFS= read -r lua_file; do
		if [ -n "$lua_compiler" ]; then
			"$lua_compiler" -p "$lua_file"
		elif command -v node >/dev/null 2>&1 && \
			node -e 'require("luaparse")' >/dev/null 2>&1; then
			node -e '
				const fs = require("fs");
				const luaparse = require("luaparse");
				luaparse.parse(fs.readFileSync(process.argv[1], "utf8"), { luaVersion: "5.1" });
			' "$lua_file"
		else
			fail "luac5.1 or Node luaparse is required for Lua 5.1 validation"
		fi
	done
	printf 'PASS: all Lua files parse as Lua 5.1\n'
}

check_yaml_syntax() {
	workflow_found=0
	for workflow in "${WORKFLOW_DIR}"/*.yml "${WORKFLOW_DIR}"/*.yaml; do
		[ -f "$workflow" ] || continue
		workflow_found=1
		if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
			python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$workflow"
		elif command -v node >/dev/null 2>&1 && \
			node -e 'require("yaml")' >/dev/null 2>&1; then
			node -e '
				const fs = require("fs");
				const YAML = require("yaml");
				YAML.parse(fs.readFileSync(process.argv[1], "utf8"));
			' "$workflow"
		else
			fail "python3 PyYAML or Node yaml is required for YAML validation"
		fi
	done
	[ "$workflow_found" -eq 1 ] || fail "no GitHub Actions workflow file was found"
	printf 'PASS: all workflow YAML files parse successfully\n'
}

check_utf8_and_bom() {
	input_files() {
		find "$SOURCE_DIR" "${ROOT_DIR}/tests" "${ROOT_DIR}/.github" -type f -print
		printf '%s\n' "${ROOT_DIR}/README.md"
	}

	if command -v python3 >/dev/null 2>&1; then
		input_files | LC_ALL=C sort | python3 -c '
			import codecs
			import os
			import sys

			for raw_path in sys.stdin.buffer:
				path = os.fsdecode(raw_path.rstrip(b"\n"))
				with open(path, "rb") as handle:
					data = handle.read()
				if data.startswith(codecs.BOM_UTF8):
					raise SystemExit("UTF-8 BOM found: " + path)
				try:
					data.decode("utf-8")
				except UnicodeDecodeError as error:
					raise SystemExit("Invalid UTF-8 in {}: {}".format(path, error))
		'
	elif command -v perl >/dev/null 2>&1; then
		input_files | LC_ALL=C sort | perl -MEncode=decode -e '
			while (defined(my $path = <STDIN>)) {
				chomp $path;
				open(my $handle, "<:raw", $path) or die "open failed: $path: $!\n";
				local $/;
				my $data = <$handle>;
				close($handle);
				die "UTF-8 BOM found: $path\n"
					if substr($data, 0, 3) eq "\xEF\xBB\xBF";
				eval { decode("UTF-8", $data, 1); 1 }
					or die "Invalid UTF-8 in $path: $@\n";
			}
		'
	else
		fail "python3 or perl is required for UTF-8 and BOM validation"
	fi
	printf 'PASS: project text files are UTF-8 without BOM\n'
}

resolve_source_dir
check_project_contracts
check_line_endings
check_shell_syntax
run_tests
check_lua_syntax
check_yaml_syntax
check_utf8_and_bom
(
	cd "$ROOT_DIR"
	git diff --check
)
printf 'PASS: git diff --check passed\n'

printf 'source validation passed\n'
