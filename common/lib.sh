# Shared helpers (sourced by customize.sh and post-fs-data.sh as common.sh in the module zip).
# Device values (REQ_*, XML, patch patterns, HAS_HAL, gen_xml) live in device.sh.

# find_pat <file> <hex pattern> -> "<count> <byte offset> <byte offset> ..." (byte-aligned matches only)
find_pat() {
  od -An -v -tx1 "$1" | tr -d ' \n' | awk -v pat="$2" '
    { s = $0; p = 0
      while ((i = index(substr(s, p + 1), pat)) > 0) {
        pos = p + i
        if ((pos - 1) % 2 == 0) { n++; offs = offs " " (pos - 1) / 2 }
        p = pos
      } }
    END { print n + 0 offs }'
}

# patch_at <file> <printf octal bytes> <offset> [<offset> ...]
patch_at() {
  f=$1; b=$2; shift 2
  for o in "$@"; do printf "$b" | dd of="$f" bs=1 seek="$o" conv=notrunc 2>/dev/null || return 1; done
}

# stock_sha <file> <old bytes (octal)> <offset> [<offset> ...]: SHA-256 of the file with every patch
# site reverted to the stock bytes, so it gives the same value whether the file is stock or patched.
stock_sha() {
  t="${TMPDIR:-/data/local/tmp}/.btm_norm.$$"
  f=$1; b=$2; shift 2
  cp "$f" "$t" && patch_at "$t" "$b" "$@" && sha256sum "$t" | cut -d' ' -f1
  rm -f "$t"
}
