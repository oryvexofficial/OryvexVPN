// ============================================================================
// SOCIAL MEDIA (Admin > Social media)
//
// Permission: "social". The owner always has it; the owner (or a Team admin)
// can grant it to other admins.
//
// - Telegram bot: token, webhook, reconnect, health check (see 05-settings-admin).
// - Telegram channel: channel @username or -100 id, connection test (is the bot
//   an admin there?), post messages (plain or HTML, optional button, silent,
//   pin), recent posts log with delete.
// - Social links: Telegram, X, Instagram, YouTube, TikTok, Discord, Reddit,
//   WhatsApp, Facebook, website. Optional footer row on the public site and a
//   /social command + "Join channel" button in the bot.
// - Bots: Telegram, Discord, WhatsApp, Messenger, LINE, Slack, Viber or any
//   other bot by ID/username. Each one gets a ready-made "open / add" link and
//   is shown on the public /social page, in the burger menu and in the footer.
// - Public /social page ("Social media" in the header, burger menu and footer).
//
// Storage (D1, binding DB):
//   settings.social_config  JSON (links, bots, footer/page flags, channel)
//   social_posts            log of channel posts (created by the Worker too)
// ============================================================================

const SOCIAL_NETWORKS = [
    { id: 'telegram', label: 'Telegram', ph: 'https://t.me/yourchannel' },
    { id: 'x', label: 'X (Twitter)', ph: 'https://x.com/yourname' },
    { id: 'instagram', label: 'Instagram', ph: 'https://instagram.com/yourname' },
    { id: 'youtube', label: 'YouTube', ph: 'https://youtube.com/@yourname' },
    { id: 'tiktok', label: 'TikTok', ph: 'https://tiktok.com/@yourname' },
    { id: 'discord', label: 'Discord', ph: 'https://discord.gg/invite' },
    { id: 'reddit', label: 'Reddit', ph: 'https://reddit.com/r/yoursub' },
    { id: 'whatsapp', label: 'WhatsApp', ph: 'https://whatsapp.com/channel/...' },
    { id: 'facebook', label: 'Facebook', ph: 'https://facebook.com/yourpage' },
    { id: 'website', label: 'Website', ph: 'https://example.com' }
];
const SOCIAL_IDS = SOCIAL_NETWORKS.map(n => n.id);
const SOCIAL_POST_MAX = 4000;

// Bots people can open or add. idLabel/ph drive the admin form; link() builds
// the public "open / add" URL from the ID when no custom link is given.
const SOCIAL_BOT_PLATFORMS = [
    { id: 'telegram', label: 'Telegram', idLabel: 'Bot username', ph: '@VexoStreamBot', cta: 'Open in Telegram', hint: 'The @username from BotFather.' },
    { id: 'discord', label: 'Discord', idLabel: 'Application (client) ID', ph: '123456789012345678', cta: 'Add to Discord', hint: 'Developer Portal › your app › Application ID. Builds the “Add to server” link.' },
    { id: 'whatsapp', label: 'WhatsApp', idLabel: 'Phone number', ph: '+15551234567', cta: 'Chat on WhatsApp', hint: 'Full number with country code.' },
    { id: 'messenger', label: 'Messenger', idLabel: 'Page username', ph: 'yourpage', cta: 'Open in Messenger', hint: 'Your Facebook Page username (m.me link).' },
    { id: 'line', label: 'LINE', idLabel: 'LINE ID', ph: '@yourbot', cta: 'Add on LINE', hint: 'Official account ID, with the @.' },
    { id: 'slack', label: 'Slack', idLabel: 'App ID', ph: 'A0123456789', cta: 'Add to Slack', hint: 'Starts with A. Paste your install link below for one-click add.' },
    { id: 'viber', label: 'Viber', idLabel: 'Bot URI', ph: 'yourbot', cta: 'Open in Viber', hint: 'Add the public https link below to make it clickable.' },
    { id: 'other', label: 'Other', idLabel: 'Bot ID or handle', ph: 'your-bot', cta: 'Open bot', hint: 'Any platform. Add a link so people can open it.' }
];
const SOCIAL_BOT_IDS = SOCIAL_BOT_PLATFORMS.map(p => p.id);
const SOCIAL_BOT_MAX = 12;
function botPlatform(id) { return SOCIAL_BOT_PLATFORMS.find(p => p.id === id) || SOCIAL_BOT_PLATFORMS[SOCIAL_BOT_PLATFORMS.length - 1]; }

let __social = { at: 0, cfg: null };
let __socialPostsReady = false;

function socialDefaults() {
    return { links: {}, bots: [], showInFooter: false, showPage: true, botButtons: true, channel: { chatId: '', title: '', inviteUrl: '' } };
}

