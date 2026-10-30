require('dotenv').config();
const fs = require('fs');
const path = require('path');
const {
  Client, Events, GatewayIntentBits, SlashCommandBuilder, EmbedBuilder, ActionRowBuilder,
  ButtonBuilder, ButtonStyle, ActivityType, MessageFlags,
} = require('discord.js');

/* ---------- configuration ---------- */
const need = ['BOT_TOKEN', 'OWNER_ID', 'BOT_NAME'];
const missing = need.filter((k) => !(process.env[k] || '').trim());
if (missing.length) {
  console.error(`Missing in .env: ${missing.join(', ')}\nRun "bash install.sh" (it asks for them) or copy .env.example to .env.`);
  process.exit(1);
}
const BOT_TOKEN = process.env.BOT_TOKEN.trim();
const OWNER_ID = process.env.OWNER_ID.trim();
const BOT_NAME = process.env.BOT_NAME.trim();
if (!/^\d{17,20}$/.test(OWNER_ID)) {
  console.error('OWNER_ID must be your numeric Discord user ID (17-20 digits).');
  process.exit(1);
}
const DM_DELAY_MS = Math.max(+process.env.DM_DELAY_MS || 1500, 1000); // never faster than 1 DM / second
const ANNOUNCE_NAMES = ['announcement', 'announce'];

/* ---------- opt-out list (people who asked not to get DMs) ---------- */
const DATA_DIR = path.join(__dirname, 'data');
const OPTOUT_FILE = path.join(DATA_DIR, 'optout.json');
fs.mkdirSync(DATA_DIR, { recursive: true });
let optOut = new Set();
try { optOut = new Set(JSON.parse(fs.readFileSync(OPTOUT_FILE, 'utf8'))); } catch { /* first run */ }
const saveOptOut = () => fs.writeFileSync(OPTOUT_FILE, JSON.stringify([...optOut]));

/* ---------- slash commands ---------- */
const announceCommand = (name) => new SlashCommandBuilder()
  .setName(name)
  .setDescription('Owner only: send an announcement to this server')
  .addStringOption((o) => o.setName('message').setDescription('The announcement text').setRequired(true).setMaxLength(1800))
  .addBooleanOption((o) => o.setName('ping_everyone').setDescription('Also post it in this channel and mention @everyone'))
  .addBooleanOption((o) => o.setName('dm_members').setDescription('Send it as a DM to every member (default: yes)'))
  .setDMPermission(false);
const optoutCommand = new SlashCommandBuilder()
  .setName('optout')
  .setDescription('Stop (or resume) receiving announcement DMs from this bot')
  .setDMPermission(false);
const commandJSON = [...ANNOUNCE_NAMES.map(announceCommand), optoutCommand].map((c) => c.toJSON());

/* ---------- client ---------- */
const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers], // GuildMembers = privileged "Server Members Intent"
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const busy = new Set(); // guilds with an announcement in progress

const registerCommands = (guild) =>
  guild.commands.set(commandJSON).catch((e) => console.error(`Could not register commands in ${guild.name}:`, e.message));

client.once(Events.ClientReady, async (c) => {
  console.log(`✅ ${BOT_NAME} is online! Logged in as ${c.user.tag} (${c.guilds.cache.size} server(s))`);
  c.user.setPresence({ activities: [{ name: BOT_NAME, type: ActivityType.Playing }] });
  for (const guild of c.guilds.cache.values()) await registerCommands(guild);
});
client.on(Events.GuildCreate, registerCommands);

client.on(Events.InteractionCreate, async (i) => {
  if (!i.isChatInputCommand()) return;
  try {
    if (i.commandName === 'optout') return await handleOptOut(i);
    if (ANNOUNCE_NAMES.includes(i.commandName)) return await handleAnnounce(i);
  } catch (e) {
    console.error('Command error:', e);
    const text = 'Something went wrong. Check the bot console.';
    if (i.deferred || i.replied) await i.editReply({ content: text, components: [] }).catch(() => {});
    else await i.reply({ content: text, flags: MessageFlags.Ephemeral }).catch(() => {});
  }
});

async function handleOptOut(i) {
  const nowOut = !optOut.has(i.user.id);
  nowOut ? optOut.add(i.user.id) : optOut.delete(i.user.id);
  saveOptOut();
  return i.reply({
    content: nowOut ? '🔕 You will no longer receive announcement DMs. Run /optout again to turn them back on.'
                    : '🔔 Announcement DMs are back on for you.',
    flags: MessageFlags.Ephemeral,
  });
}

async function sendDm(member, embed, retry = true) {
  try { await member.send({ embeds: [embed] }); return { ok: true }; }
  catch (e) {
    if (e.code === 40003 && retry) { // "opening DMs too fast": back off, then retry once
      console.warn('Discord asked us to slow down. Pausing 60s...');
      await sleep(60_000);
      return sendDm(member, embed, false);
    }
    return { ok: false, closed: e.code === 50007, reason: e.code === 50007 ? 'DMs closed or bot blocked' : `error ${e.code ?? e.message}` };
  }
}

