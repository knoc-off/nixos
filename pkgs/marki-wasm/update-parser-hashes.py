#!/usr/bin/env python3
"""
Replace placeholder sha256 hashes in parsers.nix with correct values.

Reads parsers.nix, identifies each fetchParser block by its surrounding
context (the parser/variable name), and substitutes the placeholder hash.

Usage:
    python3 update-parser-hashes.py [--dry-run]

The hash mapping is maintained inline below. To update a hash, just edit
the HASHES dict. The placeholder value is the sentinel that gets replaced.
"""
import re
import sys
from pathlib import Path

PARSERS_NIX = Path(__file__).parent / "parsers.nix"

PLACEHOLDER = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

# parser-name -> correct SRI hash (without the "sha256-" prefix being separate;
# the full string including "sha256-" is the value).
HASHES = {
    # Shared repos
    "typescript-repo": "sha256-A0M6IBoY87ekSV4DfGHDU5zzFWdLjGqSyVr6VENgA+s=",
    "markdown-repo":   "sha256-TvGTKsna1NS31/Tp9gBpndG1hNCRCEErBq1DK3pQHkU=",
    "php-repo":        "sha256-xvUUw+532j49MhEgAeEDfLo+bqN0U65s/uV9BPbsVt4=",
    # "some" group
    "bash":       "sha256-vRaN/mNfpR+hdv2HVS1bzaW0o+HGjizRFsk3iinICJE=",
    "c":          "sha256-gmzbdwvrKSo6C1fqTJFGxy8x0+T+vUTswm7F5sojzKc=",
    "cpp":        "sha256-yU1bwDhwcqeKrho0bo4qclqDDm1EuZWHENI2PNYnxVs=",
    "css":        "sha256-en379DlqzzvQNvKgE8CtiA00j7phUyipttqbnETGHKc=",
    "go":         "sha256-PgFdtkPMgkNK7Gv6dBf89lNjJrZyt9Wp5h5OIwd83aw=",
    "html":       "sha256-lNMiSDAQ49QpeyD1RzkIIUeRWdp2Wrv6+XQZdZ40c1g=",
    "java":       "sha256-fNq5MMMr83wqn7lNgj0pfSZDF4XO98YbzfNsFjr3Kpw=",
    "javascript": "sha256-X9DDCBF+gQYL0syfqgKVFvzoy2tnBl+veaYi7bUuRms=",
    "json":       "sha256-s8aAOrM4Mh4O60iSORMefN3nvFxThFk/On5DvK1BwWs=",
    "kotlin":     "sha256-CA4bfWE3YkvC4v21EXdjJ2SD7mIWJbuGpnyvRwFgm8M=",
    "lua":        "sha256-fO8XqlauYiPR0KaFzlAzvkrYXgEsiSzlB3xYzUpcbrs=",
    "python":     "sha256-t9etfZcrliF7f9hfiomh2U9P+3ufAm8iSK1y9rOhP7s=",
    "rust":       "sha256-a9Te7SXVd7hkinrpvwrWgb6J53PoSL/Irk0DpQ6vS7k=",
    "toml":       "sha256-mhoXokuSpe1PEYSrU7z0Iia7Xn26IeDAgEv+GOQnbqs=",
    "yaml":       "sha256-4XYAgMXq9AmEuejbM+y1x9oHrStxgrXlm3zg33iEvNQ=",
    # "most" group
    "asm":        "sha256-a/wbmJQFddf+19E2uHmObQ5XfUkF5iaCSI1Y8avntGw=",
    "c_sharp":    "sha256-ORhtfxQ6N72UjFx6WRfdYpkM9mVkTkxQ3PX3ydjIvX4=",
    "clojure":    "sha256-t5lLOUBgsUewnfTOIreGq83OnGNzUbl6UDDB/HCocpg=",
    "cmake":      "sha256-OxViW7H5fNc5BP072ob7GGgx1EYc6TiQEut0wHGrE1c=",
    "comment":    "sha256-O9BBcsMfIfDDzvm2eWuOhgLclUNdgZ/GsQd0kuFFFPQ=",
    "dart":       "sha256-bMFBSVAHTGstvalL5vZGahA5gL95IZQmJfBOE+trnwM=",
    "diff":       "sha256-1ibGin1e6+geAQNoV/KLCBOoXYcZo7S5+Q2XgsZPIfU=",
    "elixir":     "sha256-kMsGDHFGBclpyk9n01JJsoqInEWLEcyIUSgcWJ2Jpzk=",
    "haskell":    "sha256-0wmdbXHZbHkv4pTrB1fCbExx9E83l+zaocGa+SvQsZQ=",
    "jsdoc":      "sha256-MMLgza5H9NWYn9jtOumwg3cz3hqb8GQGFc/yRSvUIVI=",
    "json5":      "sha256-LaCCjvYnmofOVQ2Nqlzfh3KP3fNG0HBxkOng0gjYY1g=",
    "jsonc":      "sha256-iWc2ePRiQnZ0FEdMAaAwa3iYt/SY0bEjQrZyqE9EhlU=",
    "luap":       "sha256-4mMUHBsdK4U4uhh8GpKlG3p/s3ZCcLX1qATPyTD4Xhg=",
    "make":       "sha256-WiuhAp9JZKLd0wKCui9MV7AYFOW9dCbUp+kkVl1OEz0=",
    "nix":        "sha256-eqqneqZqA73McjPZfy7GbUi4ccmDYC5O++Ezt9+lqi4=",
    "printf":     "sha256-54yEvxL6u+Mya4INj1AIb1ldYv1WdQV55z8+wgKdthc=",
    "regex":      "sha256-KHPwvjqvgqLKGL/OeotF1djSSSrAsb2H3CNUmgiva18=",
    "ruby":       "sha256-84Nqw6QyGqwKAT+7Cdrzl1SikfJ3doX3tngGZWaXkVc=",
    "scala":      "sha256-ZE+zjpb52hvehJjNchJYK81XZbGAudeTRxlczuoix5g=",
    "scss":       "sha256-BFtMT6eccBWUyq6b8UXRAbB1R1XD3CrrFf1DM3aUI5c=",
    "sql":        "sha256-DSPmzoCO2jGkBeeKp2+pFlTPfrirnmMJEjRsabtDn/E=",
    "swift":      "sha256-2qUs9aTBliluKdYpgfu5WJzj2YL9e9TCi9GOI720yNQ=",
    "typst":      "sha256-s/9R3DKA6dix6BkU4mGXaVggE4bnzOyu20T1wuqHQxk=",
    "zig":        "sha256-lDMmnmeGr2ti9W692ZqySWObzSUa9vY7f+oHZiE8N+U=",
}


