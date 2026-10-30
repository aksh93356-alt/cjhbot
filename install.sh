#!/usr/bin/env bash
# CJH BOT SETUP: menu installer for the Discord Announcement Bot (Debian / Ubuntu).
#
#   bash install.sh              open the menu
#   bash install.sh install      run one action directly (install | update | uninstall)
#
# Optional environment variables:
#   BOT_TOKEN, OWNER_ID, BOT_NAME   skip the questions during install
#   REPO_URL      git repo to clone when install.sh is run outside the bot folder
#   INSTALL_DIR   where the bot lives (default: the folder of this script, else ~/discord-announce-bot)
set -uo pipefail

PM2_NAME="discord-announce-bot"
REPO_URL="${REPO_URL:-}"
TTY="${CJH_TTY:-/dev/tty}"          # where questions are read from
export DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# ------------------------------------------------------------------ look and feel
C0=$'\033[0m'; CB=$'\033[1m'; CC=$'\033[1;36m'; CG=$'\033[1;32m'; CY=$'\033[1;33m'; CR=$'\033[1;31m'; CD=$'\033[2m'
say()  { printf '\n%s==> %s%s\n' "$CC" "$*" "$C0"; }
ok()   { printf '%s✔ %s%s\n' "$CG" "$*" "$C0"; }
warn() { printf '%s! %s%s\n' "$CY" "$*" "$C0" >&2; }
die()  { printf '%s✘ %s%s\n' "$CR" "$*" "$C0" >&2; exit 1; }

# ------------------------------------------------------------------ helpers
# Find the bot folder: $INSTALL_DIR, then the folder of this script, then ~/discord-announce-bot
resolve_dir() {
  local d
  for d in "${INSTALL_DIR:-}" "$SCRIPT_DIR" "$HOME/discord-announce-bot"; do
    [ -n "$d" ] && [ -f "$d/index.js" ] && [ -f "$d/package.json" ] && { echo "$d"; return 0; }
  done
  return 1
}

bot_status() {
  local dir; dir="$(resolve_dir)" || { echo "${CD}not installed${C0}"; return; }
  local st="${CY}stopped${C0}"
  if command -v pm2 >/dev/null 2>&1 && pm2 describe "$PM2_NAME" 2>/dev/null | grep -q 'online'; then st="${CG}running${C0}"; fi
  echo "installed at ${CB}$dir${C0} (${st})"
}

pause() { read -rp "  Press Enter to return to the menu... " _ <"$TTY" || true; }

ensure_pm2() { command -v pm2 >/dev/null 2>&1 || $SUDO npm install -g pm2; }

# Updates the system and installs git, curl, Node.js 20 (if missing or older than 18) and npm
prepare_system() {
  command -v apt-get >/dev/null 2>&1 || die "This installer supports Debian/Ubuntu (apt) only."
  if [ -n "$SUDO" ]; then command -v sudo >/dev/null 2>&1 || die "Run as root, or install sudo."; fi
  say "Updating system packages"
  $SUDO apt-get update -y
  $SUDO apt-get upgrade -y
  $SUDO apt-get install -y curl git ca-certificates gnupg
  say "Checking Node.js (need v18 or newer)"
  local major; major="$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)"
  if ! command -v node >/dev/null 2>&1 || [ "${major:-0}" -lt 18 ]; then
    echo "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
    $SUDO apt-get install -y nodejs
  fi
  command -v npm >/dev/null 2>&1 || $SUDO apt-get install -y npm
  echo "node $(node -v), npm $(npm -v), $(git --version)"
}

ask() { # ask VAR "Prompt" secret(0|1) "regex" "error message"
  local var="$1" prompt="$2" secret="$3" regex="$4" err="$5" val="${!1:-}"
  while true; do
    if [ -z "$val" ]; then
      if [ "$secret" = 1 ]; then read -rsp "  $prompt: " val <"$TTY"; echo
      else read -rp "  $prompt: " val <"$TTY"; fi
    fi
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"   # trim spaces
    if [[ "$val" =~ $regex ]]; then break; fi
    echo "  $err" >&2; val=""
  done
  printf -v "$var" '%s' "$val"
}

