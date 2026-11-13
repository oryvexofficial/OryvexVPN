// TELEGRAM BOT
// ============================================================================
const KNOWN_PROVIDERS = PROVIDERS.map(p => p.id);

function tg(method, payload) {
    return fetch(TELEGRAM_API + '/' + method, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });
}

// Legacy Markdown: escape the four control characters in user/remote text
function md(text) {
    return String(text === null || text === undefined ? '' : text).replace(/([_*`\[])/g, '\\$1');
}

function sendOrEdit(chatId, messageId, payload) {
    return messageId
        ? tg('editMessageText', { chat_id: chatId, message_id: messageId, ...payload })
        : tg('sendMessage', { chat_id: chatId, ...payload });
}

// Optional "Join channel" / "Socials" row from Admin > Social media
function socialMenuRows() {
    const c = socialCached();
    if (!c.botButtons) return [];
    const row = [];
    const join = channelJoinUrl(c);
    if (join) row.push({ text: 'Join our channel', url: join });
    if (Object.keys(c.links || {}).length || publicBots(c).length) row.push({ text: 'Socials', callback_data: 'menu_social' });
    return row.length ? [row] : [];
}

// callback_data is capped at 64 bytes by Telegram
function pageCallback(page, provider, query) {
    let q = String(query);
    const make = () => 'tgpage_' + page + '_' + provider + '_' + encodeURIComponent(q);
    while (q.length && new TextEncoder().encode(make()).length > 64) q = q.slice(0, -1);
    return make();
}

const UI_MENUS = {
    main: (origin) => ({
        text: '*VexoStream*\n_Every quality, straight from the edge._\n\nPaste a supported video link or viewkey to open the player.\n\n*Commands*\n• `/search <query>` or `/search <provider> <query>`\n• `/models [name]` for public performer listings\n• `/status` pipeline health\n• `/social` our channel and socials',
        reply_markup: {
            inline_keyboard: [
                [{ text: 'Trending', callback_data: 'menu_quick_search' }, { text: 'Providers', callback_data: 'menu_providers' }],
                [{ text: 'Public model directory', url: (origin || 'https://vexostream.bond') + '/models' }],
                [{ text: 'Pipeline status', callback_data: 'menu_status' }, { text: 'Help', callback_data: 'menu_help' }],
                [{ text: 'Open VexoStream', url: (origin || 'https://vexostream.bond') + '/' }]
            ].concat(socialMenuRows())
        }
    }),
    help: () => ({
        text: '*How to use VexoStream*\n\n*1. Play a link*\nPaste a link from a currently supported provider, or a Pornhub viewkey.\n\n*2. Search*\n`/search <keyword>` or `/search <provider> <keyword>`\n\n*3. Browse profiles*\nUse `/models [name]` for public performer-directory listings. This does not access paid or private OnlyFans content.\n\n*4. Watch or embed*\nOpen the web player or copy the responsive embed.',
        reply_markup: { inline_keyboard: [[{ text: '‹ Back', callback_data: 'menu_main' }]] }
    }),
    providers: (origin, cfg) => ({
        text: '*Providers*\n\n' + listedProviders(cfg || normalizeProviderConfig(null)).map(p => '• *' + md(p.name) + '* ' + (p.mode === 'live' ? 'live' : 'currently unavailable')).join('\n'),
        reply_markup: { inline_keyboard: [[{ text: '‹ Back', callback_data: 'menu_main' }]] }
    }),
    social: () => ({
        text: socialBotText(),
        disable_web_page_preview: true,
        reply_markup: { inline_keyboard: [[{ text: '‹ Back', callback_data: 'menu_main' }]] }
    }),
    status: (origin, checks) => {
        const line = (name, k) => '• *' + name + ':* ' + (checks ? STATUS_LABELS[checks[k]] : 'Checking');
        return {
            text: '*Pipeline status*\n\n' + line('Edge API', 'edge') + '\n' + line('Extraction core', 'extract') + '\n' + line('Media proxy', 'proxy') + '\n' + line('Telegram bot', 'telegram'),
            reply_markup: { inline_keyboard: [[{ text: 'Status page', url: (origin || 'https://vexostream.bond') + '/status' }], [{ text: '‹ Back', callback_data: 'menu_main' }]] }
        };
    }
};

async function setupTelegramCommands() {
    return tg('setMyCommands', {
        commands: [
            { command: 'start', description: 'Main menu' },
            { command: 'menu', description: 'Open the menu' },
            { command: 'search', description: 'Search videos: /search <provider> <query>' },
            { command: 'models', description: 'Search public performer profiles' },
            { command: 'status', description: 'Pipeline health' },
            { command: 'social', description: 'Our channel and social accounts' }
        ]
    });
}

async function setupTelegramWebhook(origin, env) {
    const settings = await resolveTelegramSettings(env, origin, true);
    const secret = await telegramWebhookSecret();
    const webhookOrigin = settings.webhookOrigin || origin;
    const res = await tg('setWebhook', { url: webhookOrigin.replace(/\/+$/, '') + '/webhook', secret_token: secret, allowed_updates: ['message', 'callback_query'], drop_pending_updates: false });
    const data = await res.json().catch(() => ({ ok: false }));
    await setupTelegramCommands().catch(() => {});
    return data;
}

function parseInputToTargetUrl(raw) {
    const trimmed = raw.trim();
    if (/^https?:\/\//i.test(trimmed)) return trimmed;
    const m = trimmed.match(/viewkey=([a-zA-Z0-9]+)/) || trimmed.match(/^([a-zA-Z0-9]{8,24})$/);
    if (m) return 'https://www.pornhub.com/view_video.php?viewkey=' + m[1];
    return trimmed;
}

async function performTelegramSearch(chatId, query, provider = 'pornhub', page = 1, messageId = null, origin) {
    try {
        const res = await timedFetch(RAILWAY_URL + '/api/explore?q=' + encodeURIComponent(query) + '&page=' + page + '&provider=' + encodeURIComponent(provider), {
            headers: { 'X-Edge-Token': EDGE_TOKEN, 'User-Agent': 'Mozilla/5.0 (VexoStream Telegram Client)' }
        }, 30000);
        if (!res.ok) {
            await sendOrEdit(chatId, messageId, { text: 'Search backend answered HTTP ' + res.status + '. Try another query.' });
            return;
        }
        const items = await res.json();
        if (!Array.isArray(items) || items.length === 0) {
            await sendOrEdit(chatId, messageId, {
                text: 'No videos for *' + md(query) + '* on *' + md(provider) + '* (page ' + page + ').',
                parse_mode: 'Markdown',
                reply_markup: { inline_keyboard: [[{ text: '‹ Main menu', callback_data: 'menu_main' }]] }
            });
            return;
        }
        const keyboard = [];
        for (const item of items.slice(0, 5)) {
            if (!item || !item.url) continue;
            const t = String(item.title || 'Watch video');
            keyboard.push([{ text: (t.length > 40 ? t.slice(0, 40) + '…' : t), url: origin + '/video/' + b64urlEncode(item.url) }]);
        }
        const nav = [];
        if (page > 1) nav.push({ text: '‹ Prev', callback_data: pageCallback(page - 1, provider, query) });
        if (items.length >= 5) nav.push({ text: 'Next ›', callback_data: pageCallback(page + 1, provider, query) });
        if (nav.length) keyboard.push(nav);
        keyboard.push([{ text: 'Main menu', callback_data: 'menu_main' }]);
        await sendOrEdit(chatId, messageId, {
            text: '*Results for* ' + md(query) + '\n*Provider:* `' + md(provider) + '` · *Page:* `' + page + '`\n\nPick a title to open the player:',
            parse_mode: 'Markdown',
            reply_markup: { inline_keyboard: keyboard }
        });
    } catch (err) {
        await tg('sendMessage', { chat_id: chatId, text: 'Search failed: ' + String((err && err.message) || err) }).catch(() => {});
    }
}

async function performTelegramModelSearch(chatId, query, origin) {
    try {
        const params = new URLSearchParams({ gender: 'Female', sort: 'popularity', page: '1' });
        if (query) params.set('search', query.slice(0, 80));
        const res = await timedFetch(RAILWAY_URL + '/api/models?' + params.toString(), {
            headers: { 'X-Edge-Token': EDGE_TOKEN, 'User-Agent': 'Mozilla/5.0 (VexoStream Telegram Client)' }
        }, 30000);
        if (!res.ok) {
            await tg('sendMessage', { chat_id: chatId, text: 'Model directory answered HTTP ' + res.status + '. Try again later.' });
            return;
        }
        const data = await res.json();
        const models = data && Array.isArray(data.models) ? data.models : [];
        if (!models.length) {
            await tg('sendMessage', { chat_id: chatId, text: 'No public profiles found' + (query ? ' for ' + query : '') + '. Open /models for the full directory.' });
            return;
        }
        const keyboard = [];
        for (const model of models.slice(0, 8)) {
            if (!model || !/^[a-zA-Z0-9][a-zA-Z0-9-]{0,119}$/.test(String(model.slug || ''))) continue;
            const name = String(model.name || 'View profile').slice(0, 50);
            keyboard.push([{ text: name, url: origin + '/models/' + encodeURIComponent(model.slug) }]);
        }
        keyboard.push([{ text: 'Open full directory', url: origin + '/models' }]);
        await tg('sendMessage', {
            chat_id: chatId,
            text: '*Public performer profiles*' + (query ? ' matching *' + md(query) + '*' : '') + '\n\nThese are public directory listings. The bot does not fetch paid or private OnlyFans content.',
            parse_mode: 'Markdown',
            reply_markup: { inline_keyboard: keyboard }
        });
    } catch (err) {
        await tg('sendMessage', { chat_id: chatId, text: 'Model directory failed: ' + String((err && err.message) || err) }).catch(() => {});
    }
}

async function handleTelegramMessage(request, origin, ctx, env) {
    await resolveTelegramSettings(env, origin, true);
    // Telegram echoes the secret_token we registered in /setup
    const expected = await telegramWebhookSecret();
    if (!timingSafeEqual(request.headers.get('X-Telegram-Bot-Api-Secret-Token') || '', expected)) {
        return new Response('Forbidden', { status: 403 });
    }
    try {
        const body = await request.json();
        const pcfg = await getProviderConfig(env);
        const defP = defaultProviderOf(pcfg);
        const lockedText = (id) => '*' + md(providerName(id)) + ' is currently unavailable.*\n' + md(pcfg.lockMessage);
        const hiddenText = '*This provider is unavailable.*';

        if (body.callback_query) {
            const cb = body.callback_query;
            const data = cb.data || '';
            const chatId = cb.message && cb.message.chat && cb.message.chat.id;
            const msgId = cb.message && cb.message.message_id;
            ctx.waitUntil(tg('answerCallbackQuery', { callback_query_id: cb.id }).catch(() => {}));
            if (!chatId) return new Response('OK');

            if (data.startsWith('tgpage_')) {
                const parts = data.split('_');
                const targetPage = Math.max(1, parseInt(parts[1], 10) || 1);
                const requestedProvider = KNOWN_PROVIDERS.includes(parts[2]) ? parts[2] : '';
                if (requestedProvider && pcfg.modes[requestedProvider] === 'hidden') { await sendOrEdit(chatId, msgId, { text: hiddenText, parse_mode: 'Markdown' }); return new Response('OK'); }
                if (requestedProvider && pcfg.modes[requestedProvider] === 'locked') { await sendOrEdit(chatId, msgId, { text: lockedText(requestedProvider), parse_mode: 'Markdown' }); return new Response('OK'); }
                const provider = requestedProvider && pcfg.modes[requestedProvider] === 'live' ? requestedProvider : defP;
                if (!provider) { await sendOrEdit(chatId, msgId, { text: '*Search is paused right now.*', parse_mode: 'Markdown' }); return new Response('OK'); }
                let query = parts.slice(3).join('_');
                try { query = decodeURIComponent(query); } catch (_) {}
                await sendOrEdit(chatId, msgId, { text: '*Loading page ' + targetPage + '…*', parse_mode: 'Markdown' });
                ctx.waitUntil(performTelegramSearch(chatId, query || 'trending', provider, targetPage, msgId, origin));
                return new Response('OK');
            }

            const action = data.replace('menu_', '');
            if (action === 'quick_search') {
                if (!defP) { await sendOrEdit(chatId, msgId, { text: '*Search is paused right now.*', parse_mode: 'Markdown', reply_markup: { inline_keyboard: [[{ text: '‹ Back', callback_data: 'menu_main' }]] } }); return new Response('OK'); }
                await sendOrEdit(chatId, msgId, { text: '*Loading trending…*', parse_mode: 'Markdown' });
                ctx.waitUntil(performTelegramSearch(chatId, 'trending', defP, 1, msgId, origin));
            } else if (action === 'status') {
                const checks = await runStatusChecks(null).catch(() => null);
                const menu = UI_MENUS.status(origin, checks);
                ctx.waitUntil(sendOrEdit(chatId, msgId, { text: menu.text, parse_mode: 'Markdown', reply_markup: menu.reply_markup }));
            } else if (UI_MENUS[action]) {
                const menu = UI_MENUS[action](origin, pcfg);
                ctx.waitUntil(sendOrEdit(chatId, msgId, { text: menu.text, parse_mode: 'Markdown', reply_markup: menu.reply_markup }));
            }
            return new Response('OK');
        }

        const message = body.message;
        if (!message || !message.text) return new Response('OK');
        const chatId = message.chat.id;
        const rawText = message.text.trim();
        const cmd = rawText.split(/\s+/)[0].replace(/@\w+$/, '').toLowerCase();

        if (cmd === '/start' || cmd === '/menu') {
            const menu = UI_MENUS.main(origin);
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: menu.text, parse_mode: 'Markdown', reply_markup: menu.reply_markup }));
            return new Response('OK');
        }
        if (cmd === '/status') {
            const checks = await runStatusChecks(null).catch(() => null);
            const menu = UI_MENUS.status(origin, checks);
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: menu.text, parse_mode: 'Markdown', reply_markup: menu.reply_markup }));
            return new Response('OK');
        }
        if (cmd === '/social' || cmd === '/channel') {
            await getSocialConfig(env).catch(() => null);
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: socialBotText(), parse_mode: 'Markdown', link_preview_options: { is_disabled: true } }));
            return new Response('OK');
        }
        if (cmd === '/creator') {
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: 'VexoStream is made by ' + DEFAULTS.CREATOR + '.' }));
            return new Response('OK');
        }
        if (cmd === '/models') {
            const query = rawText.replace(/^\/models(@\w+)?\s*/i, '').trim().slice(0, 80);
            ctx.waitUntil(performTelegramModelSearch(chatId, query, origin));
            return new Response('OK');
        }
        if (cmd === '/search') {
            const words = rawText.replace(/^\/search(@\w+)?\s*/i, '').trim().split(/\s+/).filter(Boolean);
            let provider = defP;
            if (words.length > 1 && KNOWN_PROVIDERS.includes(words[0].toLowerCase())) provider = words.shift().toLowerCase();
            if (!provider) { ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: '*Search is paused right now.*', parse_mode: 'Markdown' })); return new Response('OK'); }
            if (pcfg.modes[provider] === 'hidden') { ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: hiddenText, parse_mode: 'Markdown' })); return new Response('OK'); }
            if (pcfg.modes[provider] === 'locked') { ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: lockedText(provider), parse_mode: 'Markdown' })); return new Response('OK'); }
            const query = words.join(' ').slice(0, 100);
            if (!query) {
                ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: '*Usage:* `/search <query>` or `/search <provider> <query>`\n_Example:_ `/search pornhub cosplay`', parse_mode: 'Markdown' }));
                return new Response('OK');
            }
            const loadRes = await tg('sendMessage', { chat_id: chatId, text: '*Searching ' + md(provider) + ' for* ' + md(query) + '…', parse_mode: 'Markdown' });
            const loadData = await loadRes.json().catch(() => ({}));
            ctx.waitUntil(performTelegramSearch(chatId, query, provider, 1, loadData && loadData.result && loadData.result.message_id, origin));
            return new Response('OK');
        }

        const isUrl = /^https?:\/\//i.test(rawText);
        const isViewkey = /^[a-zA-Z0-9]{8,24}$/.test(rawText) || rawText.includes('viewkey=');
        if (!isUrl && !isViewkey) {
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: 'Send a supported video link, use /search <query>, or browse profiles with /models [name].' }));
            return new Response('OK');
        }

        const targetUrl = parseInputToTargetUrl(rawText);
        const linkProvider = providerForUrl(targetUrl);
        if (!linkProvider) {
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: 'That link is not from a supported provider.' }));
            return new Response('OK');
        }
        if (isProviderHidden(pcfg, linkProvider) || isProviderLocked(pcfg, linkProvider)) {
            ctx.waitUntil(tg('sendMessage', { chat_id: chatId, text: isProviderHidden(pcfg, linkProvider) ? hiddenText : lockedText(linkProvider), parse_mode: 'Markdown' }));
            return new Response('OK');
        }
        ctx.waitUntil((async () => {
            const statusRes = await tg('sendMessage', { chat_id: chatId, text: '*Loading…*\nResolving streams.', parse_mode: 'Markdown' });
            const statusMsg = await statusRes.json().catch(() => ({}));
            const statusMsgId = statusMsg && statusMsg.result && statusMsg.result.message_id;

            let data = { status: 'error' };
            for (let i = 0; i < 4; i++) {
                try {
                    const res = await timedFetch(RAILWAY_URL + '/api/extract?url=' + encodeURIComponent(targetUrl), { headers: { 'X-Edge-Token': EDGE_TOKEN } }, 45000);
                    data = await res.json();
                    if (data.status === 'success') break;
                } catch (_) {}
                if (i < 3) await new Promise(r => setTimeout(r, 1200));
            }
            if (data.status !== 'success' || !data.streams) {
                await sendOrEdit(chatId, statusMsgId, { text: '*Extraction failed.*\nCould not resolve streams. Make sure the video is public.', parse_mode: 'Markdown' });
                return;
            }
            const enc = b64urlEncode(targetUrl);
            const d = Math.floor(Number(data.duration) || 0);
            const dur = d ? Math.floor(d / 60) + 'm ' + (d % 60) + 's' : 'Stream';
            const quals = (data.streams.qualities || []).map(q => q.quality).filter(Boolean).slice(0, 6).join(', ');
            await sendOrEdit(chatId, statusMsgId, {
                text: '*' + md(data.title || 'Untitled video') + '*\n\n• *Provider:* `' + md(String(data.provider || 'media')) + '`\n• *Duration:* `' + dur + '`' + (quals ? '\n• *Qualities:* `' + md(quals) + '`' : '') + '\n\nPick a player:',
                parse_mode: 'Markdown',
                reply_markup: { inline_keyboard: [[{ text: 'Watch on web', url: origin + '/video/' + enc }], [{ text: 'Embed player', url: origin + '/embed/' + enc }]] }
            });
        })());
        return new Response('OK');
    } catch (_) {
        return new Response('OK');
    }
}

// ============================================================================