function normalizeSocialUrl(raw) {
    const text = String(raw == null ? '' : raw).trim();
    if (!text) return '';
    if (text.length > 240) return null;
    try {
        const u = new URL(/^https?:\/\//i.test(text) ? text : 'https://' + text);
        if (u.protocol !== 'https:' || u.username || u.password || isPrivateHost(u.hostname) || !u.hostname.includes('.')) return null;
        return u.toString();
    } catch (_) { return null; }
}

// @publicchannel or a numeric -100... id for private channels
function normalizeChannelId(raw) {
    let t = String(raw == null ? '' : raw).trim();
    if (!t) return '';
    const m = t.match(/^(?:https?:\/\/)?(?:t\.me|telegram\.me)\/([A-Za-z][A-Za-z0-9_]{4,31})\/?$/i);
    if (m) t = '@' + m[1];
    if (/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(t)) t = '@' + t;
    if (/^@[A-Za-z][A-Za-z0-9_]{4,31}$/.test(t)) return t;
    if (/^-100\d{5,16}$/.test(t)) return t;
    return null;
}

// Returns the cleaned ID, '' when empty, or null when it doesn't fit the platform.
function normalizeBotId(platform, raw) {
    let t = String(raw == null ? '' : raw).trim();
    if (!t) return '';
    if (t.length > 120) return null;
    if (platform === 'telegram') {
        const m = t.match(/^(?:https?:\/\/)?(?:t\.me|telegram\.me)\/([A-Za-z][A-Za-z0-9_]{4,31})(?:[/?].*)?$/i);
        if (m) t = m[1];
        t = t.replace(/^@/, '');
        return /^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(t) ? '@' + t : null;
    }
    if (platform === 'discord') {
        const m = t.match(/client_id=(\d{17,20})/);
        if (m) t = m[1];
        return /^\d{17,20}$/.test(t) ? t : null;
    }
    if (platform === 'whatsapp') {
        const m = t.match(/wa\.me\/(\d+)/i);
        if (m) t = m[1];
        const d = t.replace(/[\s().+-]/g, '');
        return /^\d{7,15}$/.test(d) ? '+' + d : null;
    }
    if (platform === 'messenger') {
        const m = t.match(/m\.me\/([A-Za-z0-9.]+)/i);
        if (m) t = m[1];
        return /^[A-Za-z0-9.]{3,50}$/.test(t) ? t : null;
    }
    if (platform === 'line') return /^@?[A-Za-z0-9._-]{3,40}$/.test(t) ? t : null;
    if (platform === 'slack') return /^A[A-Za-z0-9]{6,20}$/.test(t) ? t.toUpperCase() : null;
    if (platform === 'viber') return /^[A-Za-z0-9_.-]{2,60}$/.test(t) ? t : null;
    return /^[^<>"'`\s][^<>"'`]{0,79}$/.test(t) ? t : null;
}

// Public "open / add" link: the custom link if set, else built from the ID.
function botLink(bot) {
    if (!bot) return '';
    if (bot.url) return bot.url;
    const id = bot.botId || '';
    if (!id) return '';
    switch (bot.platform) {
        case 'telegram': return 'https://t.me/' + id.replace(/^@/, '');
        case 'discord': return 'https://discord.com/oauth2/authorize?client_id=' + id + '&scope=bot%20applications.commands';
        case 'whatsapp': return 'https://wa.me/' + id.replace(/^\+/, '');
        case 'messenger': return 'https://m.me/' + id;
        case 'line': return 'https://line.me/R/ti/p/' + encodeURIComponent(id);
        case 'slack': return 'https://slack.com/apps/' + id;
        default: return '';
    }
}

function newBotKey() {
    const b = new Uint8Array(4);
    crypto.getRandomValues(b);
    return 'b' + Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
}

function normalizeBot(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const platform = SOCIAL_BOT_IDS.includes(raw.platform) ? raw.platform : 'other';
    const botId = normalizeBotId(platform, raw.botId) || '';
    const url = normalizeSocialUrl(raw.url) || '';
    const name = String(raw.name || '').replace(/[<>]/g, '').trim().slice(0, 60);
    if (!botId && !url) return null;
    return {
        key: /^b[0-9a-f]{8}$/.test(String(raw.key || '')) ? raw.key : newBotKey(),
        platform,
        name: name || botId || botPlatform(platform).label + ' bot',
        botId,
        url,
        about: String(raw.about || '').replace(/[<>]/g, '').trim().slice(0, 160),
        visible: raw.visible !== false
    };
}

function publicBots(cfg) {
    return ((cfg || socialCached()).bots || []).filter(b => b.visible);
}

function normalizeSocialConfig(raw) {
    const d = socialDefaults();
    const s = raw && typeof raw === 'object' ? raw : {};
    const links = {};
    for (const id of SOCIAL_IDS) {
        const v = normalizeSocialUrl(s.links && s.links[id]);
        if (v) links[id] = v;
    }
    const ch = s.channel && typeof s.channel === 'object' ? s.channel : {};
    const bots = (Array.isArray(s.bots) ? s.bots : []).map(normalizeBot).filter(Boolean).slice(0, SOCIAL_BOT_MAX);
    return {
        links,
        bots,
        showInFooter: s.showInFooter === true,
        showPage: s.showPage !== false,
        botButtons: s.botButtons !== false,
        channel: {
            chatId: normalizeChannelId(ch.chatId) || '',
            title: String(ch.title || '').slice(0, 120),
            inviteUrl: normalizeSocialUrl(ch.inviteUrl) || ''
        }
    };
}

async function getSocialConfig(env, fresh = false) {
    if (!fresh && __social.cfg && Date.now() - __social.at < 15000) return __social.cfg;
    let raw = null;
    try { raw = JSON.parse(await dbGetSetting(env, 'social_config', 'null')); } catch (_) {}
    const cfg = normalizeSocialConfig(raw);
    __social = { at: Date.now(), cfg };
    return cfg;
}

// Sync access for templates (footer, bot menu). Warmed per request by the router.
function socialCached() { return __social.cfg || socialDefaults(); }

async function saveSocialConfig(env, next) {
    const cfg = normalizeSocialConfig(next);
    const ok = await dbSetSetting(env, 'social_config', JSON.stringify(cfg));
    if (ok) __social = { at: Date.now(), cfg };
    return ok ? cfg : null;
}

// Public join link for the channel: explicit invite, else t.me/<username>.
function channelJoinUrl(cfg) {
    const c = (cfg || socialCached()).channel || {};
    if (c.inviteUrl) return c.inviteUrl;
    if (c.chatId && c.chatId.startsWith('@')) return 'https://t.me/' + c.chatId.slice(1);
    return '';
}

// ---------------------------------------------------------------- posts log
async function ensureSocialPostsSchema(env) {
    if (!env || !env.DB) return false;
    if (__socialPostsReady) return true;
    try {
        await env.DB.prepare(
            'CREATE TABLE IF NOT EXISTS social_posts (' +
            'id INTEGER PRIMARY KEY AUTOINCREMENT, network TEXT NOT NULL DEFAULT \'telegram\', chat_id TEXT NOT NULL, ' +
            'message_id INTEGER, text TEXT, posted_by TEXT, pinned INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0, ' +
            'created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)'
        ).run();
        await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_social_posts_created_at ON social_posts(created_at)').run();
        __socialPostsReady = true;
        return true;
    } catch (e) { __dbError = 'Social posts table: ' + dbErrText(e); return false; }
}

async function listSocialPosts(env, limit = 10) {
    if (!(await ensureSocialPostsSchema(env))) return [];
    try {
        const r = await env.DB.prepare('SELECT * FROM social_posts WHERE deleted = 0 ORDER BY id DESC LIMIT ?').bind(limit).all();
        return (r && r.results) || [];
    } catch (_) { return []; }
}

// ---------------------------------------------------------------- telegram helpers
async function tgCall(method, payload) {
    try {
        const r = await fetch(TELEGRAM_API + '/' + method, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload || {}) });
        return await r.json().catch(() => ({ ok: false, description: 'HTTP ' + r.status }));
    } catch (e) { return { ok: false, description: String((e && e.message) || e) }; }
}