# Only ever delete a folder that really is this bot's folder
safe_to_delete() {
  local d="${1%/}"
  case "$d" in ""|"/"|"$HOME") return 1 ;; esac
  [ "$(printf '%s' "$d" | tr -cd '/' | wc -c)" -ge 2 ] || return 1
  [ -f "$d/index.js" ] && [ -f "$d/package.json" ] && grep -q '"name": "discord-announce-bot"' "$d/package.json"
}

# ------------------------------------------------------------------ 1. INSTALL
do_install() {
  [ -r "$TTY" ] || die "No terminal available for questions."
  prepare_system

  say "Locating the bot files"
  local dir
  if ! dir="$(resolve_dir)"; then
    [ -n "$REPO_URL" ] || die "index.js not found. Run install.sh inside the bot folder, or set REPO_URL=<your git repo>."
    dir="${INSTALL_DIR:-$HOME/discord-announce-bot}"
    git clone "$REPO_URL" "$dir"
  fi
  cd "$dir"
  echo "Using folder: $dir"

  say "Bot settings"
  local write_env=1 keep
  if [ -f .env ]; then
    read -rp "  .env already exists. Keep it? [Y/n]: " keep <"$TTY" || keep="y"
    if [[ ! "${keep:-y}" =~ ^[Nn] ]]; then write_env=0; echo "Keeping existing .env"; fi
  fi
  if [ "$write_env" = 1 ]; then
    ask BOT_TOKEN "BOT_TOKEN (Discord bot token, hidden while typing)" 1 '^[^[:space:]]{30,}$' "That does not look like a bot token. Copy it again from the Developer Portal."
    ask OWNER_ID  "OWNER_ID  (your numeric Discord user ID)"           0 '^[0-9]{17,20}$'      "OWNER_ID must be 17-20 digits."
    ask BOT_NAME  "BOT_NAME  (custom name for your bot)"               0 '^.+$'                "BOT_NAME cannot be empty."
    BOT_NAME="${BOT_NAME//[\"\\]/}"                                    # remove characters that could break .env
    umask 077
    printf 'BOT_TOKEN=%s\nOWNER_ID=%s\nBOT_NAME="%s"\nDM_DELAY_MS=1500\n' "$BOT_TOKEN" "$OWNER_ID" "$BOT_NAME" > .env
    chmod 600 .env
    ok "Saved .env (permissions 600)"
  fi

  say "Installing dependencies (npm install)"
  npm install --omit=dev

  say "Starting the bot with PM2"
  ensure_pm2
  pm2 delete "$PM2_NAME" >/dev/null 2>&1 || true
  pm2 start "$dir/index.js" --name "$PM2_NAME" --cwd "$dir"
  pm2 save
  $SUDO env PATH="$PATH" pm2 startup systemd -u "$(id -un)" --hp "$HOME" >/dev/null 2>&1 \
    || warn "Could not enable start-on-reboot automatically. Run: pm2 startup"
  sleep 4
  pm2 logs "$PM2_NAME" --lines 10 --nostream || true
  echo
  ok "Bot is running in the background."
  echo "  Logs: pm2 logs $PM2_NAME     Restart: pm2 restart $PM2_NAME     Stop: pm2 stop $PM2_NAME"
}

