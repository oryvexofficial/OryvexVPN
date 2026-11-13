// ============================================================================
// APP API v1
// Native Flutter clients use short-lived, revocable bearer tokens stored only
// as SHA-256 hashes in D1. EDGE_TOKEN never leaves the Worker.
// ============================================================================
const APP_API_PREFIX = '/api/v1';
const APP_API_SESSION_TTL = 60 * 60 * 24 * 30;
let __appApiSessionsReady = false;
let __adminApiSessionsReady = false;

function appApiJson(data, status = 200, extra = {}) {
    return jsonResponse(data, status, {
        'Cache-Control': 'no-store',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, X-Requested-With, X-App-Key',
        'X-Content-Type-Options': 'nosniff',
        ...extra
    });
}

function appApiKeyStatus(request, env) {
    const expected = String(env && env.APP_KEY || '');
    const provided = String(request.headers.get('X-App-Key') || new URL(request.url).searchParams.get('key') || '');
    if (!expected) return { ok: false, status: 503, error: 'App API key is not configured on the Worker.', code: 'app_key_missing' };
    if (!provided || !timingSafeEqual(provided, expected)) return { ok: false, status: 401, error: 'The app API key is missing or does not match the Worker key.', code: 'app_key_invalid' };
    return { ok: true };
}

async function ensureAppApiSessionsSchema(env) {
    if (__appApiSessionsReady) return true;
    if (!env || !env.DB) return false;
    try {
        await env.DB.prepare(
            'CREATE TABLE IF NOT EXISTS api_sessions (' +
            'token_hash TEXT PRIMARY KEY, member_id INTEGER NOT NULL, stamp TEXT NOT NULL, ' +
            'created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at INTEGER NOT NULL, revoked_at TEXT)'
        ).run();
        await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_api_sessions_member_id ON api_sessions(member_id)').run();
        await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_api_sessions_expires_at ON api_sessions(expires_at)').run();
        __appApiSessionsReady = true;
        return true;
    } catch (e) {
        __dbError = 'App API sessions table: ' + dbErrText(e);
        return false;
    }
}

async function ensureAdminApiSessionsSchema(env) {
    if (__adminApiSessionsReady) return true;
    if (!env || !env.DB) return false;
    try {
        await env.DB.prepare(
            'CREATE TABLE IF NOT EXISTS admin_api_sessions (' +
            'token_hash TEXT PRIMARY KEY, username TEXT NOT NULL COLLATE NOCASE, stamp TEXT NOT NULL, ' +
            'created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at INTEGER NOT NULL, revoked_at TEXT)'
        ).run();
        await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_admin_api_sessions_user ON admin_api_sessions(username)').run();
        await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_admin_api_sessions_expiry ON admin_api_sessions(expires_at)').run();
        __adminApiSessionsReady = true;
        return true;
    } catch (e) {
        __dbError = 'Owner app sessions table: ' + dbErrText(e);
        return false;
    }
}

async function appApiCreateAdminSession(admin, env) {
    if (!(await ensureAdminApiSessionsSchema(env))) return null;
    const token = randomHex(32);
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + APP_API_SESSION_TTL;
    try {
        await env.DB.prepare("DELETE FROM admin_api_sessions WHERE expires_at <= ? OR (revoked_at IS NOT NULL AND created_at < datetime('now', '-7 days'))").bind(now).run().catch(() => null);
        await env.DB.prepare('INSERT INTO admin_api_sessions (token_hash, username, stamp, expires_at) VALUES (?, ?, ?, ?)')
            .bind(await sha256Hex(token), String(admin.username), String(admin.stamp || ''), expiresAt).run();
        return { token, expiresAt };
    } catch (_) { return null; }
}

async function appApiAdmin(request, env) {
    const token = appApiBearer(request);
    if (!token || !(await ensureAdminApiSessionsSchema(env)) || !(await ensureAdminUsersSchema(env))) return null;
    const tokenHash = await sha256Hex(token);
    const row = await env.DB.prepare(
        'SELECT username, stamp, expires_at FROM admin_api_sessions WHERE token_hash = ? AND revoked_at IS NULL'
    ).bind(tokenHash).first().catch(() => null);
    if (!row || Number(row.expires_at) <= Math.floor(Date.now() / 1000)) return null;
    const admin = await loadSessionUser(env, String(row.username || ''));
    if (!admin || admin.disabled || String(row.stamp) !== String(admin.stamp)) return null;
    return admin;
}