async function checkTelegramBot(env, origin) {
    const s = await resolveTelegramSettings(env, origin, true);
    if (!s.tokenConfigured) return { ok: false, error: 'No bot token is configured yet.' };
    const me = await tgCall('getMe', {});
    if (!me.ok) return { ok: false, error: 'Telegram rejected the token: ' + (me.description || 'unknown error') };
    const wh = await tgCall('getWebhookInfo', {});
    const info = (wh && wh.result) || {};
    const expected = s.webhookUrl;
    let hook = 'not set';
    if (info.url) hook = info.url === expected ? 'connected' : 'points somewhere else (' + info.url + ')';
    const pending = info.pending_update_count ? ', ' + info.pending_update_count + ' pending' : '';
    const lastErr = info.last_error_message ? '. Last error: ' + info.last_error_message : '';
    return { ok: true, message: 'Bot @' + me.result.username + ' is online. Webhook ' + hook + pending + lastErr + '.' };
}

async function testTelegramChannel(env, origin, cfg) {
    const s = await resolveTelegramSettings(env, origin, true);
    if (!s.tokenConfigured) return { ok: false, error: 'Add the bot token first.' };
    const chatId = cfg.channel.chatId;
    if (!chatId) return { ok: false, error: 'Save a channel first (@username or -100… id).' };
    const chat = await tgCall('getChat', { chat_id: chatId });
    if (!chat.ok) return { ok: false, error: 'Telegram can’t find that channel: ' + (chat.description || 'unknown error') + '. Add the bot to the channel as an admin.' };
    const me = await tgCall('getMe', {});
    const member = me.ok ? await tgCall('getChatMember', { chat_id: chatId, user_id: me.result.id }) : { ok: false };
    const st = member.ok && member.result ? member.result.status : '';
    const canPost = st === 'creator' || (st === 'administrator' && member.result.can_post_messages !== false);
    const title = String(chat.result.title || chatId);
    if (title !== cfg.channel.title) await saveSocialConfig(env, { ...cfg, channel: { ...cfg.channel, title } });
    const count = await tgCall('getChatMemberCount', { chat_id: chatId });
    const subs = count.ok ? ' · ' + count.result + ' subscribers' : '';
    if (!canPost) return { ok: false, error: 'Found “' + title + '”' + subs + ', but the bot can’t post there. Make it an admin with “Post messages”.' };
    return { ok: true, message: 'Channel “' + title + '” connected' + subs + '. The bot can post.' };
}

async function postToTelegramChannel(env, origin, cfg, form, actor) {
    const s = await resolveTelegramSettings(env, origin, true);
    if (!s.tokenConfigured) return { ok: false, error: 'Add the bot token first.' };
    const chatId = cfg.channel.chatId;
    if (!chatId) return { ok: false, error: 'Save a channel first.' };
    const text = String(form.get('text') || '').trim();
    if (!text) return { ok: false, error: 'Write something to post.' };
    if (text.length > SOCIAL_POST_MAX) return { ok: false, error: 'Posts are limited to ' + SOCIAL_POST_MAX + ' characters.' };
    const format = String(form.get('format') || 'plain');
    const btnText = String(form.get('button_text') || '').trim().slice(0, 40);
    const btnUrlRaw = String(form.get('button_url') || '').trim();
    const btnUrl = btnUrlRaw ? normalizeSocialUrl(btnUrlRaw) : '';
    if (btnUrlRaw && !btnUrl) return { ok: false, error: 'The button link must be a public https:// URL.' };
    if ((btnText && !btnUrl) || (!btnText && btnUrl)) return { ok: false, error: 'Fill in both the button text and the button link, or leave both empty.' };
    const payload = { chat_id: chatId, text, disable_notification: form.get('silent') === '1', link_preview_options: { is_disabled: form.get('no_preview') === '1' } };
    if (format === 'html') payload.parse_mode = 'HTML';
    if (btnText && btnUrl) payload.reply_markup = { inline_keyboard: [[{ text: btnText, url: btnUrl }]] };
    const sent = await tgCall('sendMessage', payload);
    if (!sent.ok) return { ok: false, error: 'Telegram refused the post: ' + (sent.description || 'unknown error') + (format === 'html' ? '. Check the HTML tags.' : '') };
    const messageId = sent.result && sent.result.message_id;
    let pinned = 0;
    if (form.get('pin') === '1' && messageId) {
        const p = await tgCall('pinChatMessage', { chat_id: chatId, message_id: messageId, disable_notification: true });
        pinned = p.ok ? 1 : 0;
    }
    if (await ensureSocialPostsSchema(env)) {
        try {
            await env.DB.prepare('INSERT INTO social_posts (network, chat_id, message_id, text, posted_by, pinned) VALUES (?, ?, ?, ?, ?, ?)')
                .bind('telegram', chatId, messageId || null, text.slice(0, 1000), actor.username, pinned).run();
        } catch (_) {}
    }
    return { ok: true, message: 'Posted to the channel' + (pinned ? ' and pinned' : '') + '.' };
}