# ------------------------------------------------------------------ 2. UNINSTALL
do_uninstall() {
  local dir; dir="$(resolve_dir)" || { warn "No installation found. Nothing to remove."; return 0; }
  safe_to_delete "$dir" || die "Refusing to delete '$dir': it does not look like the bot folder."

  echo "  This will:"
  echo "    - stop the bot and remove it from PM2"
  echo "    - DELETE the folder $dir (including your .env settings)"
  echo "  Node.js, npm, git and PM2 themselves stay installed."
  local answer; read -rp "  Type 'yes' to continue: " answer <"$TTY" || answer=""
  [ "$answer" = "yes" ] || { echo "Cancelled. Nothing was removed."; return 0; }

  say "Stopping the bot"
  if command -v pm2 >/dev/null 2>&1; then
    pm2 stop "$PM2_NAME" >/dev/null 2>&1 || true
    pm2 delete "$PM2_NAME" >/dev/null 2>&1 || true
    pm2 save --force >/dev/null 2>&1 || true
    rm -f "$HOME/.pm2/logs/$PM2_NAME-out.log" "$HOME/.pm2/logs/$PM2_NAME-error.log"
    ok "PM2 process '$PM2_NAME' removed"
  fi
  local pid                                                            # bot started by hand with "node index.js"
  for pid in $(pgrep -f 'node.*index.js' 2>/dev/null || true); do
    if [ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" = "$dir" ]; then kill "$pid" 2>/dev/null || true; fi
  done

  say "Removing $dir"
  cd "$HOME" || cd /
  rm -rf -- "$dir"
  ok "Bot uninstalled."
}

# ------------------------------------------------------------------ 3. UPDATE
do_update() {
  local dir; dir="$(resolve_dir)" || { warn "No installation found. Choose option 1 first."; return 0; }
  cd "$dir"
  command -v git >/dev/null 2>&1 || die "git is not installed. Run option 1 first."
  command -v npm >/dev/null 2>&1 || die "npm is not installed. Run option 1 first."
  [ -d .git ] || die "$dir is not a git checkout, so it cannot be updated with git pull."

  say "Pulling the latest code"
  git pull --ff-only || die "git pull failed. If you edited files, run 'git stash' in $dir and try again."
  git log -1 --oneline

  say "Reinstalling npm packages"
  npm install --omit=dev
  [ -f .env ] || warn ".env is missing. Run option 1 to create it."

  say "Restarting the bot"
  ensure_pm2
  if pm2 describe "$PM2_NAME" >/dev/null 2>&1; then
    pm2 restart "$PM2_NAME" --update-env
  else
    pm2 start "$dir/index.js" --name "$PM2_NAME" --cwd "$dir"
  fi
  pm2 save
  sleep 3
  pm2 logs "$PM2_NAME" --lines 8 --nostream || true
  ok "Bot updated and restarted."
}

# ------------------------------------------------------------------ menu
show_menu() {
  command -v clear >/dev/null 2>&1 && [ -t 1 ] && clear
  printf '%s' "$CC"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║              CJH BOT SETUP               ║"
  echo "  ╚══════════════════════════════════════════╝"
  printf '%s' "$C0"
  echo "  Status: $(bot_status)"
  echo
  echo "   ${CB}1)${C0} Install Bot    ${CD}token, owner, name, dependencies, start${C0}"
  echo "   ${CB}2)${C0} Uninstall Bot  ${CD}stop, clean PM2, delete the folder${C0}"
  echo "   ${CB}3)${C0} Update Bot     ${CD}git pull, npm install, restart${C0}"
  echo "   ${CB}4)${C0} Exit"
  echo
}

# Run an action in a subshell with "exit on first error", so a failure returns to the menu
run_action() {
  ( set -e; "$1" )
  local rc=$?
  echo
  if [ "$rc" -eq 0 ]; then ok "Finished."; else warn "That did not finish (see the message above)."; fi
  return 0
}

main() {
  if [ -n "${1:-}" ]; then                                             # direct mode: bash install.sh install
    case "$1" in
      install)   run_action do_install ;;
      update)    run_action do_update ;;
      uninstall) run_action do_uninstall ;;
      *) die "Usage: bash install.sh [install|update|uninstall]" ;;
    esac
    exit 0
  fi
  [ -r "$TTY" ] || die "No terminal available. Run this script from an interactive shell."
  local choice
  while true; do
    show_menu
    read -rp "  Choose an option [1-4]: " choice <"$TTY" || exit 0
    case "$choice" in
      1) run_action do_install;   pause ;;
      2) run_action do_uninstall; pause ;;
      3) run_action do_update;    pause ;;
      4|q|Q) echo "  Goodbye!"; exit 0 ;;
      *) warn "Please type a number from 1 to 4."; sleep 1 ;;
    esac
  done
}

main "$@"