async function appApiReadJson(request) {
    const contentLength = Number(request.headers.get('Content-Length') || 0);
    if (contentLength > 16384) return { ok: false, error: 'Request body is too large.' };
    try {
        const text = await request.text();
        if (text.length > 16384) return { ok: false, error: 'Request body is too large.' };
        const value = JSON.parse(text || '{}');
        if (!value || typeof value !== 'object' || Array.isArray(value)) return { ok: false, error: 'Send a JSON object.' };
        return { ok: true, value };
    } catch (_) {
        return { ok: false, error: 'Send valid JSON.' };
    }
}

function appApiBearer(request) {
    const match = /^Bearer\s+([a-f0-9]{64})$/i.exec(String(request.headers.get('Authorization') || '').trim());
    return match ? match[1].toLowerCase() : '';
}

async function appApiMember(request, env) {
    const token = appApiBearer(request);
    if (!token || !(await ensureAppApiSessionsSchema(env)) || !(await ensureMembersSchema(env))) return null;
    const tokenHash = await sha256Hex(token);
    const row = await env.DB.prepare(
        'SELECT s.token_hash, s.member_id, s.stamp AS session_stamp, s.expires_at, m.username, m.stamp AS member_stamp, m.disabled, m.created_at, m.last_login_at ' +
        'FROM api_sessions s JOIN members m ON m.id = s.member_id ' +
        'WHERE s.token_hash = ? AND s.revoked_at IS NULL'
    ).bind(tokenHash).first().catch(() => null);
    if (!row || Number(row.disabled) || Number(row.expires_at) <= Math.floor(Date.now() / 1000) || String(row.session_stamp) !== String(row.member_stamp)) return null;
    return { id: Number(row.member_id), username: String(row.username), created_at: row.created_at || '', last_login_at: row.last_login_at || '', tokenHash };
}

async function appApiCreateSession(member, env) {
    if (!(await ensureAppApiSessionsSchema(env))) return null;
    const token = randomHex(32);
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + APP_API_SESSION_TTL;
    try {
        await env.DB.prepare("DELETE FROM api_sessions WHERE expires_at <= ? OR (revoked_at IS NOT NULL AND created_at < datetime('now', '-7 days'))").bind(now).run().catch(() => null);
        await env.DB.prepare('INSERT INTO api_sessions (token_hash, member_id, stamp, expires_at) VALUES (?, ?, ?, ?)')
            .bind(await sha256Hex(token), Number(member.id), String(member.stamp || ''), expiresAt).run();
        return { token, expiresAt };
    } catch (_) { return null; }
}

function appApiBackendRequest(request, url, path, params = null) {
    const target = new URL(url.origin + path);
    if (params) for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== null && String(value) !== '') target.searchParams.set(key, String(value));
    }
    const headers = new Headers(request.headers);
    headers.delete('Authorization');
    headers.delete('X-App-Key');
    headers.set('X-Edge-Token', EDGE_TOKEN);
    headers.set('Accept', 'application/json');
    return new Request(target.toString(), { method: 'GET', headers });
}

function appApiPageNumber(raw) {
    const n = Number.parseInt(String(raw || '1'), 10);
    return Number.isInteger(n) && n > 0 && n < 1000 ? n : 1;
}