async function deleteTelegramChannelPost(env, origin, postId) {
    await resolveTelegramSettings(env, origin, true);
    if (!(await ensureSocialPostsSchema(env))) return { ok: false, error: 'The posts table is unavailable. Run Repair database.' };
    const row = await env.DB.prepare('SELECT * FROM social_posts WHERE id = ? AND deleted = 0').bind(parseInt(postId, 10) || 0).first().catch(() => null);
    if (!row) return { ok: false, error: 'That post was not found.' };
    const res = row.message_id ? await tgCall('deleteMessage', { chat_id: row.chat_id, message_id: row.message_id }) : { ok: true };
    await env.DB.prepare('UPDATE social_posts SET deleted = 1 WHERE id = ?').bind(row.id).run().catch(() => {});
    return res.ok ? { ok: true, message: 'Post deleted from the channel.' } : { ok: true, message: 'Removed from the log. Telegram said: ' + (res.description || 'could not delete') + ' (posts older than 48 h can’t be deleted by bots).' };
}

// One entry point for every Social form (POST ADMIN_PATH/social).
async function handleSocialAction(env, origin, user, form) {
    const action = String(form.get('action') || 'save');
    const cfg = await getSocialConfig(env, true);
    if (action === 'save') {
        const links = {};
        for (const n of SOCIAL_NETWORKS) {
            const raw = String(form.get('link_' + n.id) || '').trim();
            const v = normalizeSocialUrl(raw);
            if (raw && !v) return { ok: false, error: n.label + ': use a public https:// link.' };
            if (v) links[n.id] = v;
        }
        const saved = await saveSocialConfig(env, { ...cfg, links, showInFooter: form.get('show_footer') === '1', showPage: form.get('show_page') === '1', botButtons: form.get('bot_buttons') === '1' });
        return saved ? { ok: true, message: 'Social links saved.' } : { ok: false, error: 'Could not save social links. ' + (__dbError || 'D1 write error.') };
    }
    if (action === 'channel') {
        const rawId = String(form.get('channel_id') || '').trim();
        const chatId = normalizeChannelId(rawId);
        if (chatId === null) return { ok: false, error: 'Use @channelname, a t.me/channelname link, or the numeric -100… id.' };
        const rawInvite = String(form.get('invite_url') || '').trim();
        const inviteUrl = normalizeSocialUrl(rawInvite);
        if (rawInvite && !inviteUrl) return { ok: false, error: 'The invite link must be a public https:// URL.' };
        const saved = await saveSocialConfig(env, { ...cfg, channel: { chatId, title: chatId === cfg.channel.chatId ? cfg.channel.title : '', inviteUrl: inviteUrl || '' } });
        if (!saved) return { ok: false, error: 'Could not save the channel. ' + (__dbError || 'D1 write error.') };
        if (!chatId) return { ok: true, message: 'Channel removed.' };
        const test = await testTelegramChannel(env, origin, saved);
        return test.ok ? { ok: true, message: 'Channel saved. ' + test.message } : { ok: false, error: 'Channel saved, but: ' + test.error };
    }
    if (action === 'bots') {
        const keys = form.getAll('bot_key').map(String);
        const plats = form.getAll('bot_platform').map(String);
        const names = form.getAll('bot_name').map(String);
        const ids = form.getAll('bot_id').map(String);
        const urls = form.getAll('bot_url').map(String);
        const abouts = form.getAll('bot_about').map(String);
        const bots = [];
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            if (form.get('bot_remove_' + key) === '1') continue;
            const platform = SOCIAL_BOT_IDS.includes(plats[i]) ? plats[i] : 'other';
            const p = botPlatform(platform);
            const rawId = String(ids[i] || '').trim(), rawUrl = String(urls[i] || '').trim(), name = String(names[i] || '').trim();
            if (!rawId && !rawUrl && !name) continue; // empty "add" row
            const botId = normalizeBotId(platform, rawId);
            if (botId === null) return { ok: false, error: (name || p.label) + ': that doesn’t look like a valid ' + p.label + ' ' + p.idLabel + ' (e.g. ' + p.ph + ').' };
            const url = rawUrl ? normalizeSocialUrl(rawUrl) : '';
            if (rawUrl && !url) return { ok: false, error: (name || p.label) + ': the link must be a public https:// URL.' };
            if (!botId && !url) return { ok: false, error: (name || p.label) + ': add the ' + p.idLabel.toLowerCase() + ' or a link.' };
            const bot = normalizeBot({ key: key === 'new' ? '' : key, platform, name, botId, url, about: abouts[i], visible: form.get('bot_show_' + key) === '1' });
            if (bot) bots.push(bot);
        }
        if (bots.length > SOCIAL_BOT_MAX) return { ok: false, error: 'Up to ' + SOCIAL_BOT_MAX + ' bots.' };
        const saved = await saveSocialConfig(env, { ...cfg, bots });
        return saved ? { ok: true, message: bots.length ? 'Bots saved (' + bots.length + ').' : 'Bots cleared.' } : { ok: false, error: 'Could not save bots. ' + (__dbError || 'D1 write error.') };
    }
    if (action === 'bot_import_tg') {
        const s = await resolveTelegramSettings(env, origin, true);
        if (!s.tokenConfigured) return { ok: false, error: 'Add the Telegram bot token first.' };
        const me = await tgCall('getMe', {});
        if (!me.ok || !me.result || !me.result.username) return { ok: false, error: 'Telegram rejected the token: ' + (me.description || 'unknown error') };
        const handle = '@' + me.result.username;
        if ((cfg.bots || []).some(b => b.platform === 'telegram' && String(b.botId).toLowerCase() === handle.toLowerCase())) return { ok: true, message: handle + ' is already in your bots.' };
        if ((cfg.bots || []).length >= SOCIAL_BOT_MAX) return { ok: false, error: 'Up to ' + SOCIAL_BOT_MAX + ' bots. Remove one first.' };
        const bot = normalizeBot({ platform: 'telegram', name: me.result.first_name || 'VexoStream bot', botId: handle, about: 'Search and play videos right inside Telegram.', visible: true });
        const saved = await saveSocialConfig(env, { ...cfg, bots: [bot].concat(cfg.bots || []) });
        return saved ? { ok: true, message: 'Added ' + handle + ' to your bots.' } : { ok: false, error: 'Could not save bots. ' + (__dbError || 'D1 write error.') };
    }
    if (action === 'test_channel') { const r = await testTelegramChannel(env, origin, cfg); return r.ok ? r : { ok: false, error: r.error }; }
    if (action === 'post') return postToTelegramChannel(env, origin, cfg, form, user);
    if (action === 'delete_post') return deleteTelegramChannelPost(env, origin, form.get('post_id'));
    if (action === 'check_bot') return checkTelegramBot(env, origin);
    return { ok: false, error: 'Unknown action.' };
}

