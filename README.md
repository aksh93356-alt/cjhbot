# Discord Announcement Bot

Owner-only `/announcement` (alias `/announce`) command for your Discord server, plus `/optout` for members.

## What it does

`/announcement message:<text> [ping_everyone] [dm_members]`

- Only the user whose ID equals `OWNER_ID` can run it. Everyone else gets a refusal.
- `dm_members` (default **true**): sends the text as a DM to every non-bot member, one at a time, with a delay.
- `ping_everyone` (default false): also posts the text in the current channel and mentions @everyone.
- Before anything is sent, the owner sees how many people will be messaged and must press **Send now**.
- Members with DMs closed or who blocked the bot are skipped without crashing. A summary shows sent / failed / opted-out counts and failure reasons.
- Members can run `/optout` to stop getting DMs. The bot respects it.
- Safety: at least 1 s between DMs (default 1.5 s + random jitter), a 60 s pause if Discord says "opening DMs too fast", and an automatic stop after 10 unexpected errors in a row.

## 1. Create the bot in the Developer Portal

1. Open <https://discord.com/developers/applications> -> **New Application**.
2. **Bot** tab -> **Reset Token** -> copy it (this is `BOT_TOKEN`; never share it or commit it).
3. Same tab, **Privileged Gateway Intents**:
   - Turn on **Server Members Intent**. **Required**: without it the bot cannot list members.
   - **Message Content Intent**: *not needed* (slash commands do not read messages). You may leave it off. If you want it on anyway, the toggle is in the same place.
4. **OAuth2 -> URL Generator**: scopes `bot` and `applications.commands`. Bot permissions: View Channels, Send Messages, Embed Links, and **Mention Everyone** (only if you use `ping_everyone`). Open the generated URL and add the bot to your server.
5. Your `OWNER_ID`: Discord -> Settings -> Advanced -> enable **Developer Mode**, then right-click your own name -> **Copy User ID**.

Note: bots in 100+ servers need Discord verification to keep the Server Members Intent.

## 2. Install on a Linux VPS (Debian/Ubuntu)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/aksh93356-alt/cjhbot/main/install.sh)
```

This opens the **CJH BOT SETUP** menu:

```
  ╔══════════════════════════════════════════╗
  ║              CJH BOT SETUP               ║
  ╚══════════════════════════════════════════╝
   1) Install Bot
   2) Uninstall Bot
   3) Update Bot
   4) Exit

  Choose an option [1-4]:
```

| Option | What it does |
|---|---|
| **1) Install Bot** | Updates system packages, installs Node.js 20, npm and git if missing, asks for **BOT_TOKEN**, **OWNER_ID** and **BOT_NAME**, writes `.env` (permissions 600), runs `npm install`, and starts the bot in the background with PM2 (also on reboot). |
| **2) Uninstall Bot** | After you type `yes`: stops the bot, removes it from PM2 (and its PM2 logs), and deletes the bot folder including `.env`. Node.js, npm, git and PM2 stay installed. |
| **3) Update Bot** | `git pull`, `npm install`, then restarts the bot with PM2. Your `.env` is kept. |
| **4) Exit** | Leaves the menu. |

When the bot is online you will see: `✅ <BOT_NAME> is online! Logged in as ...` (check with `pm2 logs discord-announce-bot`).

Shortcuts:

```bash
bash install.sh install      # go straight to an action (install | update | uninstall)
BOT_TOKEN=xxxx OWNER_ID=123456789012345678 BOT_NAME="My Bot" bash install.sh install   # no questions
```

Running the script from outside the repo? Set `REPO_URL=https://github.com/YOUR_NAME/discord-announce-bot.git` and it clones the bot to `~/discord-announce-bot` (override with `INSTALL_DIR`).

Manual way: `cp .env.example .env`, edit it, then `npm install && npm start`.

## Important: read before mass-DMing

Discord's rules prohibit unsolicited bulk DMs (spam). Sending the same DM to a whole server can get members to report the bot, and Discord can **disable the bot or your account**. To stay safe:

- Prefer posting in an announcements channel (`dm_members:false ping_everyone:true`).
- Only DM small servers whose members expect it, keep messages rare and relevant.
- Keep `/optout` available, and do not lower the delay.

## Files

```
index.js        bot, commands, DM logic
package.json    dependencies (discord.js, dotenv)
.env.example    BOT_TOKEN, OWNER_ID, BOT_NAME
.gitignore      keeps .env and node_modules out of git
install.sh      CJH BOT SETUP menu (install / uninstall / update)
README.md
```


## you vps discord bot instalestion

**commands**
```git clone https://github.com/aksh93356-alt/cjhbot.git```
**next commands**
```cd cjhbot```
**next commands**
```chmod +x install.sh```
**next commands**
```./install.sh```