async function handleAppApiV1(request, url, env, ctx) {
    const path = url.pathname.slice(APP_API_PREFIX.length).replace(/\/+$/, '') || '/';
    const method = request.method.toUpperCase();
    const getOnly = () => method === 'GET';
    if (path === '/health') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        return appApiJson({ ok: true, service: 'VexoStream API', version: 1, checked_at: new Date().toISOString() });
    }
    if (path === '/config' || path === '/providers') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const cfg = await getProviderConfig(env, true);
        const members = await getMembersConfig(env, true);
        const providers = listedProviders(cfg).map(p => ({ id: p.id, name: p.name, domain: p.domain, status: p.mode, browse: p.mode === 'live', playback: p.mode === 'live', available: p.mode === 'live' }));
        return appApiJson({
            app: { name: 'VexoStream', adultOnly: true, version: '1.0.0' },
            apiVersion: 1,
            providers,
            defaultProvider: defaultProviderOf(cfg),
            defaultQuery: cfg.defaultQuery || 'trending',
            access: { requireLogin: members.requireLogin, allowSignup: members.allowSignup, modelsLogin: members.modelsLogin }
        });
    }
    if (path === '/auth/signup' || path === '/auth/login') {
        if (method !== 'POST') return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'POST, OPTIONS' });
        const body = await appApiReadJson(request);
        if (!body.ok) return appApiJson({ error: body.error }, 400);
        const ip = clientIpOf(request);
        if (memberThrottled(ip)) return appApiJson({ error: 'Too many attempts. Wait 10 minutes and try again.' }, 429, { 'Retry-After': '600' });
        const value = body.value;
        const username = String(value.username || '').trim();
        const password = String(value.password || '');
        let result;
        if (path === '/auth/signup') {
            if (value.adult !== true) return appApiJson({ error: 'You must confirm you are 18 or older to create an account.' }, 400);
            if (typeof value.passwordConfirm !== 'string') return appApiJson({ error: 'Confirm your password to create an account.' }, 400);
            result = await signupMember(env, username, password, value.passwordConfirm);
        } else {
            if (!username || username.length > 64 || !password || password.length > 128) result = { ok: false, error: 'Enter a valid username and password.' };
            else {
                const admin = await authenticateAdmin(env, username, password);
                if (admin) result = { ok: true, admin };
                else if (await isMaintenanceOn(env)) return appApiJson({ error: 'VexoStream is under maintenance. Only admins can sign in right now.', code: 'maintenance' }, 503, { 'Retry-After': '3600' });
                else result = await loginMember(env, username, password);
            }
        }
        if (!result || !result.ok) {
            memberFailed(ip);
            return appApiJson({ error: (result && result.error) || 'Wrong username or password.' }, path === '/auth/login' ? 401 : 400);
        }
        __memberFails.delete(ip);
        if (result.admin) {
            const issued = await appApiCreateAdminSession(result.admin, env);
            if (!issued) return appApiJson({ error: 'Owner app session storage is unavailable. Check the DB binding and admin_api_sessions migration.' }, 503);
            return appApiJson({
                token: issued.token,
                tokenType: 'Bearer',
                expiresAt: issued.expiresAt,
                account: { id: result.admin.username, username: result.admin.username, role: result.admin.owner ? 'Owner' : 'Admin', isOwner: !!result.admin.owner }
            });
        }
        const issued = await appApiCreateSession(result.member, env);
        if (!issued) return appApiJson({ error: 'Account service is temporarily unavailable.' }, 503);
        return appApiJson({
            token: issued.token,
            tokenType: 'Bearer',
            expiresAt: issued.expiresAt,
            account: { id: Number(result.member.id), username: String(result.member.username), role: 'Member', isOwner: false }
        }, path === '/auth/signup' ? 201 : 200);
    }
    if (path === '/auth/logout') {
        if (method !== 'POST') return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'POST, OPTIONS' });
        const admin = await appApiAdmin(request, env);
        if (admin) {
            const token = appApiBearer(request);
            await env.DB.prepare('UPDATE admin_api_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = ? AND revoked_at IS NULL').bind(await sha256Hex(token)).run().catch(() => null);
            return appApiJson({ ok: true });
        }
        const member = await appApiMember(request, env);
        if (member) await env.DB.prepare('UPDATE api_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = ? AND revoked_at IS NULL').bind(member.tokenHash).run().catch(() => null);
        return appApiJson({ ok: true });
    }
    if (path === '/account') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const admin = await appApiAdmin(request, env);
        if (admin) return appApiJson({ account: { id: admin.username, username: admin.username, role: admin.owner ? 'Owner' : 'Admin', isOwner: !!admin.owner, permissions: admin.permissions || [], createdAt: admin.createdAt || '', lastLoginAt: admin.lastLogin || '' } });
        const member = await appApiMember(request, env);
        if (!member) return appApiJson({ error: 'Sign in to view your account.', code: 'auth_required' }, 401);
        return appApiJson({ account: { id: member.id, username: member.username, role: 'Member', isOwner: false, createdAt: member.created_at, lastLoginAt: member.last_login_at } });
    }
    if (path.startsWith('/admin')) {
        const admin = await appApiAdmin(request, env);
        if (!admin) return appApiJson({ error: 'Admin access is required.', code: 'auth_required' }, 401);
        if (path === '/admin' && method === 'GET') {
            const out = { owner: { username: admin.username, role: admin.owner ? 'Owner' : 'Admin', isOwner: !!admin.owner, permissions: admin.permissions || [], legacy: !!admin.legacy } };
            if (adminCan(admin, 'site')) {
                const memberList = await listMembers(env, 100);
                out.maintenanceOn = await isMaintenanceOn(env, true);
                out.members = { config: await getMembersConfig(env, true), total: memberList.total, rows: memberList.rows };
            }
            if (adminCan(admin, 'providers')) {
                const cfg = await getProviderConfig(env, true);
                Object.assign(out, { defaultProvider: cfg.defaultProvider, defaultQuery: cfg.defaultQuery, lockMessage: cfg.lockMessage, providerOrder: cfg.order, providers: providerList(cfg).map(p => ({ id: p.id, name: p.name, domain: p.domain, mode: p.mode })) });
            }
            if (adminCan(admin, 'backend')) out.backendUrl = await getBackendUrl(env, true);
            if (adminCan(admin, 'users')) out.team = (await listAdminUsers(env) || []).map(t => ({ username: t.username, owner: !!t.owner, permissions: t.permissions, disabled: !!t.disabled, createdBy: t.createdBy, createdAt: t.createdAt, lastLogin: t.lastLogin, legacy: !!t.legacy }));
            if (adminCan(admin, 'social')) {
                out.social = { config: await getSocialConfig(env, true), posts: await listSocialPosts(env, 25) };
                out.telegram = await getTelegramAdminSettings(env, url.origin, true);
            }
            if (admin.owner) out.live = { config: await getLiveConfig(env, true), stats: await liveAdminStats(env) };
            if (adminCan(admin, 'operations')) out.database = await dbHealth(env);
            return appApiJson(out);
        }
        if (method !== 'POST') return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, POST, OPTIONS' });
        const body = await appApiReadJson(request);
        if (!body.ok) return appApiJson({ error: body.error }, 400);
        const values = body.value;
        if (path === '/admin/settings') {
            // Reject the entire request before writing anything if any field is unauthorized.
            const fieldPermissions = { defaultQuery: 'providers', defaultProvider: 'providers', lockMessage: 'providers', providerOrder: 'providers', providerModes: 'providers', backendUrl: 'backend', maintenanceOn: 'site', members: 'site', live: 'owner' };
            for (const key of Object.keys(values)) {
                const perm = fieldPermissions[key];
                if (!perm || (perm === 'owner' ? !admin.owner : !adminCan(admin, perm))) return appApiJson({ error: 'Permission denied for setting: ' + key, code: 'forbidden' }, 403);
            }
            const cfg = await getProviderConfig(env, true);
            const nextCfg = { ...cfg };
            if (Object.prototype.hasOwnProperty.call(values, 'defaultQuery')) nextCfg.defaultQuery = String(values.defaultQuery || '').trim().slice(0, 100);
            if (Object.prototype.hasOwnProperty.call(values, 'defaultProvider')) nextCfg.defaultProvider = String(values.defaultProvider || '').trim().toLowerCase();
            if (Object.prototype.hasOwnProperty.call(values, 'lockMessage')) nextCfg.lockMessage = String(values.lockMessage || '').trim().slice(0, 200);
            if (Array.isArray(values.providerOrder)) nextCfg.order = values.providerOrder.map(String);
            if (values.providerModes && typeof values.providerModes === 'object') nextCfg.modes = values.providerModes;
            if (Object.keys(nextCfg).some(k => JSON.stringify(nextCfg[k]) !== JSON.stringify(cfg[k])) && !(await saveProviderConfig(env, nextCfg))) return appApiJson({ error: 'Could not save provider settings.' }, 503);
            if (Object.prototype.hasOwnProperty.call(values, 'backendUrl')) {
                const backend = await saveBackendUrl(env, String(values.backendUrl || ''));
                if (!backend.ok) return appApiJson({ error: backend.error }, 400);
            }
            if (Object.prototype.hasOwnProperty.call(values, 'maintenanceOn') && !(await setMaintenance(env, values.maintenanceOn === true))) return appApiJson({ error: 'Could not save maintenance mode.' }, 503);
            if (values.members && typeof values.members === 'object' && !(await saveMembersConfig(env, values.members))) return appApiJson({ error: 'Could not save member settings.' }, 503);
            if (values.live && typeof values.live === 'object' && !(await saveLiveConfig(env, { ...(await getLiveConfig(env, true)), ...values.live }))) return appApiJson({ error: 'Could not save live viewer settings.' }, 503);
            if (admin.owner) {
                const updated = await getProviderConfig(env, true);
                return appApiJson({ ok: true, maintenanceOn: await isMaintenanceOn(env, true), defaultProvider: updated.defaultProvider, defaultQuery: updated.defaultQuery, lockMessage: updated.lockMessage, providerOrder: updated.order, providers: providerList(updated).map(p => ({ id: p.id, name: p.name, mode: p.mode })), backendUrl: await getBackendUrl(env, true), members: await getMembersConfig(env, true), live: await getLiveConfig(env, true) });
            }
            return appApiJson({ ok: true });
        }
        const requiredPermission = { '/admin/team': 'users', '/admin/members': 'site', '/admin/social': 'social', '/admin/telegram': 'social', '/admin/operations': 'operations', '/admin/live': 'owner' }[path];
        if (requiredPermission && (requiredPermission === 'owner' ? !admin.owner : !adminCan(admin, requiredPermission))) return appApiJson({ error: 'You do not have permission for this section.', code: 'forbidden' }, 403);
        if (path === '/admin/team') {
            const action = String(values.action || '');
            let result;
            const perms = Array.isArray(values.permissions) ? values.permissions.map(String) : [];
            if (action === 'create') result = await createAdminAccount(env, admin, values.username, values.password, perms);
            else if (action === 'update') result = await updateAdminPermissions(env, admin, values.username, perms);
            else if (action === 'reset') result = await resetAdminPassword(env, admin, values.username, values.password);
            else if (action === 'remove') result = await removeAdminAccount(env, admin, values.username);
            else return appApiJson({ error: 'Unknown team action.' }, 400);
            if (!result.ok) return appApiJson({ error: result.error }, 400);
            return appApiJson({ ok: true, result, team: (await listAdminUsers(env) || []).map(t => ({ username: t.username, owner: !!t.owner, permissions: t.permissions, disabled: !!t.disabled, createdBy: t.createdBy, createdAt: t.createdAt, lastLogin: t.lastLogin, legacy: !!t.legacy })) });
        }
        if (path === '/admin/password') {
            const result = await changeOwnPassword(env, admin, values.current, values.next, values.confirm);
            if (!result.ok) return appApiJson({ error: result.error }, 400);
            const oldToken = appApiBearer(request);
            await env.DB.prepare('UPDATE admin_api_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = ? AND revoked_at IS NULL').bind(await sha256Hex(oldToken)).run().catch(() => null);
            const issued = await appApiCreateAdminSession(result.user, env);
            if (!issued) return appApiJson({ error: 'Password changed, but could not refresh this app session. Sign in again.' }, 503);
            return appApiJson({ ok: true, token: issued.token, expiresAt: issued.expiresAt });
        }
        if (path === '/admin/members') {
            const form = new FormData();
            for (const [key, value] of Object.entries(values)) {
                if (key === 'config' && value && typeof value === 'object') {
                    form.set('action', 'settings');
                    form.set('require_login', value.requireLogin ? '1' : '0');
                    form.set('allow_signup', value.allowSignup ? '1' : '0');
                    form.set('embeds_too', value.embedsToo ? '1' : '0');
                    form.set('models_login', value.modelsLogin ? '1' : '0');
                } else if (value !== null && value !== undefined) form.set(key, String(value));
            }
            const result = await handleMembersAdmin(env, form);
            if (!result.ok) return appApiJson({ error: result.error }, 400);
            const list = await listMembers(env, 100);
            return appApiJson({ ok: true, result, members: { config: await getMembersConfig(env, true), total: list.total, rows: list.rows } });
        }
        if (path === '/admin/live') {
            const cfg = await getLiveConfig(env, true);
            const next = normalizeLiveConfig({ ...cfg, ...(values.config || values) });
            if (!(await saveLiveConfig(env, next))) return appApiJson({ error: 'Could not save live viewer settings.' }, 503);
            return appApiJson({ ok: true, config: await getLiveConfig(env, true), stats: await liveAdminStats(env) });
        }
        if (path === '/admin/social') {
            const action = String(values.action || 'save');
            const form = new FormData();
            form.set('action', action);
            const config = values.config && typeof values.config === 'object' ? values.config : values;
            if (action === 'save') {
                const links = config.links && typeof config.links === 'object' ? config.links : {};
                for (const [key, value] of Object.entries(links)) form.set('link_' + key, String(value || ''));
                form.set('show_page', config.showPage ? '1' : '0'); form.set('show_footer', config.showInFooter ? '1' : '0'); form.set('bot_buttons', config.botButtons ? '1' : '0');
            } else if (action === 'channel') {
                const channel = config.channel && typeof config.channel === 'object' ? config.channel : config;
                form.set('channel_id', String(channel.chatId || '')); form.set('invite_url', String(channel.inviteUrl || ''));
            } else if (action === 'bots') {
                const bots = Array.isArray(config.bots) ? config.bots : [];
                for (const bot of bots) {
                    const key = String(bot.key || 'new');
                    form.append('bot_key', key); form.append('bot_platform', String(bot.platform || 'other')); form.append('bot_name', String(bot.name || ''));
                    form.append('bot_id', String(bot.botId || '')); form.append('bot_url', String(bot.url || '')); form.append('bot_about', String(bot.about || ''));
                    form.set('bot_show_' + key, bot.visible === false ? '0' : '1');
                }
            }
            for (const key of ['text', 'format', 'button_text', 'button_url', 'post_id']) if (values[key] !== undefined) form.set(key, String(values[key]));
            for (const key of ['silent', 'pin', 'no_preview']) if (values[key] !== undefined) form.set(key, values[key] === true || values[key] === '1' ? '1' : '');
            const result = await handleSocialAction(env, url.origin, admin, form);
            if (!result.ok) return appApiJson({ error: result.error }, 400);
            return appApiJson({ ok: true, result, social: { config: await getSocialConfig(env, true), posts: await listSocialPosts(env, 25) } });
        }
        if (path === '/admin/telegram') {
            const action = String(values.action || 'save');
            let result;
            if (action === 'save') result = await saveTelegramSettings(env, values.botToken, values.webhookOrigin);
            else if (action === 'reset_token') result = await resetTelegramTokenOverride(env);
            else if (action === 'reconnect') {
                const data = await setupTelegramWebhook(url.origin, env).catch(e => ({ ok: false, description: String(e && e.message) }));
                result = data && data.ok ? { ok: true, message: 'Telegram webhook connected.' } : { ok: false, error: 'Telegram setup failed: ' + ((data && data.description) || 'unknown error') };
            } else if (action === 'check_bot') result = await checkTelegramBot(env, url.origin);
            else if (action === 'check_channel') result = await testTelegramChannel(env, url.origin, await getSocialConfig(env, true));
            else return appApiJson({ error: 'Unknown Telegram action.' }, 400);
            if (!result.ok) return appApiJson({ error: result.error }, 400);
            return appApiJson({ ok: true, result, telegram: await getTelegramAdminSettings(env, url.origin, true) });
        }
        if (path === '/admin/operations') {
            const action = String(values.action || 'health');
            let health = await dbHealth(env);
            if (action === 'repair') {
                __usersReady = false;
                __membersReady = false;
                __appApiSessionsReady = false;
                __adminApiSessionsReady = false;
                const settingsOk = await ensureSettingsSchema(env, true);
                const adminsOk = await ensureAdminUsersSchema(env);
                const membersOk = await ensureMembersSchema(env);
                const sessionsOk = await ensureAppApiSessionsSchema(env);
                const adminSessionsOk = await ensureAdminApiSessionsSchema(env);
                const writeOk = settingsOk && await dbSetSetting(env, 'last_healthcheck', new Date().toISOString());
                health = { ...(await dbHealth(env)), binding: !!env.DB, table: settingsOk, write: !!writeOk, admins: adminsOk, members: membersOk, sessions: sessionsOk, adminSessions: adminSessionsOk, error: __dbError };
            } else if (action !== 'health') return appApiJson({ error: 'Unknown operations action.' }, 400);
            return appApiJson({ ok: !!(health.binding && health.table && health.write), database: health });
        }
        return appApiJson({ error: 'Unknown admin endpoint.' }, 404);
    }
    if (path === '/catalog' || path === '/search') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const cfg = await getProviderConfig(env, true);
        const asked = String(url.searchParams.get('provider') || '').trim().toLowerCase();
        const provider = asked || defaultProviderOf(cfg);
        if (!provider) return lockedJson(cfg, provider);
        if (isProviderHidden(cfg, provider)) return hiddenJson(provider);
        if (isProviderLocked(cfg, provider)) return lockedJson(cfg, provider);
        const q = String(url.searchParams.get('q') || url.searchParams.get('search') || cfg.defaultQuery || 'trending').trim().slice(0, 100) || cfg.defaultQuery || 'trending';
        const params = { q, provider, page: appApiPageNumber(url.searchParams.get('page')) };
        return forwardToRailway(appApiBackendRequest(request, url, '/api/explore', params), ctx);
    }
    if (path === '/models' || path.startsWith('/models/')) {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const config = await getMembersConfig(env);
        if (config.modelsLogin && !(await appApiMember(request, env)) && !(await appApiAdmin(request, env))) return appApiJson({ error: 'Sign in to browse performer profiles.', code: 'auth_required' }, 401);
        if (path === '/models') {
            const requestedGender = String(url.searchParams.get('gender') || 'women').trim().toLowerCase();
            const gender = ({ women: 'Female', both: 'Female,Male', men: 'Male' })[requestedGender] || String(url.searchParams.get('gender') || 'Female').trim();
            if (!['Female', 'Male', 'Female,Male'].includes(gender)) return appApiJson({ error: 'Invalid gender filter.' }, 400);
            const params = {
                gender,
                sort: 'popularity',
                page: appApiPageNumber(url.searchParams.get('page')),
                search: String(url.searchParams.get('search') || '').trim().slice(0, 80)
            };
            return forwardToRailway(appApiBackendRequest(request, url, '/api/models', params), ctx);
        }
        let slug = '';
        try { slug = decodeURIComponent(path.slice('/models/'.length)); } catch (_) {}
        if (!/^[a-z0-9][a-z0-9._-]{0,119}$/i.test(slug)) return appApiJson({ error: 'Invalid profile.' }, 400);
        return forwardToRailway(appApiBackendRequest(request, url, '/api/models/' + encodeURIComponent(slug)), ctx);
    }
    if (path === '/embed/grant') {
        if (method !== 'POST') return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'POST, OPTIONS' });
        const member = await appApiMember(request, env);
        const admin = member ? null : await appApiAdmin(request, env);
        if (!member && !admin) return appApiJson({ error: 'Sign in before opening the embedded player.', code: 'auth_required' }, 401);

        const body = await appApiReadJson(request);
        if (!body.ok) return appApiJson({ error: body.error }, 400);
        const target = String(body.value.url || '').trim();
        if (!target || target.length > 2048) return appApiJson({ error: 'Enter a valid video URL.' }, 400);
        let parsed;
        try { parsed = new URL(target); } catch (_) { return appApiJson({ error: 'Enter a valid video URL.' }, 400); }
        if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || parsed.username || parsed.password || isPrivateHost(parsed.hostname)) {
            return appApiJson({ error: 'Only public HTTP or HTTPS video links are supported.' }, 400);
        }
        const provider = providerForUrl(target);
        if (!provider) return appApiJson({ error: 'That video source is not supported.' }, 400);
        const cfg = await getProviderConfig(env, true);
        if (isProviderHidden(cfg, provider)) return hiddenJson(provider);
        if (isProviderLocked(cfg, provider)) return lockedJson(cfg, provider);
        const issued = await createAppEmbedGrant(target);
        return appApiJson({ grant: issued.value, expiresAt: issued.expiresAt });
    }
    if (path === '/videos/extract') {
        if (method !== 'POST') return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'POST, OPTIONS' });
        const body = await appApiReadJson(request);
        if (!body.ok) return appApiJson({ error: body.error }, 400);
        const target = String(body.value.url || '').trim();
        let parsed;
        try { parsed = new URL(target); } catch (_) { return appApiJson({ error: 'Enter a valid video URL.' }, 400); }
        if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return appApiJson({ error: 'Only HTTP and HTTPS links are supported.' }, 400);
        const provider = providerForUrl(target);
        if (!provider) return appApiJson({ error: 'That video source is not supported.' }, 400);
        const cfg = await getProviderConfig(env, true);
        if (isProviderHidden(cfg, provider)) return hiddenJson(provider);
        if (isProviderLocked(cfg, provider)) return lockedJson(cfg, provider);
        const members = await getMembersConfig(env);
        if (members.requireLogin && !(await appApiMember(request, env)) && !(await appApiAdmin(request, env))) return appApiJson({ error: 'Sign in before playing videos.', code: 'auth_required' }, 401);
        // Dart HTTP and mpv can choose different IPv4/IPv6 paths; app media URLs are target-bound.
        return forwardToRailway(appApiBackendRequest(request, url, '/api/extract', { url: target }), ctx, request, { portableMedia: true });
    }
    if (path === '/posters') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const cfg = await getProviderConfig(env, true);
        const keep = url.searchParams.getAll('u').map(v => String(v || '').trim()).filter((v, i, all) => {
            if (!v || all.indexOf(v) !== i || !/^https:\/\//i.test(v)) return false;
            const provider = providerForUrl(v);
            return !!provider && !isProviderHidden(cfg, provider);
        }).slice(0, 24);
        if (!keep.length) return appApiJson({ posters: {} });
        const target = new URL(url.origin + '/api/posters');
        keep.forEach(v => target.searchParams.append('u', v));
        const headers = new Headers(request.headers);
        headers.delete('Authorization');
        headers.delete('X-App-Key');
        headers.set('X-Edge-Token', EDGE_TOKEN);
        return forwardToRailway(new Request(target.toString(), { method: 'GET', headers }), ctx);
    }
    if (path === '/image') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        // Thumbnails and performer photos for the native app (same safety checks as /proxy-image).
        return handleImageProxy(request, ctx);
    }
    if (path === '/status') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const checks = await runStatusChecks(env);
        const history = await getRealStatusHistory(env, checks);
        const cfg = await getProviderConfig(env, true);
        const providers = listedProviders(cfg).map(p => ({ id: p.id, name: p.name, status: p.mode, available: p.mode === 'live' }));
        return appApiJson({ ...checks, overall: statusOverall(checks), providers, history });
    }
    if (path === '/social') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const cfg = await getSocialConfig(env, true);
        const bots = (cfg.bots || []).filter(b => b.visible).map(b => ({ platform: b.platform, label: b.name || b.platform, about: b.about || '', url: botLink(b) })).filter(b => b.url);
        return appApiJson({
            enabled: cfg.showPage,
            links: cfg.showPage ? cfg.links : {},
            bots: cfg.showPage ? bots : [],
            channel: cfg.showPage ? { title: cfg.channel.title || 'VexoStream community', url: channelJoinUrl(cfg) } : null
        });
    }
    if (path === '/developers') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        return appApiJson({
            title: 'VexoStream for developers',
            embed: '<iframe src="https://vexostream.bond/embed?url=VIDEO_URL" width="100%" height="480" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen loading="lazy"></iframe>',
            endpoints: [
                { method: 'GET', path: '/api/v1/config', auth: false },
                { method: 'GET', path: '/api/v1/catalog?provider=xvideos&q=trending&page=1', auth: false },
                { method: 'GET', path: '/api/v1/models', auth: 'optional by site policy' },
                { method: 'GET', path: '/api/v1/image?url=IMAGE_URL', auth: false },
                { method: 'POST', path: '/api/v1/videos/extract', auth: 'required by site policy' },
                { method: 'POST', path: '/api/v1/embed/grant', auth: 'member or admin bearer session' },
                { method: 'POST', path: '/api/v1/auth/login', auth: false },
                { method: 'POST', path: '/api/v1/auth/signup', auth: false }
            ]
        });
    }
    if (path === '/check-host/nodes') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const all = await checkHostNodes();
        return appApiJson({ countries: CH_COUNTRIES, nodes: Object.keys(all).map(id => ({ id, cc: all[id][0], city: all[id][2], asn: all[id][4] })) }, 200, { 'Cache-Control': 'public, max-age=600', 'X-Robots-Tag': 'noindex' });
    }
    if (path === '/check-host/start') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        return handleCheckHostStart(request, url, env);
    }
    if (path === '/check-host/result') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        return handleCheckHostResult(url, env);
    }
    if (path === '/live') {
        if (!getOnly()) return appApiJson({ error: 'Method not allowed.' }, 405, { Allow: 'GET, OPTIONS' });
        const sid = String(url.searchParams.get('sid') || '').toLowerCase().replace(/[^a-f0-9]/g, '').slice(0, 32);
        if (sid) await touchLivePresence(env, sid, ctx);
        return appApiJson(await livePublicPayload(env));
    }
    return appApiJson({ error: 'Unknown API endpoint.', path }, 404);
}
