#!/usr/bin/env bash
# 88API-image-gen multi-client installer (macOS / Linux).
#
# Links the shared skill into every detected AI client and copies the Hermes
# desktop panel when Hermes is present. The core script generate.mjs is never
# copied; all clients run it from this repository checkout.
#
# Usage:
#   bash install.sh                 # install into every detected client
#   bash install.sh --target claude # only one of: claude | cursor | hermes | agents | trae | qoder | all
#   bash install.sh --uninstall     # remove the links/panel again

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_SOURCE="$REPO_ROOT/skills/88api-image-gen"
PANEL_SOURCE="$REPO_ROOT/hermes-desktop-plugin"
SKILL_NAME="88api-image-gen"

TARGET="all"
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="${2:?--target requires a value: claude|cursor|hermes|agents|trae|qoder|all}"
      shift 2
      ;;
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      sed -n '1,14p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

log()  { printf '%s\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
skip() { printf '  [skip] %s\n' "$*"; }

link_skill() {
  local dest_dir="$1"
  local label="$2"
  mkdir -p "$dest_dir"
  local link_path="$dest_dir/$SKILL_NAME"
  if [ -L "$link_path" ] || [ -e "$link_path" ]; then
    if [ "$(readlink "$link_path" 2>/dev/null || true)" = "$SKILL_SOURCE" ]; then
      ok "$label: already linked ($link_path)"
      return
    fi
    log "  $label: $link_path exists and is not our link; leaving it untouched"
    return
  fi
  ln -sfn "$SKILL_SOURCE" "$link_path"
  ok "$label: linked $link_path -> $SKILL_SOURCE"
}

unlink_skill() {
  local dest_dir="$1"
  local label="$2"
  local link_path="$dest_dir/$SKILL_NAME"
  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$SKILL_SOURCE" ]; then
    rm -f "$link_path"
    ok "$label: removed $link_path"
  else
    skip "$label: nothing to remove"
  fi
}

install_hermes_panel() {
  local dest_dir="$HOME/.hermes/desktop-plugins/$SKILL_NAME"
  mkdir -p "$dest_dir"
  cp "$PANEL_SOURCE/plugin.js" "$dest_dir/plugin.js"
  ok "hermes desktop panel: copied to $dest_dir (run 'Reload desktop plugins' from Cmd-K)"
}

uninstall_hermes_panel() {
  local dest_dir="$HOME/.hermes/desktop-plugins/$SKILL_NAME"
  if [ -d "$dest_dir" ]; then
    rm -rf "$dest_dir"
    ok "hermes desktop panel: removed $dest_dir"
  else
    skip "hermes desktop panel: nothing to remove"
  fi
}

check_prereqs() {
  if ! command -v node >/dev/null 2>&1; then
    log "WARNING: node not found. Install Node.js 18+ before using the plugin."
  else
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "$major" -lt 18 ]; then
      log "WARNING: node $(node --version) detected; Node.js 18+ is required (20+ recommended)."
    else
      ok "node $(node --version)"
    fi
  fi

  case "$(uname -s)" in
    Darwin)
      command -v sips >/dev/null 2>&1 && ok "resize backend: macOS sips" \
        || log "WARNING: sips not found; exact-resize will fail on macOS."
      ;;
    Linux)
      if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
        ok "resize backend: ImageMagick"
      else
        log "WARNING: ImageMagick not found; install it for exact-resize on Linux."
      fi
      ;;
  esac
}

detected_any=0
want() {
  [ "$TARGET" = "all" ] || [ "$TARGET" = "$1" ]
}

log "88API-image-gen installer"
log "repository: $REPO_ROOT"

if [ "$UNINSTALL" -eq 1 ]; then
  want claude && unlink_skill "$HOME/.claude/skills" "claude"
  want cursor && unlink_skill "$HOME/.cursor/skills" "cursor"
  want agents && unlink_skill "$HOME/.agents/skills" "agents"
  want trae && unlink_skill "$HOME/.trae/skills" "trae"
  want trae && unlink_skill "$HOME/.trae-cn/skills" "trae-cn"
  want qoder && unlink_skill "$HOME/.qoder/skills" "qoder"
  if want hermes; then
    unlink_skill "$HOME/.hermes/skills" "hermes"
    uninstall_hermes_panel
  fi
  log "done."
  exit 0
fi

check_prereqs

if want claude; then
  if [ -d "$HOME/.claude" ]; then
    detected_any=1
    link_skill "$HOME/.claude/skills" "claude"
    log "  claude: tip - you can also use '/plugin marketplace add DaYePython/88API-image-gen'"
  else
    skip "claude: ~/.claude not found"
  fi
fi

if want cursor; then
  if [ -d "$HOME/.cursor" ]; then
    detected_any=1
    link_skill "$HOME/.cursor/skills" "cursor"
  else
    skip "cursor: ~/.cursor not found"
  fi
fi

if want agents; then
  detected_any=1
  link_skill "$HOME/.agents/skills" "agents (shared)"
fi

if want trae; then
  if [ -d "$HOME/.trae" ]; then
    detected_any=1
    link_skill "$HOME/.trae/skills" "trae"
  else
    skip "trae: ~/.trae not found"
  fi
  if [ -d "$HOME/.trae-cn" ]; then
    detected_any=1
    link_skill "$HOME/.trae-cn/skills" "trae-cn"
  else
    skip "trae-cn: ~/.trae-cn not found"
  fi
fi

if want qoder; then
  if [ -d "$HOME/.qoder" ]; then
    detected_any=1
    link_skill "$HOME/.qoder/skills" "qoder"
    log "  qoder: tip - you can also import this repo as a local plugin (root .qoder-plugin/plugin.json)"
  else
    skip "qoder: ~/.qoder not found"
  fi
fi

if want hermes; then
  if [ -d "$HOME/.hermes" ]; then
    detected_any=1
    link_skill "$HOME/.hermes/skills" "hermes"
    install_hermes_panel
  else
    skip "hermes: ~/.hermes not found"
  fi
fi

if [ "$detected_any" -eq 0 ]; then
  log "No supported client directory detected. Install Claude Code, Cursor, Hermes, Trae, or Qoder first,"
  log "or link manually: ln -sfn \"$SKILL_SOURCE\" <client-skills-dir>/$SKILL_NAME"
fi

log ""
log "Next step: configure base_url (optional) and your 88API image-generation group key:"
log "  node \"$REPO_ROOT/plugins/88api-image-gen/scripts/generate.mjs\" --set-api-root \"<YOUR_BASE_URL>\"   # optional; default https://88api.ai"
log "  node \"$REPO_ROOT/plugins/88api-image-gen/scripts/generate.mjs\" --set-key \"<YOUR_88API_IMAGE_GROUP_KEY>\""
log "  node \"$REPO_ROOT/plugins/88api-image-gen/scripts/generate.mjs\" --get-config"
