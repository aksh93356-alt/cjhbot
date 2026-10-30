#!/usr/bin/env bash
# All-in-one installer for the Discord Announcement Bot (Debian / Ubuntu).
#
#   bash install.sh
#
# It updates the system, installs Node.js 20 + npm + git if needed, asks for
# BOT_TOKEN / OWNER_ID / BOT_NAME, writes .env, runs npm install, then lets you
# start the bot directly or in the background with PM2.
#
# Optional: pass values up front to skip the questions:
#   BOT_TOKEN=xxx OWNER_ID=123456789012345678 BOT_NAME="My Bot" bash install.sh
# Optional: run it from outside the repo and let it clone for you:
#   REPO_URL=https://github.com/YOUR_NAME/discord-announce-bot.git bash install.sh
set -euo pipefail

PM2_NAME="discord-announce-bot"
REPO_URL="${REPO_URL:-}"
export DEBIAN_FRONTEND=noninteractive

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

command -v apt-get >/dev/null 2>&1 || die "This installer supports Debian/Ubuntu (apt) only."
[ -r /dev/tty ] || die "No terminal available for questions. Run it from an interactive shell, or pass BOT_TOKEN, OWNER_ID and BOT_NAME as environment variables."

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "Run as root, or install sudo."
  SUDO="sudo"
fi

# ---------------------------------------------------------------- 1. system
say "[1/6] Updating system packages"
$SUDO apt-get update -y
$SUDO apt-get upgrade -y
$SUDO apt-get install -y curl git ca-certificates gnupg

# ---------------------------------------------------------------- 2. node
say "[2/6] Checking Node.js (need v18 or newer)"
node_major() { node -v 2>/dev/null | cut -d. -f1 | tr -d v; }
if ! command -v node >/dev/null 2>&1 || [ "$(node_major)" -lt 18 ]; then
  echo "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
  $SUDO apt-get install -y nodejs
fi
command -v npm >/dev/null 2>&1 || $SUDO apt-get install -y npm
echo "node $(node -v), npm $(npm -v), $(git --version)"

# ---------------------------------------------------------------- 3. project folder
say "[3/6] Locating the bot files"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$SCRIPT_DIR/index.js" ]; then
  cd "$SCRIPT_DIR"
elif [ -f "./index.js" ]; then
  :
elif [ -n "$REPO_URL" ]; then
  git clone "$REPO_URL" discord-announce-bot
  cd discord-announce-bot
else
  die "index.js not found. Run this script inside the bot folder, or set REPO_URL=<your git repo>."
fi
echo "Using folder: $(pwd)"

# ---------------------------------------------------------------- 4. credentials -> .env
ask() { # ask VAR "Prompt" secret(0|1) "regex" "error message"
  local var="$1" prompt="$2" secret="$3" regex="$4" err="$5" val="${!1:-}"
  while true; do
    if [ -z "$val" ]; then
      if [ "$secret" = 1 ]; then read -rsp "$prompt: " val </dev/tty; echo
      else read -rp "$prompt: " val </dev/tty; fi
    fi
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"   # trim spaces
    if [[ "$val" =~ $regex ]]; then break; fi
    echo "  $err" >&2; val=""
  done
  printf -v "$var" '%s' "$val"
}

say "[4/6] Bot settings"
WRITE_ENV=1
if [ -f .env ]; then
  read -rp ".env already exists. Keep it? [Y/n]: " keep </dev/tty || keep="y"
  if [[ ! "${keep:-y}" =~ ^[Nn] ]]; then WRITE_ENV=0; echo "Keeping existing .env"; fi
fi
if [ "$WRITE_ENV" = 1 ]; then
  ask BOT_TOKEN "BOT_TOKEN (Discord bot token, hidden while typing)" 1 '^[^[:space:]]{30,}$' "That does not look like a bot token. Copy it again from the Developer Portal."
  ask OWNER_ID  "OWNER_ID (your numeric Discord user ID)"           0 '^[0-9]{17,20}$'      "OWNER_ID must be 17-20 digits."
  ask BOT_NAME  "BOT_NAME (custom name for your bot)"               0 '^.+$'                "BOT_NAME cannot be empty."
  BOT_NAME="${BOT_NAME//[\"\\]/}"                                   # remove characters that could break the .env file
  umask 077
  printf 'BOT_TOKEN=%s\nOWNER_ID=%s\nBOT_NAME="%s"\nDM_DELAY_MS=1500\n' "$BOT_TOKEN" "$OWNER_ID" "$BOT_NAME" > .env
  chmod 600 .env
  echo "Saved .env (permissions 600)"
fi

# ---------------------------------------------------------------- 5. dependencies
say "[5/6] Installing dependencies (npm install)"
npm install --omit=dev

# ---------------------------------------------------------------- 6. start
say "[6/6] How do you want to start the bot?"
echo "  1) Start now in this terminal (stops when you close it, Ctrl+C to stop)"
echo "  2) Start in the background with PM2 (keeps running, restarts on reboot)"
echo "  3) Do not start, I will do it later (npm start)"
read -rp "Choose 1, 2 or 3 [2]: " choice </dev/tty || choice="2"
case "${choice:-2}" in
  1)
    say "Starting. You should see: <BOT_NAME> is online!"
    exec node index.js
    ;;
  3)
    echo "Done. Start it any time with:  cd $(pwd) && npm start"
    ;;
  *)
    command -v pm2 >/dev/null 2>&1 || $SUDO npm install -g pm2
    pm2 delete "$PM2_NAME" >/dev/null 2>&1 || true
    pm2 start index.js --name "$PM2_NAME"
    pm2 save
    $SUDO env PATH="$PATH" pm2 startup systemd -u "$(id -un)" --hp "$HOME" >/dev/null 2>&1 \
      || warn "Could not enable start-on-reboot automatically. Run: pm2 startup"
    sleep 4
    pm2 logs "$PM2_NAME" --lines 10 --nostream || true
    echo
    echo "Bot is running in the background."
    echo "  Logs:     pm2 logs $PM2_NAME"
    echo "  Restart:  pm2 restart $PM2_NAME"
    echo "  Stop:     pm2 stop $PM2_NAME"
    ;;
esac