def update_hashes(content: str, dry_run: bool = False) -> str:
    """Walk through parsers.nix content and replace placeholder hashes."""
    lines = content.splitlines(keepends=True)
    # Track which parser/variable "block" we're inside.
    # Shared-repo vars look like:  typescript-repo = fetchParser {
    # Parser entries look like:    bash = {  ... src = fetchParser {
    current_name = None
    replaced = set()

    # Patterns to detect which block we're in
    # Shared repo:  `  typescript-repo = fetchParser {`
    shared_repo_re = re.compile(r"^\s+([\w-]+)\s*=\s*fetchParser\s*\{")
    # Parser entry:  `    bash = {`
    parser_entry_re = re.compile(r"^\s+([\w]+)\s*=\s*\{")
    # sha256 line with placeholder
    sha256_re = re.compile(
        r'^(\s*sha256\s*=\s*")' + re.escape(PLACEHOLDER) + r'(";\s*)$'
    )

    out = []
    for line in lines:
        # Check if this line starts a shared-repo variable
        m = shared_repo_re.match(line)
        if m:
            current_name = m.group(1)

        # Check if this line starts a parser entry (only inside `parsers = {`)
        m2 = parser_entry_re.match(line)
        if m2:
            candidate = m2.group(1)
            # Don't override current_name if we just matched a shared-repo line
            if candidate not in ("parsers",):
                current_name = candidate

        # Try to replace placeholder on sha256 lines
        m3 = sha256_re.match(line)
        if m3 and current_name and current_name in HASHES:
            line = m3.group(1) + HASHES[current_name] + m3.group(2)
            replaced.add(current_name)

        out.append(line)

    # Report
    missing = set(HASHES.keys()) - replaced
    if missing:
        print(f"WARNING: no placeholder found for: {', '.join(sorted(missing))}", file=sys.stderr)
    print(f"Replaced {len(replaced)}/{len(HASHES)} hashes.", file=sys.stderr)

    return "".join(out)


def main():
    dry_run = "--dry-run" in sys.argv

    content = PARSERS_NIX.read_text()
    updated = update_hashes(content, dry_run)

    if dry_run:
        print(updated)
    else:
        PARSERS_NIX.write_text(updated)
        print(f"Updated {PARSERS_NIX}", file=sys.stderr)


if __name__ == "__main__":
    main()
