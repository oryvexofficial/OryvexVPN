// ROUTER
// ============================================================================
function htmlResponse(html, status = 200, headers = SECURE_HTML_HEADERS) {
    return new Response(html, { status, headers });
}

function redirect(location, extra = {}) {
    return new Response(null, { status: 302, headers: { 'Location': location, 'Cache-Control': 'no-store', ...extra } });
}

function decodeVideoParam(param) {
    let decoded = '';
    try { decoded = b64urlDecode(param); } catch (_) { decoded = ''; }
    if (!decoded || !/^https?:\/\//i.test(decoded)) {
        // bare viewkey fallback
        const vk = (decoded || param).match(/^[a-zA-Z0-9]{6,32}$/);
        return vk ? 'https://www.pornhub.com/view_video.php?viewkey=' + vk[0] : null;
    }
    return decoded;
}

function targetFromQuery(url) {
    const viewkey = url.searchParams.get('viewkey');
    const urlParam = url.searchParams.get('url');
    if (viewkey && /^[a-zA-Z0-9]{4,40}$/.test(viewkey)) return 'https://www.pornhub.com/view_video.php?viewkey=' + viewkey;
    if (urlParam && /^https?:\/\//i.test(urlParam)) return urlParam;
    return null;
}

async function socialPreview(targetUrl) {
    // Only for link-preview bots: fetch title + thumbnail so cards look right
    try {
        const r = await timedFetch(RAILWAY_URL + '/api/extract?url=' + encodeURIComponent(targetUrl), { headers: { 'X-Edge-Token': EDGE_TOKEN } }, 6000);
        const d = await r.json();
        if (d && d.status === 'success') return {
            title: d.title || '',
            thumb: normalizeThumbnailUrl(d.thumbnail || d.thumbnail_url || d.poster || d.images || '')
        };
    } catch (_) {}
    return { title: '', thumb: '' };
}

async function handleRequest(request, env, ctx) {
    initConfig(env);
    try {
        const url = new URL(request.url);
        const path = url.pathname;
        const isApiHost = url.hostname.toLowerCase() === 'api.vexostream.bond';
        const isAppApiPath = path === APP_API_PREFIX || path.startsWith(APP_API_PREFIX + '/');
        const isApiProxyPath = path.startsWith('/proxy-m3u8') || path.startsWith('/proxy-video') || path === '/proxy-image';

        // Keep the API hostname API-only: never render the public website there.
        if (isApiHost && !isAppApiPath && !isApiProxyPath) {
            return new Response('Not Found', {
                status: 404,
                headers: {
                    'Content-Type': 'text/plain;charset=UTF-8',
                    'Cache-Control': 'no-store',
                    'X-Robots-Tag': 'noindex, nofollow',
                    'X-Content-Type-Options': 'nosniff'
                }
            });
        }

        if (!STREAM_SIGN_SECRET || !EDGE_TOKEN) return new Response('Service secrets must be configured before use.', { status: 503, headers: { 'Cache-Control': 'no-store' } });
        await getBackendUrl(env);

        // One canonical host: www.vexostream.bond -> vexostream.bond (301)
        if (url.hostname.startsWith('www.') && url.hostname.slice(4) === seoHost() && (request.method === 'GET' || request.method === 'HEAD') && path !== '/webhook') {
            return new Response(null, { status: 301, headers: { 'Location': SEO_ORIGIN + path + url.search, 'Cache-Control': 'public, max-age=86400' } });
        }

        if (path === '/favicon.ico' || path === '/favicon.svg') {
            return new Response(FAVICON_SVG, { headers: { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'public, max-age=604800' } });
        }
        if (path.startsWith('/assets/') && Object.prototype.hasOwnProperty.call(STATIC_ASSETS, path)) {
            const [type, b64] = STATIC_ASSETS[path];
            const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
            return new Response(bin, { headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=2592000, immutable', 'Access-Control-Allow-Origin': '*', 'X-Content-Type-Options': 'nosniff' } });
        }
        if (path === '/fonts/css2' || path.startsWith('/fonts/gstatic/')) return handleFontProxy(request, url, ctx);
        if (path === '/robots.txt') {
            return new Response(renderRobotsTxt(), { headers: { 'Content-Type': 'text/plain;charset=UTF-8', 'Cache-Control': 'public, max-age=3600' } });
        }
        if (path === '/site.webmanifest' || path === '/manifest.json') {
            return new Response(renderWebManifest(), { headers: { 'Content-Type': 'application/manifest+json', 'Cache-Control': 'public, max-age=86400' } });
        }
        if (path === '/apple-touch-icon.png' || path === '/apple-touch-icon-precomposed.png') {
            const [type, b64] = STATIC_ASSETS['/assets/brand/vexostream-mark-512.png'];
            return new Response(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), { headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=2592000' } });
        }

        if (request.method === 'OPTIONS') {
            return new Response(null, {
                status: 204,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, HEAD',
                    'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Edge-Token, X-App-Key, Accept, Origin, Range, X-Requested-With',
                    'Access-Control-Max-Age': '86400'
                }
            });
        }

        // Gate the versioned API. HLS media URLs carry short-lived signatures; site
        // requests remain IP-bound, native app links are target-bound for mpv IP-family changes.
        if (isAppApiPath) {
            const appKey = appApiKeyStatus(request, env);
            if (!appKey.ok) return appApiJson({ status: 'error', error: appKey.error, code: appKey.code }, appKey.status);
        }

        const gate = await antiScrapeGate(request, url, env, ctx);
        if (gate) return gate;
        const securityCheck = await isScraperOrAttack(request, url);
        if (securityCheck.blocked) return jsonResponse({ status: 'error', error: securityCheck.reason }, 403);

        // Social links (footer + bot), cached 15 s per isolate
        await getSocialConfig(env).catch(() => null);
        // Member flags (log in to watch / sign-ups), cached 15 s per isolate
        await getMembersConfig(env).catch(() => null);

        if (path === '/sitemap.xml') {
            return new Response(renderSitemapXml(await getProviderConfig(env, true)), { headers: { 'Content-Type': 'application/xml;charset=UTF-8', 'Cache-Control': 'public, max-age=3600' } });
        }

        // ---------------------------------------------------------------- admin
        const isAdminPath = path === ADMIN_PATH || path.startsWith(ADMIN_PATH + '/');
        if (isAdminPath) {
            const back = (msg, ok, hash = '') => redirect(ADMIN_PATH + '?flash=' + encodeURIComponent(msg) + (ok ? '' : '&err=1') + (hash ? '#' + hash : ''));
            const readForm = async () => { try { return await request.formData(); } catch (_) { return null; } };
            if ((path === ADMIN_PATH || path === ADMIN_PATH + '/') && request.method === 'GET') {
                const user = await verifyAdminSession(request, env);
                if (!user) return htmlResponse(renderAdminLoginHtml(''), 200, adminHtmlHeaders());
                const tableOk = await ensureSettingsSchema(env, true);
                const health = { binding: !!(env && env.DB), table: tableOk, write: null, error: __dbError };
                const maint = await isMaintenanceOn(env, true);
                const cfg = await getProviderConfig(env, true);
                const team = adminCan(user, 'users') ? await listAdminUsers(env) : null;
                const telegram = adminCan(user, 'social') ? await getTelegramAdminSettings(env, url.origin, true) : null;
                const social = adminCan(user, 'social') ? { cfg: await getSocialConfig(env, true), posts: await listSocialPosts(env, 10) } : null;
                const live = user.owner ? { cfg: await getLiveConfig(env, true), stats: await liveAdminStats(env) } : null;
                const members = adminCan(user, 'site') ? { cfg: await getMembersConfig(env, true), list: await listMembers(env, 25) } : null;
                return htmlResponse(renderAdminPanelHtml(user, maint, url.searchParams.get('flash') || '', cfg, health, url.searchParams.get('err') === '1', await getBackendUrl(env, true), team, telegram, live, social, members), 200, adminHtmlHeaders());
            }
            if (path === ADMIN_PATH + '/live/stats' && request.method === 'GET') {
                const user = await verifyAdminSession(request, env);
                if (!user || !user.owner) return jsonResponse({ status: 'error', error: 'Forbidden' }, 403, { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': url.origin });
                return jsonResponse(await liveAdminStats(env), 200, { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': url.origin, 'X-Robots-Tag': 'noindex' });
            }
            if (path === ADMIN_PATH + '/logout') {
                return redirect(ADMIN_PATH, { 'Set-Cookie': ADMIN_COOKIE_NAME + '=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0' });
            }
            if (request.method !== 'POST') return htmlResponse(render404Html(), 404, adminHtmlHeaders());
            // Admin forms only accept same-origin posts.
            const origin = request.headers.get('Origin');
            if (origin && origin !== url.origin) return new Response('Cross-site request blocked', { status: 403, headers: { 'Cache-Control': 'no-store' } });

            if (path === ADMIN_PATH + '/login') {
                const ip = clientIpOf(request);
                if (loginBlocked(ip)) return htmlResponse(renderAdminLoginHtml('Too many attempts. Try again in 10 minutes.'), 429, adminHtmlHeaders());
                const form = await readForm();
                const uname = form ? String(form.get('username') || '').trim() : '';
                const pass = form ? String(form.get('password') || '') : '';
                const user = uname && pass ? await authenticateAdmin(env, uname, pass) : null;
                if (!user) {
                    loginFailed(ip);
                    return htmlResponse(renderAdminLoginHtml('Wrong username or password.'), 401, adminHtmlHeaders());
                }
                return redirect(ADMIN_PATH, { 'Set-Cookie': adminSessionCookie(await createAdminSession(user)) });
            }

            const user = await verifyAdminSession(request, env);
            if (!user) return redirect(ADMIN_PATH);
            const deny = (label) => back('You don\u2019t have permission to manage ' + label + '.', false);

            if (path === ADMIN_PATH + '/account/password') {
                const form = await readForm();
                if (!form) return back('Could not read the form.', false, 'account');
                const res = await changeOwnPassword(env, user, form.get('current'), form.get('next'), form.get('confirm'));
                if (!res.ok) return back(res.error, false, 'account');
                // Stay signed in on this device with the new stamp.
                return redirect(ADMIN_PATH + '?flash=' + encodeURIComponent('Password changed. Other sessions were signed out.') + '#account', { 'Set-Cookie': adminSessionCookie(await createAdminSession(res.user)) });
            }
            if (path.startsWith(ADMIN_PATH + '/users/')) {
                if (!adminCan(user, 'users')) return deny('the team');
                const form = await readForm();
                if (!form) return back('Could not read the form.', false, 'team');
                const name = String(form.get('username') || '').trim();
                const perms = form.getAll('perm').map(String);
                const action = path.slice((ADMIN_PATH + '/users/').length);
                let res = null, msg = '';
                if (action === 'create') { res = await createAdminAccount(env, user, name, String(form.get('password') || ''), perms); msg = res.ok ? res.username + ' was added.' : ''; }
                else if (action === 'update') { res = await updateAdminPermissions(env, user, name, perms); msg = res.ok ? 'Permissions saved for ' + res.username + '.' : ''; }
                else if (action === 'reset') { res = await resetAdminPassword(env, user, name, String(form.get('password') || '')); msg = res.ok ? 'Password reset for ' + res.username + '. Share it with them privately.' : ''; }
                else if (action === 'remove') { res = await removeAdminAccount(env, user, name); msg = res.ok ? res.username + ' was removed.' : ''; }
                else return htmlResponse(render404Html(), 404, adminHtmlHeaders());
                return back(res.ok ? msg : res.error, res.ok, 'team');
            }
            if (path === ADMIN_PATH + '/toggle') {
                if (!adminCan(user, 'site')) return deny('site mode');
                const cur = await isMaintenanceOn(env, true);
                const wrote = await setMaintenance(env, !cur);
                return back(wrote ? ('Maintenance is now ' + (!cur ? 'on' : 'off') + '.') : 'Could not update maintenance mode. ' + (__dbError || 'D1 write error.') + ' Try Repair database.', wrote, 'overview');
            }
            if (path === ADMIN_PATH + '/backend') {
                if (!adminCan(user, 'backend')) return deny('the backend');
                const form = await readForm();
                if (!form) return back('Could not read the backend form.', false, 'backend');
                const reset = String(form.get('action') || '') === 'reset';
                const result = await saveBackendUrl(env, reset ? '' : form.get('backend_url'));
                return back(result.ok ? (result.reset ? 'Backend URL reset to the Worker RAILWAY_URL variable.' : 'Backend URL saved and applied.') : result.error, result.ok, 'backend');
            }
            if (path === ADMIN_PATH + '/providers') {
                if (!adminCan(user, 'providers')) return deny('providers');
                const form = await readForm();
                if (!form) return back('Could not read the form.', false, 'providers');
                const next = { modes: {}, order: String(form.get('order') || '').split(',').map(x => x.trim()), defaultProvider: String(form.get('default_provider') || ''), defaultQuery: form.get('default_query'), lockMessage: form.get('lock_message') };
                for (const p of PROVIDERS) next.modes[p.id] = String(form.get('mode_' + p.id) || 'live');
                const ok = await saveProviderConfig(env, next);
                return back(ok ? 'Providers saved. ' + browseProviders(normalizeProviderConfig(next)).length + ' live in Browse.' : 'Could not save providers. ' + (__dbError || 'D1 write error.'), ok, 'providers');
            }
            if (path === ADMIN_PATH + '/providers/bulk') {
                if (!adminCan(user, 'providers')) return deny('providers');
                const form = await readForm();
                const action = form ? String(form.get('action') || '') : '';
                const cur = await getProviderConfig(env, true);
                let next = null, label = '';
                if (action === 'unlock_all') { next = { ...cur, modes: Object.fromEntries(PROVIDERS.map(p => [p.id, 'live'])) }; label = 'All providers are live.'; }
                else if (action === 'lock_all') { next = { ...cur, modes: Object.fromEntries(PROVIDERS.map(p => [p.id, 'locked'])) }; label = 'All providers are locked.'; }
                else if (action === 'reset') { next = normalizeProviderConfig(null); label = 'Providers reset to defaults.'; }
                if (!next) return redirect(ADMIN_PATH + '#providers');
                const ok = await saveProviderConfig(env, next);
                return back(ok ? label : 'Could not save providers. ' + (__dbError || 'D1 write error.'), ok, 'providers');
            }
            if (path === ADMIN_PATH + '/members') {
                if (!adminCan(user, 'site')) return deny('members');
                const form = await readForm();
                if (!form) return back('Could not read the form.', false, 'members');
                const res = await handleMembersAdmin(env, form);
                return back(res.ok ? res.message : res.error, res.ok, 'members');
            }
            if (path === ADMIN_PATH + '/social') {
                if (!adminCan(user, 'social')) return deny('social media');
                const form = await readForm();
                if (!form) return back('Could not read the form.', false, 'social');
                const res = await handleSocialAction(env, url.origin, user, form);
                return back(res.ok ? res.message : res.error, res.ok, 'social');
            }
            if (path === ADMIN_PATH + '/telegram') {
                if (!adminCan(user, 'social')) return deny('Telegram settings');
                const form = await readForm();
                if (!form) return back('Could not read the Telegram form.', false, 'social');
                const action = String(form.get('action') || 'save');
                if (action === 'reset_token') {
                    const result = await resetTelegramTokenOverride(env);
                    return back(result.ok ? 'Telegram token reset to the Worker secret.' : result.error, result.ok, 'social');
                }
                if (action !== 'save') return htmlResponse(render404Html(), 404, adminHtmlHeaders());
                const result = await saveTelegramSettings(env, form.get('bot_token'), form.get('webhook_origin'));
                return back(result.ok ? 'Telegram settings saved.' : result.error, result.ok, 'social');
            }
            if (path === ADMIN_PATH + '/live') {
                if (!user.owner) return deny('live viewers');
                const form = await readForm();
                if (!form) return back('Could not read the live viewers form.', false, 'live');
                const parsed = parseLiveForm(form, await getLiveConfig(env, true));
                if (!parsed.ok) return back(parsed.error, false, 'live');
                const ok = await saveLiveConfig(env, parsed.cfg);
                return back(ok ? 'Live viewers saved.' + (parsed.cfg.enabled ? '' : ' The counter is hidden on the site.') : 'Could not save live viewers. ' + (__dbError || 'D1 write error.'), ok, 'live');
            }
            if (path === ADMIN_PATH + '/repair') {
                if (!adminCan(user, 'operations')) return deny('operations');
                const h = await dbHealth(env);
                __usersReady = false;
                const usersOk = await ensureAdminUsersSchema(env);
                const ok = h.binding && h.table && h.write && usersOk;
                return back(ok ? 'Database is healthy. Settings and admin tables ready and writable.' : 'Database still failing. ' + (h.error || __dbError || 'Unknown error.'), ok, 'operations');
            }
            if (path === ADMIN_PATH + '/setup') {
                if (!adminCan(user, 'social')) return deny('Telegram settings');
                const data = await setupTelegramWebhook(url.origin, env).catch(e => ({ ok: false, description: String(e && e.message) }));
                const ok = !!(data && data.ok);
                return back(ok ? 'Telegram webhook connected.' : 'Telegram setup failed: ' + ((data && data.description) || 'unknown error'), ok, 'social');
            }
            return htmlResponse(render404Html(), 404, adminHtmlHeaders());
        }

        // ---------------------------------------------------------------- telegram webhook
        if (request.method === 'POST' && path === '/webhook') {
            return handleTelegramMessage(request, url.origin, ctx, env);
        }

        // ---------------------------------------------------------------- maintenance gate
        const isMedia = path.startsWith('/proxy-m3u8') || path.startsWith('/proxy-video') || path === '/proxy-image' || path === '/api/v1/image';
        const isDiag = path === '/status' || path === '/api/status' || path === '/check-host' || path.startsWith('/api/check-host/');
        if (!isMedia && !isDiag) {
            if (await isMaintenanceOn(env)) {
                const appLoginAllowed = path === APP_API_PREFIX + '/auth/login';
                const appOwner = path.startsWith(APP_API_PREFIX + '/') ? await appApiAdmin(request, env) : null;
                if (!appLoginAllowed && !(await verifyAdminSession(request, env)) && !appOwner) {
                    if (path.startsWith('/api/')) return appApiJson({ status: 'error', error: 'VexoStream is under maintenance. Try again soon.', code: 'maintenance' }, 503, { 'Retry-After': '3600' });
                    return htmlResponse(renderMaintenanceHtml(), 503, { ...SECURE_HTML_HEADERS, 'Retry-After': '3600', 'Cache-Control': 'no-store' });
                }
            }
        }

        // ---------------------------------------------------------------- native app API
        if (path === APP_API_PREFIX || path.startsWith(APP_API_PREFIX + '/')) {
            return handleAppApiV1(request, url, env, ctx);
        }

        // ---------------------------------------------------------------- member accounts
        if (path === '/login' || path === '/signup' || path === '/register') {
            if (path === '/register') return new Response(null, { status: 301, headers: { 'Location': '/signup' + url.search, 'Cache-Control': 'public, max-age=86400' } });
            const next = safeNext(url.searchParams.get('next'));
            if (await verifyMemberSession(request, env) || await verifyAdminSession(request, env)) return redirect(next);
            return htmlResponse(renderAuthHtml(path === '/signup' ? 'signup' : 'login', { next, gate: url.searchParams.get('gate') === '1' }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        if (path === '/logout' || path === '/account/logout') {
            const headers = new Headers({ 'Location': '/', 'Cache-Control': 'no-store' });
            headers.append('Set-Cookie', memberCookieClear());
            headers.append('Set-Cookie', ADMIN_COOKIE_NAME + '=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0');
            return new Response(null, { status: 302, headers });
        }
        if (request.method === 'POST' && (path === '/account/login' || path === '/account/signup')) {
            const origin = request.headers.get('Origin');
            if (origin && origin !== url.origin) return new Response('Cross-site request blocked', { status: 403, headers: { 'Cache-Control': 'no-store' } });
            const signup = path === '/account/signup';
            const ip = clientIpOf(request);
            let form = null;
            try { form = await request.formData(); } catch (_) {}
            const next = safeNext(form && form.get('next'));
            const username = String((form && form.get('username')) || '').trim().slice(0, 40);
            const again = (error, status) => htmlResponse(renderAuthHtml(signup ? 'signup' : 'login', { next, error, username }), status, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            if (!form) return again('Could not read the form. Try again.', 400);
            if (memberThrottled(ip)) return again('Too many tries. Wait 10 minutes and try again.', 429);
            if (signup && await verifyAdminSession(request, env)) return again('You’re signed in with an admin account. Use your existing admin login; a member account is not needed.', 403);
            if (signup && form.get('adult') !== '1') return again('You must be 18 or older to create an account.', 400);
            let res;
            if (signup) {
                res = await signupMember(env, username, form.get('password'), form.get('password2'));
            } else {
                const admin = await authenticateAdmin(env, username, form.get('password'));
                res = admin ? { ok: true, admin } : await loginMember(env, username, form.get('password'));
            }
            if (!res.ok) { memberFailed(ip); return again(res.error, signup ? 400 : 401); }
            const cookie = res.admin
                ? adminSessionCookie(await createAdminSession(res.admin))
                : memberCookie(await createMemberSession(res.member));
            return redirect(next, { 'Set-Cookie': cookie });
        }

        if (request.method !== 'GET' && request.method !== 'HEAD') {
            return jsonResponse({ status: 'error', error: 'Method not allowed' }, 405, { 'Allow': 'GET, HEAD, OPTIONS' });
        }

        // ---------------------------------------------------------------- token-gated APIs
        if (path === '/api/extract' || path.startsWith('/api/explore') || path.startsWith('/api/models') || path === '/api/posters' || path === '/proxy-image') {
            const caller = await isApiCallerAllowed(request, url);
            if (!caller.ok) return jsonResponse({ status: 'error', error: caller.reason || 'Unauthorized API access', code: caller.code || 'blocked' }, 403, { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
        }

        if (path.startsWith('/api/models')) {
            const mc = await getMembersConfig(env);
            const edge = request.headers.get('X-Edge-Token') || '';
            const trusted = !!edge && timingSafeEqual(edge, EDGE_TOKEN);
            if (mc.modelsLogin && !trusted && !(await verifyMemberSession(request, env)) && !(await verifyAdminSession(request, env))) {
                return jsonResponse({ status: 'error', error: 'Please log in first.', code: 'login' }, 401, { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
            }
        }

        // ---------------------------------------------------------------- provider locks
        if (path.startsWith('/api/explore')) {
            const cfg = await getProviderConfig(env, true);
            const asked = (url.searchParams.get('provider') || '').trim().toLowerCase();
            const pv = asked || defaultProviderOf(cfg);
            if (!pv) return lockedJson(cfg, pv);
            if (isProviderHidden(cfg, pv)) return hiddenJson(pv);
            if (isProviderLocked(cfg, pv)) return lockedJson(cfg, pv);
            if (!asked) { url.searchParams.set('provider', pv); request = new Request(url.toString(), request); }
        }
        if (path === '/api/extract') {
            const cfg = await getProviderConfig(env, true);
            const pv = providerForUrl(url.searchParams.get('url') || '');
            if (isProviderHidden(cfg, pv)) return hiddenJson(pv);
            if (isProviderLocked(cfg, pv)) return lockedJson(cfg, pv);
            // Log in to watch: the stream resolver only answers members (or open embeds / your own server tools).
            const mc = await getMembersConfig(env);
            if (mc.requireLogin) {
                const edge = request.headers.get('X-Edge-Token') || '';
                const trusted = !!edge && timingSafeEqual(edge, EDGE_TOKEN);
                let fromEmbed = false;
                try { const ref = new URL(request.headers.get('Referer') || ''); fromEmbed = ref.origin === url.origin && ref.pathname.startsWith('/embed'); } catch (_) {}
                const appGrant = await verifyAppEmbedGrant(
                    url.searchParams.get('url') || '',
                    request.headers.get('X-Vexo-Embed-Grant') || ''
                );
                if (!trusted && !(fromEmbed && !mc.embedsToo) && !appGrant && !(await verifyMemberSession(request, env)) && !(await verifyAdminSession(request, env))) {
                    return jsonResponse({ status: 'error', error: 'Please log in first.', code: 'login' }, 401, { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
                }
            }
        }
        if (path === '/api/providers') {
            const cfg = await getProviderConfig(env, true);
            return jsonResponse({
                providers: listedProviders(cfg).map(p => ({ id: p.id, name: p.name, domain: p.domain, status: p.mode, browse: p.mode === 'live', playback: p.mode === 'live', available: p.mode === 'live' })),
                default: defaultProviderOf(cfg)
            }, 200, { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' });
        }

        // ---------------------------------------------------------------- pages
        if (path === '/' || path === '/index.html') {
            // Old single-page links (/?q=..&provider=..&page=..) now live on real pages
            const oq = (url.searchParams.get('q') || '').trim();
            const op = (url.searchParams.get('provider') || '').trim().toLowerCase();
            const opg = parseInt(url.searchParams.get('page') || '1', 10);
            if (oq) {
                const sp = new URLSearchParams({ q: oq.slice(0, 100) });
                if (op) sp.set('provider', op);
                if (opg > 1) sp.set('page', String(opg));
                return redirect('/search?' + sp.toString());
            }
            if (op) return redirect('/browse/' + encodeURIComponent(op) + (opg > 1 ? '?page=' + opg : ''));
            if (path === '/index.html') return new Response(null, { status: 301, headers: { 'Location': '/', 'Cache-Control': 'public, max-age=86400' } });
            const meta = buildSocialCardMetaTags({ title: 'VexoStream | Ad-Free HD Video Player (18+)', description: SEO_DEFAULT_DESC, url: '/', jsonld: seoHomeJsonLd() });
            return htmlResponse(renderHomeHtml(meta, await getProviderConfig(env, true)), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }

        // ---------------------------------------------------------------- browse / search / developers
        const pageNum = () => { const n = parseInt(url.searchParams.get('page') || '1', 10); return n > 0 && n < 1000 ? n : 1; };
        if (path === '/browse' || path === '/browse/') {
            const cfg = await getProviderConfig(env, true);
            const def = defaultProviderOf(cfg);
            const meta = buildSocialCardMetaTags({ title: 'Browse Videos | VexoStream', description: 'Browse every video library on VexoStream in one clean, ad-free HD player.', url: '/browse' });
            if (!def) return htmlResponse(renderCatalogHtml(meta, cfg, { kind: 'browse', provider: '', page: 1 }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            return redirect('/browse/' + def + (pageNum() > 1 ? '?page=' + pageNum() : ''));
        }
        if (path.startsWith('/browse/')) {
            let id = '';
            try { id = decodeURIComponent(path.slice(8).replace(/\/+$/, '')).toLowerCase(); } catch (_) { id = ''; }
            const cfg = await getProviderConfig(env, true);
            if (!PROVIDERS.some(p => p.id === id) || isProviderHidden(cfg, id)) return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            if (isProviderLocked(cfg, id)) return htmlResponse(renderProviderLockedHtml(cfg, id, false), 423, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            const pn = pageNum();
            const bUrl = '/browse/' + id + (pn > 1 ? '?page=' + pn : '');
            const meta = buildSocialCardMetaTags({
                title: 'Trending ' + providerName(id) + ' Videos' + (pn > 1 ? ', Page ' + pn : '') + ' | VexoStream',
                description: 'Watch trending ' + providerName(id) + ' videos on VexoStream: no ads, every quality from 240p to 4K, one clean player.' + (pn > 1 ? ' Page ' + pn + '.' : ''),
                url: bUrl,
                jsonld: seoBreadcrumbs([['VexoStream', '/'], ['Browse', '/browse'], [providerName(id), '/browse/' + id]])
            });
            return htmlResponse(renderCatalogHtml(meta, cfg, { kind: 'browse', provider: id, page: pageNum() }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        if (path === '/search' || path === '/search/') {
            const cfg = await getProviderConfig(env, true);
            const q = (url.searchParams.get('q') || '').trim().slice(0, 100);
            let pv = (url.searchParams.get('provider') || '').trim().toLowerCase();
            if (!browseProviders(cfg).some(p => p.id === pv)) pv = defaultProviderOf(cfg);
            // Internal search results stay out of Google (thin/duplicate pages), links are still followed.
            const meta = buildSocialCardMetaTags({ title: (q ? q + ' | ' : '') + 'Search | VexoStream', description: q ? 'Results for ' + q + ' on VexoStream.' : 'Search the VexoStream catalogue.', url: '/search', robots: SEO_NOINDEX });
            return htmlResponse(renderCatalogHtml(meta, cfg, { kind: 'search', provider: pv, q, page: pageNum() }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        if (path === '/developers' || path === '/developers/') {
            const meta = buildSocialCardMetaTags({ title: 'Embed the VexoStream Player | Developers', description: 'Embed the ad-free VexoStream HD player on any website with one line of code. Responsive, HLS and MP4, every quality.', url: '/developers', jsonld: seoBreadcrumbs([['VexoStream', '/'], ['Developers', '/developers']]) });
            return htmlResponse(renderDevelopersHtml(meta, url.origin), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'public, max-age=300' });
        }
        if (path === '/social' || path === '/social/' || path === '/socials' || path === '/bots') {
            if (path !== '/social') return new Response(null, { status: 301, headers: { 'Location': '/social', 'Cache-Control': 'public, max-age=86400' } });
            const meta = buildSocialCardMetaTags({ title: 'VexoStream on Telegram & Social Media', description: 'Follow VexoStream: our Telegram channel, bots and official social media accounts.', url: '/social' });
            return htmlResponse(renderSocialPageHtml(meta, await getSocialConfig(env)), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        // Models: members only (Admin > Members > "Models pages need an account")
        if (path === '/models' || path.startsWith('/models/')) {
            const mc = await getMembersConfig(env);
            if (mc.modelsLogin && !(await verifyMemberSession(request, env)) && !(await verifyAdminSession(request, env))) {
                const gm = buildSocialCardMetaTags({ title: 'Please log in first | VexoStream', description: 'Log in or create a free account to see OnlyFans models on VexoStream.', url: path, robots: SEO_NOINDEX, canonical: false });
                return htmlResponse(renderAuthHtml('login', { next: path + url.search, gate: true, gateText: 'Please log in first. Models are for members only.', meta: gm }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            }
        }
        if (path === '/models' || path === '/models/') {
            const meta = buildSocialCardMetaTags({ title: 'OnlyFans Models | VexoStream', description: 'Browse the most popular public performer profiles on VexoStream, sorted by gender.', url: '/models' });
            return htmlResponse(renderModelsHtml(meta), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        if (path.startsWith('/models/')) {
            let slug = '';
            try { slug = decodeURIComponent(path.slice('/models/'.length).replace(/\/+$/, '')); } catch (_) {}
            if (!/^[a-zA-Z0-9][a-zA-Z0-9-]{0,119}$/.test(slug)) return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            const meta = buildSocialCardMetaTags({ title: slug.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()) + ' | OnlyFans Models | VexoStream', description: 'Public profile of ' + slug.replace(/-/g, ' ') + ' on VexoStream: performer details and photos.', url: '/models/' + encodeURIComponent(slug) });
            return htmlResponse(renderModelsHtml(meta, slug), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
        }
        if (path === '/creator' || path === '/setup') {
            return redirect(path === '/setup' ? ADMIN_PATH : '/');
        }

        const parts = path.split('/');
        if ((parts[1] === 'video' || parts[1] === 'embed') && parts[2]) {
            const target = decodeVideoParam(parts[2]);
            if (!target) return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
            const appGrant = parts[1] === 'embed' ? (url.searchParams.get('app_grant') || '') : '';
            const validAppGrant = appGrant ? await verifyAppEmbedGrant(target, appGrant) : false;
            {
                const cfg = await getProviderConfig(env, true);
                const pv = providerForUrl(target);
                if (isProviderHidden(cfg, pv)) return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
                if (isProviderLocked(cfg, pv)) {
                    return parts[1] === 'embed'
                        ? htmlResponse(renderProviderLockedHtml(cfg, pv, true), 423, { ...EMBED_HTML_HEADERS, 'Cache-Control': 'no-store' })
                        : htmlResponse(renderProviderLockedHtml(cfg, pv, false), 423, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
                }
            }
            // Log in to watch
            {
                const mc = await getMembersConfig(env);
                const gated = mc.requireLogin && (parts[1] === 'video' || mc.embedsToo);
                if (gated && !validAppGrant && !(await verifyMemberSession(request, env)) && !(await verifyAdminSession(request, env))) {
                    if (parts[1] === 'embed') return htmlResponse(renderEmbedGateHtml(url.origin, '/video/' + parts[2]), 200, { ...EMBED_HTML_HEADERS, 'Cache-Control': 'no-store' });
                    let pv = { title: '', thumb: '' };
                    if (isSocialEmbedBot(request.headers.get('User-Agent'))) pv = await socialPreview(target);
                    const gm = buildSocialCardMetaTags({ title: pv.title ? pv.title + ' | VexoStream' : 'Please log in first | VexoStream', description: 'Log in or create a free account to watch on VexoStream.', url: path, image: pv.thumb, robots: SEO_NOINDEX, canonical: false });
                    return htmlResponse(renderAuthHtml('login', { next: path, gate: true, meta: gm }), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
                }
            }
            const canonical = url.origin + '/' + parts[1] + '/' + parts[2];
            const embedUrl = url.origin + '/embed/' + parts[2];
            let preview = { title: '', thumb: '' };
            if (isSocialEmbedBot(request.headers.get('User-Agent'))) preview = await socialPreview(target);
            const title = preview.title || 'VexoStream Player';
            const meta = buildSocialCardMetaTags({
                title: preview.title ? preview.title + ' | VexoStream' : title,
                description: 'Watch ' + (preview.title || 'this video') + ' on VexoStream, ad-free in every quality.',
                url: canonical,
                // Third-party videos behind a login: keep them out of the index (duplicate content).
                robots: SEO_NOINDEX,
                canonical: false,
                image: preview.thumb,
                video: embedUrl
            });
            if (parts[1] === 'embed') return htmlResponse(renderEmbedHtml(target, meta, preview.thumb, validAppGrant ? appGrant : ''), 200, EMBED_HTML_HEADERS);
            return htmlResponse(renderWatchHtml(target, meta, { title: preview.title, thumb: preview.thumb }));
        }

        if (path === '/embed.js') {
            return new Response(renderEmbedSdk(url.origin), {
                headers: { 'Content-Type': 'application/javascript;charset=UTF-8', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'public, max-age=3600' }
            });
        }
        if (path === '/embed' || path === '/view_video.php') {
            const target = targetFromQuery(url);
            if (!target) return new Response('Missing url or viewkey parameter', { status: 400 });
            if (path === '/embed') {
                const cfg = await getProviderConfig(env, true);
                const pv = providerForUrl(target);
                if (isProviderHidden(cfg, pv)) return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
                if (isProviderLocked(cfg, pv)) return htmlResponse(renderProviderLockedHtml(cfg, pv, true), 423, { ...EMBED_HTML_HEADERS, 'Cache-Control': 'no-store' });
                return htmlResponse(renderEmbedHtml(target, ''), 200, EMBED_HTML_HEADERS);
            }
            return redirect('/video/' + b64urlEncode(target));
        }

        if (path === '/proxy-image') return handleImageProxy(request, ctx);
        if (path.startsWith('/proxy-m3u8') || path.startsWith('/proxy-video')) return handleWorkerStreamProxy(request, url);

        if (path === '/check-host' || path === '/check-host/' || path === '/checkhost' || path === '/check') {
            if (path !== '/check-host') return new Response(null, { status: 301, headers: { 'Location': '/check-host' + url.search, 'Cache-Control': 'public, max-age=86400' } });
            const qt = String(url.searchParams.get('type') || 'http').toLowerCase();
            const init = {
                type: CH_TYPES.includes(qt) ? qt : 'http',
                host: String(url.searchParams.get('host') || '').slice(0, 300),
                port: String(url.searchParams.get('port') || '').replace(/\D/g, '').slice(0, 5),
                cc: String(url.searchParams.get('cc') || '').toLowerCase().split(',').filter(c => CH_CC.includes(c))
            };
            if (!init.cc.length) init.cc = null;
            const cMeta = buildSocialCardMetaTags({
                title: 'Check Host | VexoStream Network Diagnostics',
                description: 'Run ping, HTTP, TCP, and DNS checks for VexoStream-owned or explicitly authorized hosts. Regional probes use Check-Host.net, with Globalping as a fallback.',
                url: '/check-host',
                robots: url.search ? 'noindex, follow' : undefined
            });
            return htmlResponse(renderCheckHostHtml(cMeta, init), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store, max-age=0' });
        }
        if (path === '/api/check-host/start') return handleCheckHostStart(request, url, env);
        if (path === '/api/check-host/result') return handleCheckHostResult(url, env);
        if (path === '/api/check-host/nodes') {
            const all = await checkHostNodes();
            return jsonResponse({ countries: CH_COUNTRIES, nodes: Object.keys(all).map(id => ({ id, cc: all[id][0], city: all[id][2], asn: all[id][4] })) }, 200, { 'Cache-Control': 'public, max-age=600', 'X-Robots-Tag': 'noindex' });
        }
        if (path === '/status') {
            const checks = await runStatusChecksAndStore(env);
            const history = await getRealStatusHistory(env, checks);
            const sMeta = buildSocialCardMetaTags({ title: 'VexoStream Status | Live System Health', description: 'Live health and 90-day uptime history for every part of VexoStream: player, edge, API and each video library.', url: '/status' });
            return htmlResponse(renderStatusHtml(checks, history, await getProviderConfig(env, true), sMeta), 200, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store, max-age=0' });
        }
        if (path === '/api/live') {
            const sid = String(url.searchParams.get('sid') || '').toLowerCase();
            await touchLivePresence(env, sid, ctx);
            return jsonResponse(await livePublicPayload(env), 200, { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': url.origin, 'X-Robots-Tag': 'noindex' });
        }
        if (path === '/api/status') {
            const checks = await runStatusChecks(env);
            const providerConfig = await getProviderConfig(env, true);
            const providers = listedProviders(providerConfig).map(p => ({ id: p.id, name: p.name, status: p.mode, available: p.mode === 'live' }));
            return jsonResponse({ ...checks, overall: statusOverall(checks), providers }, 200, { 'Cache-Control': 'no-store' });
        }
        if (path === '/api/posters') {
            // Real card posters (og:image of each video page), batched. Only
            // visible provider pages are forwarded; the API caches results.
            const cfg = await getProviderConfig(env);
            const keep = url.searchParams.getAll('u').map(u => String(u || '').trim()).filter((u, i, all) => {
                if (!u || all.indexOf(u) !== i || !/^https:\/\//i.test(u)) return false;
                const pv = providerForUrl(u);
                return !!pv && !isProviderHidden(cfg, pv);
            }).slice(0, 24);
            if (!keep.length) return jsonResponse({ posters: {} }, 200, { 'Cache-Control': 'no-store' });
            const clean = new URL(url.origin + '/api/posters');
            keep.forEach(u => clean.searchParams.append('u', u));
            return forwardToRailway(new Request(clean.toString(), request), ctx);
        }
        if (path.startsWith('/api/')) return forwardToRailway(request, ctx);

        return htmlResponse(render404Html(), 404, { ...SECURE_HTML_HEADERS, 'Cache-Control': 'no-store' });
    } catch (fatalError) {
        console.error('Unhandled error:', fatalError && (fatalError.stack || fatalError.message));
        return new Response('Something went wrong. Please try again.', { status: 500, headers: { 'Content-Type': 'text/plain;charset=UTF-8', 'Cache-Control': 'no-store' } });
    }
}

export default {
    async fetch(request: Request, env: WorkerBindings, ctx: WorkerContext) {
        let response = await handleRequest(request, env, ctx);
        try { response = await injectMemberState(response, request, env); } catch (_) {}
        try { response = await injectSessionToken(response, request); } catch (_) {}
        try { return finalizeSeoHeaders(response, request); } catch (_) { return response; }
    },
    async scheduled(event: unknown, env: WorkerBindings, ctx: WorkerContext) {
        initConfig(env);
        ctx.waitUntil(runStatusChecksAndStore(env, true));
    }
};