async function handleAnnounce(i) {
  if (i.user.id !== OWNER_ID)
    return i.reply({ content: '⛔ Only the bot owner can use this command.', flags: MessageFlags.Ephemeral });
  if (busy.has(i.guildId))
    return i.reply({ content: 'An announcement is already being sent in this server.', flags: MessageFlags.Ephemeral });

  const message = i.options.getString('message', true);
  const ping = i.options.getBoolean('ping_everyone') ?? false;
  const dm = i.options.getBoolean('dm_members') ?? true;
  await i.deferReply({ flags: MessageFlags.Ephemeral });
  busy.add(i.guildId);

  try {
    /* 1. work out what will happen */
    let targets = [], optedOut = 0;
    if (dm) {
      await i.editReply('Fetching server members…');
      const humans = [...(await i.guild.members.fetch()).values()].filter((m) => !m.user.bot);
      targets = humans.filter((m) => !optOut.has(m.id));
      optedOut = humans.length - targets.length;
    }
    if (!dm && !ping) return i.editReply('Nothing to do: both ping_everyone and dm_members are off.');

    const plan = [];
    if (ping) plan.push(`• Post in this channel with **@everyone**`);
    if (dm) plan.push(`• DM **${targets.length}** member(s) (${optedOut} opted out). About ${Math.max(1, Math.ceil((targets.length * (DM_DELAY_MS + 250)) / 60000))} min.`);

    /* 2. owner must confirm */
    const row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId('confirm').setLabel('Send now').setStyle(ButtonStyle.Danger),
      new ButtonBuilder().setCustomId('cancel').setLabel('Cancel').setStyle(ButtonStyle.Secondary));
    const prompt = await i.editReply({ content: `**Please confirm**\n${plan.join('\n')}\n\n>>> ${message}`, components: [row] });
    let click;
    try { click = await prompt.awaitMessageComponent({ filter: (b) => b.user.id === OWNER_ID, time: 60_000 }); }
    catch { return i.editReply({ content: '⌛ Timed out. Nothing was sent.', components: [] }); }
    if (click.customId === 'cancel') return click.update({ content: '❌ Cancelled. Nothing was sent.', components: [] });
    await click.update({ content: '📤 Sending…', components: [] });

    /* 3. channel post */
    let channelNote = '';
    if (ping) {
      try {
        await i.channel.send({ content: `@everyone\n${message}`, allowedMentions: { parse: ['everyone'] } });
        channelNote = '✅ Posted in this channel with @everyone.\n';
      } catch (e) { channelNote = `⚠️ Could not post in this channel: ${e.message}\n`; }
    }

    /* 4. DMs, one at a time with delays */
    const started = Date.now();
    let sent = 0, failed = 0, hardFails = 0, aborted = false;
    const reasons = {};
    if (dm) {
      const embed = new EmbedBuilder()
        .setTitle(`📢 Announcement from ${i.guild.name}`)
        .setDescription(message).setColor(0x5865f2)
        .setFooter({ text: `Sent by ${BOT_NAME} • Use /optout in the server to stop these DMs` })
        .setTimestamp();
      for (let n = 0; n < targets.length; n++) {
        const r = await sendDm(targets[n], embed);
        if (r.ok) { sent++; hardFails = 0; }
        else {
          failed++; reasons[r.reason] = (reasons[r.reason] || 0) + 1;
          hardFails = r.closed ? 0 : hardFails + 1;
          if (hardFails >= 10) { aborted = true; break; } // something is wrong (flagged/limited): stop, protect the bot
        }
        if ((n + 1) % 50 === 0 && Date.now() - started < 14 * 60_000)
          await i.editReply(`📤 Sending… ${n + 1}/${targets.length} (✅ ${sent}  ❌ ${failed})`).catch(() => {});
        await sleep(DM_DELAY_MS + Math.floor(Math.random() * 500));
      }
    }

    /* 5. summary for the owner */
    const secs = Math.round((Date.now() - started) / 1000);
    let summary = channelNote;
    if (dm) {
      summary += `**Announcement finished**\n✅ DMs sent: **${sent}**\n❌ Failed: **${failed}**\n⏭️ Skipped (opted out): **${optedOut}**\n⏱️ Time: ${Math.floor(secs / 60)}m ${secs % 60}s`;
      const lines = Object.entries(reasons).map(([k, v]) => `   - ${k}: ${v}`);
      if (lines.length) summary += `\nFailure reasons:\n${lines.join('\n')}`;
      if (aborted) summary += `\n🛑 Stopped early after 10 unexpected errors in a row. Wait a while before trying again.`;
    }
    console.log(`[${BOT_NAME}] Announcement in "${i.guild.name}": sent ${sent}, failed ${failed}, opted out ${optedOut}`);
    // The interaction token lasts 15 min; for long runs also DM the owner.
    await i.editReply({ content: summary, components: [] }).catch(() => i.user.send(summary).catch(() => {}));
    if (Date.now() - started > 14 * 60_000) await i.user.send(summary).catch(() => {});
  } finally {
    busy.delete(i.guildId);
  }
}

/* ---------- start ---------- */
process.on('unhandledRejection', (e) => console.error('Unhandled rejection:', e));
process.on('SIGINT', () => { console.log('Shutting down…'); client.destroy(); process.exit(0); });
process.on('SIGTERM', () => { client.destroy(); process.exit(0); });

client.login(BOT_TOKEN).catch((e) => {
  if (e.code === 'TokenInvalid') console.error('❌ Invalid BOT_TOKEN. Reset it in the Developer Portal and update .env.');
  else if (e.code === 'DisallowedIntents') console.error('❌ Enable "Server Members Intent" in the Developer Portal (Bot tab -> Privileged Gateway Intents).');
  else console.error('❌ Login failed:', e.message);
  process.exit(1);
});