// ---------------------------------------------------------------- public footer row
function socialChip(href, icon, label, extraClass = '') {
    return '<a class="sx-chip' + extraClass + '" href="' + escapeHtml(href) + '" target="_blank" rel="noopener nofollow" style="--c:' + socialColor(icon) + '"' + (extraClass ? '' : ' aria-label="' + escapeHtml(label) + '" title="' + escapeHtml(label) + '"') + '>' + socialIcon(icon) + (extraClass ? '<span>' + escapeHtml(label) + '</span>' : '') + '</a>';
}

// Footer: Follow = round brand icons, Bots = named pills.
function renderSocialFooterRow() {
    const cfg = socialCached();
    if (!cfg.showInFooter) return '';
    const items = SOCIAL_NETWORKS.filter(n => cfg.links[n.id]).map(n => socialChip(cfg.links[n.id], n.id, n.label));
    const join = channelJoinUrl(cfg);
    if (join && !cfg.links.telegram) items.unshift(socialChip(join, 'telegram', 'Telegram channel'));
    const bots = publicBots(cfg).filter(b => botLink(b)).map(b => socialChip(botLink(b), b.platform, b.name, ' is-bot'));
    let out = '';
    if (items.length) out += '<nav class="gfoot-social" aria-label="Follow us">' + items.join('') + '</nav>';
    if (bots.length) out += '<nav class="gfoot-bots" aria-label="Our bots">' + bots.join('') + '</nav>';
    return out;
}

// ---------------------------------------------------------------- bot text
function socialBotText(cfg) {
    const c = cfg || socialCached();
    const lines = SOCIAL_NETWORKS.filter(n => c.links[n.id]).map(n => '• ' + md(n.label) + ': ' + md(c.links[n.id]));
    const join = channelJoinUrl(c);
    if (join) lines.unshift('• Channel: ' + md(join));
    const bots = publicBots(c).map(b => '• ' + md(b.name) + ' (' + md(botPlatform(b.platform).label) + ')' + (botLink(b) ? ': ' + md(botLink(b)) : b.botId ? ': ' + md(b.botId) : ''));
    if (!lines.length && !bots.length) return 'No social links have been set up yet.';
    return (lines.length ? '*Follow VexoStream*\n\n' + lines.join('\n') : '') + (bots.length ? (lines.length ? '\n\n' : '') + '*Our bots*\n\n' + bots.join('\n') : '');
}

