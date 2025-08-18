#!/usr/bin/env zsh
# Scans repo for files >99MB, ensures they're listed at the top of .gitignore
# (under a header), and uploads newly added ones to GitHub release 1.0.0.

set -e
set -u
set -o pipefail

# --- Config ---
RELEASE_TAG="1.0.0"
HEADER="# former lfs files we are migrating to releases"
GITIGNORE=".gitignore"

# --- Ensure we're at repo root ---
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not inside a Git repository." >&2
  exit 1
fi
cd "$REPO_ROOT"

# --- Collect files >99MB (exclude .git) ---
typeset -a BIGFILES
BIGFILES=()
while IFS= read -r -d '' f; do
  # normalize to repo-relative path without leading "./"
  f="${f#./}"
  BIGFILES+=("$f")
done < <(find . -type f -size +99M -not -path "./.git/*" -print0)

if (( ${#BIGFILES[@]} == 0 )); then
  echo "No files >99MB found. Nothing to do."
  exit 0
fi

# --- Ensure .gitignore exists and HEADER is first line ---
if [[ ! -f "$GITIGNORE" ]]; then
  print -r -- "$HEADER" > "$GITIGNORE"
else
  local first_line
  first_line="$(head -n1 "$GITIGNORE" || true)"
  if [[ "$first_line" != "$HEADER" ]]; then
    local tmp
    tmp="$(mktemp)"
    {
      print -r -- "$HEADER"
      cat "$GITIGNORE"
    } > "$tmp"
    mv "$tmp" "$GITIGNORE"
  fi
fi

# --- Determine which files are NEW additions to .gitignore ---
typeset -a NEW_IGNORES
NEW_IGNORES=()
for f in "${BIGFILES[@]}"; do
  # exact-line match anywhere in .gitignore
  if ! grep -Fxq -- "$f" "$GITIGNORE"; then
    NEW_IGNORES+=("$f")
  fi
done

# --- If there are new ignores, insert them immediately under the header ---
if (( ${#NEW_IGNORES[@]} > 0 )); then
  echo "Adding ${#NEW_IGNORES[@]} new entr${${#NEW_IGNORES[@]}==1:?y:ies} to .gitignore…"
  local tmp
  tmp="$(mktemp)"
  {
    print -r -- "$HEADER"
    for f in "${NEW_IGNORES[@]}"; do
      print -r -- "$f"
    done
    # append prior content starting from line 2 (skip the existing header)
    tail -n +2 "$GITIGNORE" 2>/dev/null || true
  } > "$tmp"
  mv "$tmp" "$GITIGNORE"
else
  echo "All >99MB files already listed in .gitignore."
fi

# --- Publish newly added files to release tag 1.0.0 ---
if (( ${#NEW_IGNORES[@]} > 0 )); then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI (gh) not found. Install it and run 'gh auth login'." >&2
    exit 1
  fi

  # Create the release if it doesn't exist
  if ! gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    echo "Creating release ${RELEASE_TAG}…"
    gh release create "$RELEASE_TAG" --title "$RELEASE_TAG" --notes "Initial auto-publish of large assets"
  fi

  echo "Uploading new files to release ${RELEASE_TAG}…"
  # Pass each file as a separate arg to handle spaces safely
  gh release upload "$RELEASE_TAG" "${NEW_IGNORES[@]}"
fi

echo "Done."
echo "Newly added to .gitignore: ${#NEW_IGNORES[@]}"
for f in "${NEW_IGNORES[@]}"; do
  echo "  - $f"
done

echo
echo "Reminder: commit & push the updated .gitignore if desired:"
echo "  git add .gitignore && git commit -m \"Update .gitignore for large assets\" && git push"