// ---------------------------------------------------------------- admin cards
function renderSocialCards(cfg, posts = []) {
    cfg = cfg || socialDefaults();
    const join = channelJoinUrl(cfg);
    const chPill = cfg.channel.chatId
        ? '<span class="hpill"><i></i>' + escapeHtml(cfg.channel.title || cfg.channel.chatId) + '</span>'
        : '<span class="hpill bad"><i></i>No channel</span>';
    const channel = '<section class="card span" id="tg-channel"><div class="card-head"><div><div class="card-kicker">TELEGRAM CHANNEL</div><h2>Channel</h2><p>Add the bot to your channel as an admin with “Post messages”, then save the channel here.</p></div><div class="health">' + chPill + '</div></div>' +
        '<form method="POST" action="' + ADMIN_PATH + '/social"><input type="hidden" name="action" value="channel"><div class="prov-opts">' +
        '<label class="opt"><span>Channel</span><input name="channel_id" maxlength="64" value="' + escapeHtml(cfg.channel.chatId) + '" placeholder="@yourchannel or -1001234567890" autocomplete="off" spellcheck="false"></label>' +
        '<label class="opt"><span>Invite link (private channels)</span><input type="url" name="invite_url" maxlength="240" value="' + escapeHtml(cfg.channel.inviteUrl) + '" placeholder="https://t.me/+AbCdEf…" autocomplete="off" spellcheck="false"></label>' +
        '</div><p class="backend-note">Public join link: <code>' + escapeHtml(join || 'none yet') + '</code>. Leave Channel empty and save to disconnect.</p>' +
        '<div class="actions-row"><button class="btn sm" type="submit">Save channel</button></div></form>' +
        '<div class="links"><form method="POST" action="' + ADMIN_PATH + '/social"><input type="hidden" name="action" value="test_channel"><button class="btn quiet sm" type="submit">Test channel</button></form>' +
        (join ? '<a class="btn quiet sm" href="' + escapeHtml(join) + '" target="_blank" rel="noopener">Open channel</a>' : '') + '</div></section>';

    const composer = '<section class="card span" id="tg-post"><div class="card-kicker">TELEGRAM CHANNEL</div><h2>Post to channel</h2><p>Sends as the bot. HTML allows &lt;b&gt;, &lt;i&gt;, &lt;a href&gt;, &lt;code&gt;.</p>' +
        '<form method="POST" action="' + ADMIN_PATH + '/social" class="social-post"><input type="hidden" name="action" value="post">' +
        '<label class="opt span"><span>Message</span><textarea name="text" rows="5" maxlength="' + SOCIAL_POST_MAX + '" required placeholder="New on VexoStream…"></textarea></label>' +
        '<div class="prov-opts">' +
        '<label class="opt"><span>Format</span><select name="format"><option value="plain">Plain text</option><option value="html">HTML</option></select></label>' +
        '<label class="opt"><span>Button text (optional)</span><input name="button_text" maxlength="40" placeholder="Watch now" autocomplete="off"></label>' +
        '<label class="opt span"><span>Button link (optional)</span><input type="url" name="button_url" maxlength="240" placeholder="https://your-site.com/watch?..." autocomplete="off" spellcheck="false"></label>' +
        '</div><div class="social-flags">' +
        '<label><input type="checkbox" name="silent" value="1"> Send silently</label>' +
        '<label><input type="checkbox" name="pin" value="1"> Pin after posting</label>' +
        '<label><input type="checkbox" name="no_preview" value="1"> No link preview</label>' +
        '</div><div class="actions-row"><button class="btn sm" type="submit"' + (cfg.channel.chatId ? '' : ' disabled title="Save a channel first"') + '>Post now</button></div></form></section>';

    const rows = (posts || []).map(p => '<li class="social-log-row"><div><b>' + escapeHtml(String(p.text || '').slice(0, 140)) + (String(p.text || '').length > 140 ? '…' : '') + '</b>' +
        '<small>' + escapeHtml(String(p.created_at || '')) + ' UTC · ' + escapeHtml(String(p.posted_by || '')) + (Number(p.pinned) ? ' · pinned' : '') + '</small></div>' +
        '<form method="POST" action="' + ADMIN_PATH + '/social" data-confirm="Delete this post from the channel?"><input type="hidden" name="action" value="delete_post"><input type="hidden" name="post_id" value="' + Number(p.id) + '"><button class="btn danger sm" type="submit">Delete</button></form></li>').join('');
    const log = '<section class="card span"><div class="card-kicker">TELEGRAM CHANNEL</div><h2>Recent posts</h2>' +
        (rows ? '<ul class="social-log">' + rows + '</ul>' : '<p>No posts yet.</p>') + '</section>';

    const linkInputs = SOCIAL_NETWORKS.map(n => '<label class="opt"><span>' + escapeHtml(n.label) + '</span><input type="url" inputmode="url" name="link_' + n.id + '" maxlength="240" value="' + escapeHtml(cfg.links[n.id] || '') + '" placeholder="' + escapeHtml(n.ph) + '" autocomplete="off" spellcheck="false"></label>').join('');
    const links = '<section class="card span" id="social-links"><div class="card-kicker">SOCIAL LINKS</div><h2>Social accounts</h2><p>Links shown in the site footer and in the bot’s /social command. Leave a field empty to hide it.</p>' +
        '<form method="POST" action="' + ADMIN_PATH + '/social"><input type="hidden" name="action" value="save"><div class="prov-opts">' + linkInputs + '</div>' +
        '<div class="social-flags">' +
        '<label><input type="checkbox" name="show_page" value="1"' + (cfg.showPage ? ' checked' : '') + '> Show “Social” in the header, burger menu &amp; footer</label>' +
        '<label><input type="checkbox" name="show_footer" value="1"' + (cfg.showInFooter ? ' checked' : '') + '> Show icons in site footer</label>' +
        '<label><input type="checkbox" name="bot_buttons" value="1"' + (cfg.botButtons ? ' checked' : '') + '> Show “Join channel” + Socials in the bot menu</label>' +
        '</div><div class="actions-row"><button class="btn sm" type="submit">Save social links</button></div></form></section>';
    return channel + composer + log + links + renderBotsCard(cfg);
}

function renderBotRow(b, isNew) {
    const key = isNew ? 'new' : b.key;
    const p = botPlatform(b.platform);
    const opts = SOCIAL_BOT_PLATFORMS.map(x => '<option value="' + x.id + '"' + (x.id === b.platform ? ' selected' : '') + '>' + escapeHtml(x.label) + '</option>').join('');
    const link = isNew ? '' : botLink(b);
    return '<fieldset class="bot-row' + (isNew ? ' is-new' : '') + '" data-bot-row>' +
        '<legend>' + (isNew ? '<b>Add a bot</b>' : '<span class="bot-badge" style="--c:' + socialColor(b.platform) + '">' + socialIcon(b.platform) + '</span><b>' + escapeHtml(b.name) + '</b>' + (b.visible ? '' : '<span class="hpill bad"><i></i>Hidden</span>')) + '</legend>' +
        '<input type="hidden" name="bot_key" value="' + escapeHtml(key) + '">' +
        '<div class="prov-opts bot-grid">' +
        '<label class="opt"><span>Platform</span><select name="bot_platform" data-bot-platform>' + opts + '</select></label>' +
        '<label class="opt"><span>Name</span><input name="bot_name" maxlength="60" value="' + escapeHtml(isNew ? '' : b.name) + '" placeholder="VexoStream Bot" autocomplete="off"></label>' +
        '<label class="opt"><span data-bot-idlabel>' + escapeHtml(p.idLabel) + '</span><input name="bot_id" maxlength="120" value="' + escapeHtml(b.botId || '') + '" placeholder="' + escapeHtml(p.ph) + '" data-bot-id autocomplete="off" spellcheck="false" dir="ltr"></label>' +
        '<label class="opt"><span>Custom link (optional)</span><input type="url" name="bot_url" maxlength="240" value="' + escapeHtml(b.url || '') + '" placeholder="https://…" autocomplete="off" spellcheck="false"></label>' +
        '<label class="opt span"><span>Short description (optional)</span><input name="bot_about" maxlength="160" value="' + escapeHtml(b.about || '') + '" placeholder="Search and play videos right inside the chat." autocomplete="off"></label>' +
        '</div><p class="backend-note" data-bot-hint>' + escapeHtml(p.hint) + (link ? ' Public link: <code>' + escapeHtml(link) + '</code>' : '') + '</p>' +
        '<div class="social-flags">' +
        '<label><input type="checkbox" name="bot_show_' + escapeHtml(key) + '" value="1"' + (b.visible ? ' checked' : '') + '> Show on site</label>' +
        (isNew ? '' : '<label class="bot-remove"><input type="checkbox" name="bot_remove_' + escapeHtml(key) + '" value="1"> Remove</label>') +
        '</div></fieldset>';
}

function renderBotsCard(cfg) {
    const bots = cfg.bots || [];
    const full = bots.length >= SOCIAL_BOT_MAX;
    const rows = bots.map(b => renderBotRow(b, false)).join('') + (full ? '' : renderBotRow({ platform: 'telegram', botId: '', url: '', about: '', visible: true }, true));
    const hints = JSON.stringify(SOCIAL_BOT_PLATFORMS.map(x => ({ id: x.id, idLabel: x.idLabel, ph: x.ph, hint: x.hint }))).replace(/</g, '\\u003c');
    return '<section class="card span" id="social-bots"><div class="card-head"><div><div class="card-kicker">BOTS</div><h2>Bots</h2><p>Add your Telegram, Discord and other bots by ID. Visitors see them on the Social page, in the burger menu and the footer.</p></div>' +
        '<div class="health"><span class="hpill' + (bots.length ? '' : ' bad') + '"><i></i>' + bots.length + ' / ' + SOCIAL_BOT_MAX + '</span></div></div>' +
        '<form method="POST" action="' + ADMIN_PATH + '/social" class="bots-form"><input type="hidden" name="action" value="bots">' + rows +
        '<div class="actions-row"><button class="btn sm" type="submit">Save bots</button><a class="btn quiet sm" href="/social" target="_blank" rel="noopener">View Social page</a></div></form>' +
        '<div class="links"><form method="POST" action="' + ADMIN_PATH + '/social"><input type="hidden" name="action" value="bot_import_tg"><button class="btn quiet sm" type="submit"' + (full ? ' disabled' : '') + '>Add this site’s Telegram bot</button></form></div>' +
        '<script type="application/json" id="botPlatforms">' + hints + '</script></section>';
}

const SOCIAL_ADMIN_JS = String.raw`
(function(){
  var data = document.getElementById('botPlatforms'); if (!data) return;
  var map = {}; try { JSON.parse(data.textContent).forEach(function(p){ map[p.id] = p; }); } catch (e) { return; }
  document.querySelectorAll('[data-bot-row]').forEach(function(row){
    var sel = row.querySelector('[data-bot-platform]'), lab = row.querySelector('[data-bot-idlabel]'), inp = row.querySelector('[data-bot-id]'), hint = row.querySelector('[data-bot-hint]');
    if (!sel) return;
    sel.addEventListener('change', function(){ var p = map[sel.value]; if (!p) return; lab.textContent = p.idLabel; inp.placeholder = p.ph; hint.textContent = p.hint; });
    var rm = row.querySelector('.bot-remove input');
    if (rm) rm.addEventListener('change', function(){ row.classList.toggle('is-removing', rm.checked); });
  });
})();
`;


// ---------------------------------------------------------------- platform marks
// Real brand marks live in assets/icons/*.svg (Simple Icons, CC0; globe + bot
// from Lucide). The build embeds them as SOCIAL_ICON_FILES (currentColor).
const SOCIAL_ICON_ALIAS = { other: 'bot' };
const SOCIAL_COLORS = {
    telegram: 'oklch(0.64 0.14 236)', discord: 'oklch(0.57 0.2 277)', x: 'oklch(0.24 0.01 262)', instagram: 'oklch(0.6 0.22 0)',
    youtube: 'oklch(0.6 0.23 27)', tiktok: 'oklch(0.24 0.01 262)', reddit: 'oklch(0.65 0.21 38)', whatsapp: 'oklch(0.66 0.17 150)',
    facebook: 'oklch(0.55 0.19 262)', messenger: 'oklch(0.58 0.23 290)', line: 'oklch(0.68 0.2 145)', slack: 'oklch(0.42 0.13 330)',
    viber: 'oklch(0.5 0.18 300)', website: 'oklch(0.55 0.215 258)', other: 'oklch(0.55 0.215 258)'
};
function socialIcon(id) { const k = SOCIAL_ICON_ALIAS[id] || id; return SOCIAL_ICON_FILES[k] || SOCIAL_ICON_FILES.bot || ''; }
function socialColor(id) { return SOCIAL_COLORS[id] || SOCIAL_COLORS.other; }
function socialHasContent(cfg) {
    const c = cfg || socialCached();
    return Object.keys(c.links || {}).length > 0 || publicBots(c).length > 0 || !!channelJoinUrl(c);
}
function prettyUrl(u) {
    try { const x = new URL(u); return (x.hostname.replace(/^www\./, '') + x.pathname.replace(/\/$/, '')).slice(0, 48); } catch (_) { return u; }
}

// ---------------------------------------------------------------- burger menu block
function renderSocialDrawerBlock() {
    const cfg = socialCached();
    if (!cfg.showPage || !socialHasContent(cfg)) return '';
    const join = channelJoinUrl(cfg);
    const chips = SOCIAL_NETWORKS.filter(n => cfg.links[n.id]).map(n =>
        '<a class="vxd-ic" href="' + escapeHtml(cfg.links[n.id]) + '" target="_blank" rel="noopener nofollow" aria-label="' + escapeHtml(n.label) + '" title="' + escapeHtml(n.label) + '" style="--c:' + socialColor(n.id) + '">' + socialIcon(n.id) + '</a>');
    if (join && !cfg.links.telegram) chips.unshift('<a class="vxd-ic" href="' + escapeHtml(join) + '" target="_blank" rel="noopener nofollow" aria-label="Telegram channel" title="Telegram channel" style="--c:' + socialColor('telegram') + '">' + socialIcon('telegram') + '</a>');
    const bots = publicBots(cfg).slice(0, 4).map(b => {
        const href = botLink(b) || '/social#bots';
        const ext = /^https:/.test(href);
        return '<a class="vxd-bot" href="' + escapeHtml(href) + '"' + (ext ? ' target="_blank" rel="noopener nofollow"' : '') + ' style="--c:' + socialColor(b.platform) + '"><span class="vxd-bot-mk">' + socialIcon(b.platform) + '</span><span><b>' + escapeHtml(b.name) + '</b><small>' + escapeHtml(botPlatform(b.platform).label + ' bot') + '</small></span></a>';
    });
    return '<div class="vxd-sec"><p class="vxd-label">Social media</p>' +
        (chips.length ? '<div class="vxd-ics">' + chips.join('') + '</div>' : '') +
        (bots.length ? '<div class="vxd-bots">' + bots.join('') + '</div>' : '') +
        '<a class="vxd-more" href="/social">All socials &amp; bots' + ICONS.arrow + '</a></div>';
}

// ---------------------------------------------------------------- public /social page
function renderSocialPageHtml(meta, cfg) {
    cfg = cfg || socialCached();
    const join = channelJoinUrl(cfg);
    const bots = publicBots(cfg);
    const links = SOCIAL_NETWORKS.filter(n => cfg.links[n.id]);

    // Signature: the strip of every network we are on, gently floating under the headline.
    const strip = links.length ? '<div class="sx-strip" aria-hidden="true">' + links.map((n, i) =>
        '<span class="sx-strip-i" style="--c:' + socialColor(n.id) + ';--i:' + i + '">' + socialIcon(n.id) + '</span>').join('') + '</div>' : '';

    const onAir = join ? '<section class="sx-air reveal" style="--i:0"><span class="vf vf-tl"></span><span class="vf vf-tr"></span><span class="vf vf-bl"></span><span class="vf vf-br"></span><span class="sx-scan" aria-hidden="true"></span>' +
        '<p class="sx-tally"><i></i>On air · Telegram channel</p><h2>' + escapeHtml(cfg.channel.title || (cfg.channel.chatId.startsWith('@') ? cfg.channel.chatId : 'VexoStream channel')) + '</h2><p class="sx-air-sub">New drops, provider status and picks, first.</p>' +
        '<a class="btn sx-air-btn" href="' + escapeHtml(join) + '" target="_blank" rel="noopener nofollow">' + socialIcon('telegram') + '<span>Join channel</span></a></section>' : '';

    const botCards = bots.map((b, i) => {
        const p = botPlatform(b.platform);
        const href = botLink(b);
        return '<article class="sx-bot reveal" style="--c:' + socialColor(b.platform) + ';--i:' + i + '">' +
            '<span class="sx-mk">' + socialIcon(b.platform) + '</span><span class="sx-plat">' + escapeHtml(p.label) + ' bot</span>' +
            '<h3>' + escapeHtml(b.name) + '</h3>' +
            (b.about ? '<p>' + escapeHtml(b.about) + '</p>' : '') +
            '<div class="sx-bot-foot">' +
            (b.botId ? '<button class="sx-id" type="button" data-copy="' + escapeHtml(b.botId) + '" title="Copy ' + escapeHtml(p.idLabel.toLowerCase()) + '"><code>' + escapeHtml(b.botId) + '</code>' + ICONS.copy + '</button>' : '') +
            (href ? '<a class="btn sm sx-go" href="' + escapeHtml(href) + '" target="_blank" rel="noopener nofollow"><span>' + escapeHtml(p.cta) + '</span>' + ICONS.arrow + '</a>' : '') +
            '</div></article>';
    }).join('');

    const linkTiles = links.map((n, i) => '<a class="sx-tile reveal" href="' + escapeHtml(cfg.links[n.id]) + '" target="_blank" rel="noopener nofollow" style="--c:' + socialColor(n.id) + ';--i:' + i + '">' +
        '<span class="sx-mk">' + socialIcon(n.id) + '</span><b>' + escapeHtml(n.label) + '</b><small>' + escapeHtml(prettyUrl(cfg.links[n.id])) + '</small><span class="sx-tile-go" aria-hidden="true">' + ICONS.arrow + '</span></a>').join('');

    const head = (id, title, count) => '<div class="sx-sec-head"><h2 class="sx-h" id="' + id + '-h">' + title + '</h2><span class="sx-count">' + count + '</span></div>';
    const empty = !onAir && !botCards && !linkTiles;
    return renderHead({ meta }) +
        '<body>' + renderNav('social') +
        '<main class="page sx">' +
        '<section class="sx-hero"><div class="wrap-wide"><p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span><span>Social media</span></p>' +
        '<h1 class="sx-title">Find us everywhere.</h1><p class="sx-sub">Our bots, channel and accounts. Same VexoStream, wherever you hang out.</p>' + strip + '</div></section>' +
        '<div class="wrap-wide sx-body">' + onAir +
        (botCards ? '<section class="sx-sec" id="bots" aria-labelledby="bots-h">' + head('bots', 'Bots', bots.length + (bots.length === 1 ? ' bot' : ' bots')) + '<div class="sx-bots">' + botCards + '</div></section>' : '') +
        (linkTiles ? '<section class="sx-sec" id="accounts" aria-labelledby="accounts-h">' + head('accounts', 'Accounts', links.length + ' linked') + '<div class="sx-tiles">' + linkTiles + '</div></section>' : '') +
        (empty ? '<div class="sx-empty"><span class="sx-mk" style="--c:' + socialColor('other') + '">' + socialIcon('other') + '</span><b>Nothing here yet.</b><p>Our bots and socials are on the way.</p><a class="btn quiet sm" href="/">Back to home</a></div>' : '') +
        '</div></main>' + renderFooter() +
        '<script>' + COMMON_JS + SOCIAL_PAGE_JS + '</script></body></html>';
}

const SOCIAL_PAGE_JS = String.raw`
(function(){
  document.querySelectorAll('[data-copy]').forEach(function(b){
    b.addEventListener('click', function(){
      var v = b.getAttribute('data-copy');
      window.copyText(v).then(function(){ b.classList.remove('ok'); void b.offsetWidth; b.classList.add('ok'); window.toast('Copied ' + v); setTimeout(function(){ b.classList.remove('ok'); }, 1400); }).catch(function(){ window.toast('Could not copy'); });
    });
  });
})();
`;

