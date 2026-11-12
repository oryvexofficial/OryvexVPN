// ============================================================================
// ADMIN ACCOUNTS + PERMISSIONS (D1 table: admin_users)
//
// - The owner (DEFAULTS.CREATOR, "Muvixo") always has every permission, can't
//   be removed or demoted, and is the only one who can grant "Team".
// - Admins with the "Team" permission can add admins and set permissions for
//   admins below them (never for the owner, themselves, or other Team admins).
// - Every account can change its own password. Passwords are PBKDF2-SHA256
//   (100k iterations, per-user salt). Changing a password, permissions, or
//   removing an account bumps the account "stamp", which signs the session
//   cookie, so old sessions stop working immediately.
// - Bootstrap: accounts in the ADMIN_USERS secret ({"name":"<sha256>"}) still
//   sign in. On first sign-in they are copied into D1 and from then on the D1
//   password wins (so "change password" really changes it).
// ============================================================================
const ADMIN_PERMISSIONS = [
    { id: 'site', label: 'Site mode', hint: 'Turn maintenance on or off' },
    { id: 'backend', label: 'Backend', hint: 'Change the API server URL' },
    { id: 'providers', label: 'Providers', hint: 'Lock, hide and reorder libraries' },
    { id: 'operations', label: 'Operations', hint: 'Repair the database' },
    { id: 'social', label: 'Social media', hint: 'Telegram bot, channel posts and social links' },
    { id: 'users', label: 'Team', hint: 'Add admins and set their permissions' }
];
const ADMIN_PERM_IDS = ADMIN_PERMISSIONS.map(p => p.id);
const ADMIN_PBKDF2_ITER = 100000; // Workers cap PBKDF2 at 100k iterations
const ADMIN_PW_MIN = 10;
const ADMIN_PW_MAX = 128;
const ADMIN_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{2,31}$/;

let __usersReady = false;
const __userCache = new Map(); // lowercase name -> { at, user }

function ownerName() { return String(DEFAULTS.CREATOR || 'Muvixo'); }
function isOwnerName(name) { return String(name || '').toLowerCase() === ownerName().toLowerCase(); }
function adminCan(user, perm) { return !!user && (user.owner || (Array.isArray(user.permissions) && user.permissions.includes(perm))); }
function cleanPerms(list) { return ADMIN_PERM_IDS.filter(id => (list || []).includes(id)); }

function bytesToHex(bytes) { return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join(''); }
function hexToBytes(hex) {
    const clean = String(hex || '').replace(/[^0-9a-f]/gi, '');
    const out = new Uint8Array(clean.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
    return out;
}
function randomHex(bytes = 16) { const b = new Uint8Array(bytes); crypto.getRandomValues(b); return bytesToHex(b); }

async function hashAdminPassword(password, saltHex, iterations = ADMIN_PBKDF2_ITER) {
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(String(password)), 'PBKDF2', false, ['deriveBits']);
    const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: hexToBytes(saltHex), iterations }, key, 256);
    return bytesToHex(new Uint8Array(bits));
}

function passwordProblem(pw) {
    const p = String(pw || '');
    if (p.length < ADMIN_PW_MIN) return 'Use at least ' + ADMIN_PW_MIN + ' characters.';
    if (p.length > ADMIN_PW_MAX) return 'Use at most ' + ADMIN_PW_MAX + ' characters.';
    if (/^(.)\1+$/.test(p)) return 'That password is too easy to guess.';
    return '';
}

async function ensureAdminUsersSchema(env) {
    if (!env || !env.DB) return false;
    if (__usersReady) return true;
    try {
        await env.DB.prepare(
            'CREATE TABLE IF NOT EXISTS admin_users (' +
            'username TEXT PRIMARY KEY COLLATE NOCASE, password_hash TEXT NOT NULL, salt TEXT NOT NULL, ' +
            'iterations INTEGER NOT NULL DEFAULT 100000, permissions TEXT NOT NULL DEFAULT \'[]\', ' +
            'is_owner INTEGER NOT NULL DEFAULT 0, disabled INTEGER NOT NULL DEFAULT 0, stamp TEXT NOT NULL, ' +
            'created_by TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP, updated_at TEXT DEFAULT CURRENT_TIMESTAMP, last_login TEXT)'
        ).run();
        __usersReady = true;
        return true;
    } catch (e) {
        __dbError = 'Admin users table: ' + dbErrText(e);
        return false;
    }
}

function rowToAdmin(row) {
    if (!row) return null;
    let perms = [];
    try { perms = JSON.parse(row.permissions || '[]'); } catch (_) { perms = []; }
    const owner = !!Number(row.is_owner);
    return {
        username: String(row.username),
        owner,
        permissions: owner ? ADMIN_PERM_IDS.slice() : cleanPerms(perms),
        disabled: !!Number(row.disabled),
        stamp: String(row.stamp || ''),
        hash: String(row.password_hash || ''),
        salt: String(row.salt || ''),
        iterations: Number(row.iterations) || ADMIN_PBKDF2_ITER,
        createdBy: row.created_by ? String(row.created_by) : '',
        createdAt: row.created_at ? String(row.created_at) : '',
        lastLogin: row.last_login ? String(row.last_login) : '',
        legacy: false
    };
}

async function getAdminRow(env, username) {
    if (!(await ensureAdminUsersSchema(env))) return null;
    try {
        return rowToAdmin(await env.DB.prepare('SELECT * FROM admin_users WHERE username = ? COLLATE NOCASE LIMIT 1').bind(String(username)).first());
    } catch (e) { __dbError = 'Admin users read: ' + dbErrText(e); return null; }
}

async function listAdminUsers(env) {
    if (!(await ensureAdminUsersSchema(env))) return null;
    try {
        const res = await env.DB.prepare('SELECT * FROM admin_users WHERE disabled = 0 ORDER BY is_owner DESC, username COLLATE NOCASE ASC').all();
        return ((res && res.results) || []).map(rowToAdmin);
    } catch (e) { __dbError = 'Admin users list: ' + dbErrText(e); return null; }
}

async function ownerExists(env) {
    try {
        const r = await env.DB.prepare('SELECT username FROM admin_users WHERE is_owner = 1 AND disabled = 0 LIMIT 1').first();
        return !!r;
    } catch (_) { return false; }
}

function legacyAdminKey(username) {
    const keys = Object.keys(ADMIN_USERS || {});
    return keys.find(k => k === username) || '';
}

async function legacyAdminUser(username) {
    const key = legacyAdminKey(username);
    if (!key) return null;
    return {
        username: key, owner: isOwnerName(key), permissions: ADMIN_PERM_IDS.slice(), disabled: false,
        stamp: 'env:' + (await sha256Hex(String(ADMIN_USERS[key]))).slice(0, 16), legacy: true
    };
}

function forgetAdminCache(username) { __userCache.delete(String(username || '').toLowerCase()); }

// Account used to validate a session cookie (10 s isolate cache).
async function loadSessionUser(env, username) {
    const k = String(username || '').toLowerCase();
    const hit = __userCache.get(k);
    if (hit && Date.now() - hit.at < 10000) return hit.user;
    let user = null;
    if (env && env.DB) user = await getAdminRow(env, username);
    if (!user) user = await legacyAdminUser(username);
    __userCache.set(k, { at: Date.now(), user });
    return user;
}

async function createAdminSession(user) {
    const exp = Math.floor(Date.now() / 1000) + ADMIN_SESSION_TTL;
    const sig = await generateHmacSha256(user.username + ':' + exp + ':' + user.stamp, ADMIN_SESSION_SECRET);
    return encodeURIComponent(user.username + '.' + exp + '.' + sig);
}

function adminSessionCookie(token) {
    return ADMIN_COOKIE_NAME + '=' + token + '; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=' + ADMIN_SESSION_TTL;
}

async function verifyAdminSession(request, env) {
    const cookie = request.headers.get('Cookie') || '';
    const m = cookie.match(new RegExp('(?:^|;\\s*)' + ADMIN_COOKIE_NAME + '=([^;]+)'));
    if (!m) return null;
    let raw;
    try { raw = decodeURIComponent(m[1]); } catch (_) { return null; }
    const parts = raw.split('.');
    if (parts.length !== 3) return null;
    const [uname, expStr, sig] = parts;
    const exp = parseInt(expStr, 10);
    if (!uname || !ADMIN_NAME_RE.test(uname) && !legacyAdminKey(uname)) return null;
    if (isNaN(exp) || Math.floor(Date.now() / 1000) > exp) return null;
    const user = await loadSessionUser(env, uname);
    if (!user || user.disabled) return null;
    const expected = await generateHmacSha256(user.username + ':' + exp + ':' + user.stamp, ADMIN_SESSION_SECRET);
    return timingSafeEqual(expected, sig) ? user : null;
}

// Sign in: D1 account first; ADMIN_USERS secret only while no D1 row exists.
async function authenticateAdmin(env, username, password) {
    const name = String(username || '').trim();
    if (!name || name.length > 64) return null;
    const hasDb = !!(env && env.DB) && (await ensureAdminUsersSchema(env));
    if (hasDb) {
        const row = await getAdminRow(env, name);
        if (row) {
            if (row.disabled) return null;
            const given = await hashAdminPassword(password, row.salt, row.iterations);
            if (!timingSafeEqual(given, row.hash)) return null;
            try { await env.DB.prepare('UPDATE admin_users SET last_login = CURRENT_TIMESTAMP WHERE username = ? COLLATE NOCASE').bind(row.username).run(); } catch (_) {}
            return row;
        }
    }
    const key = legacyAdminKey(name);
    if (!key) return null;
    const given = await sha256Hex(String(password));
    if (!timingSafeEqual(given, String(ADMIN_USERS[key]).toLowerCase())) return null;
    if (hasDb) {
        // First sign-in from the secret: copy the account into D1.
        const anyOwner = await ownerExists(env);
        const secretHasOwner = Object.keys(ADMIN_USERS || {}).some(isOwnerName);
        const owner = isOwnerName(key) || (!anyOwner && !secretHasOwner);
        const salt = randomHex(16);
        const hash = await hashAdminPassword(password, salt);
        try {
            await env.DB.prepare('INSERT INTO admin_users (username, password_hash, salt, iterations, permissions, is_owner, disabled, stamp, created_by, last_login) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, CURRENT_TIMESTAMP)')
                .bind(key, hash, salt, ADMIN_PBKDF2_ITER, JSON.stringify(ADMIN_PERM_IDS), owner ? 1 : 0, randomHex(8), 'secret').run();
            forgetAdminCache(key);
            const row = await getAdminRow(env, key);
            if (row) return row;
        } catch (e) { __dbError = 'Admin bootstrap: ' + dbErrText(e); }
    }
    return legacyAdminUser(key);
}

// ---------------------------------------------------------------- mutations
async function changeOwnPassword(env, user, current, next, confirm) {
    if (!user || user.legacy) return { ok: false, error: 'Password changes need the D1 database. Repair the database first.' };
    if (String(next) !== String(confirm)) return { ok: false, error: 'The new passwords don\u2019t match.' };
    const bad = passwordProblem(next);
    if (bad) return { ok: false, error: bad };
    const row = await getAdminRow(env, user.username);
    if (!row) return { ok: false, error: 'Account not found.' };
    const given = await hashAdminPassword(current, row.salt, row.iterations);
    if (!timingSafeEqual(given, row.hash)) return { ok: false, error: 'Your current password is wrong.' };
    if (String(current) === String(next)) return { ok: false, error: 'Pick a password you haven\u2019t used here.' };
    return setAdminPassword(env, row.username, next);
}

async function setAdminPassword(env, username, password) {
    const salt = randomHex(16);
    const hash = await hashAdminPassword(password, salt);
    try {
        await env.DB.prepare('UPDATE admin_users SET password_hash = ?, salt = ?, iterations = ?, stamp = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ? COLLATE NOCASE')
            .bind(hash, salt, ADMIN_PBKDF2_ITER, randomHex(8), String(username)).run();
        forgetAdminCache(username);
        return { ok: true, user: await getAdminRow(env, username) };
    } catch (e) { return { ok: false, error: 'Could not save the password. ' + dbErrText(e) }; }
}

// Who may manage whom.
function canManageTarget(actor, target) {
    if (!adminCan(actor, 'users') || !target) return false;
    if (target.owner) return false;
    if (target.username.toLowerCase() === actor.username.toLowerCase()) return false;
    if (!actor.owner && target.permissions.includes('users')) return false;
    return true;
}
function grantablePerms(actor, requested) {
    const perms = cleanPerms(requested);
    return actor.owner ? perms : perms.filter(p => p !== 'users');
}

async function createAdminAccount(env, actor, username, password, perms) {
    if (!adminCan(actor, 'users')) return { ok: false, error: 'You don\u2019t have permission to add admins.' };
    if (!(await ensureAdminUsersSchema(env))) return { ok: false, error: 'Team management needs the D1 database. Repair the database first.' };
    const name = String(username || '').trim();
    if (!ADMIN_NAME_RE.test(name)) return { ok: false, error: 'Usernames are 3\u201332 letters, numbers, - or _.' };
    if (isOwnerName(name)) return { ok: false, error: 'That username is reserved for the owner.' };
    const bad = passwordProblem(password);
    if (bad) return { ok: false, error: bad };
    const granted = grantablePerms(actor, perms);
    const existing = await getAdminRow(env, name);
    if (existing && !existing.disabled) return { ok: false, error: 'An admin called ' + existing.username + ' already exists.' };
    const salt = randomHex(16);
    const hash = await hashAdminPassword(password, salt);
    try {
        if (existing) {
            await env.DB.prepare('UPDATE admin_users SET username = ?, password_hash = ?, salt = ?, iterations = ?, permissions = ?, is_owner = 0, disabled = 0, stamp = ?, created_by = ?, created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, last_login = NULL WHERE username = ? COLLATE NOCASE')
                .bind(name, hash, salt, ADMIN_PBKDF2_ITER, JSON.stringify(granted), randomHex(8), actor.username, existing.username).run();
        } else {
            await env.DB.prepare('INSERT INTO admin_users (username, password_hash, salt, iterations, permissions, is_owner, disabled, stamp, created_by) VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)')
                .bind(name, hash, salt, ADMIN_PBKDF2_ITER, JSON.stringify(granted), randomHex(8), actor.username).run();
        }
        forgetAdminCache(name);
        return { ok: true, username: name, perms: granted };
    } catch (e) { return { ok: false, error: 'Could not add the admin. ' + dbErrText(e) }; }
}

async function updateAdminPermissions(env, actor, username, perms) {
    const target = await getAdminRow(env, username);
    if (!target || target.disabled) return { ok: false, error: 'Admin not found.' };
    if (!canManageTarget(actor, target)) return { ok: false, error: target.owner ? 'The owner always has every permission.' : 'You can\u2019t change permissions for ' + target.username + '.' };
    let granted = grantablePerms(actor, perms);
    // A non-owner can't take away "Team" from someone (they can't edit Team admins at all).
    if (!actor.owner && target.permissions.includes('users')) granted = Array.from(new Set(granted.concat('users')));
    try {
        await env.DB.prepare('UPDATE admin_users SET permissions = ?, stamp = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ? COLLATE NOCASE')
            .bind(JSON.stringify(cleanPerms(granted)), randomHex(8), target.username).run();
        forgetAdminCache(target.username);
        return { ok: true, username: target.username, perms: cleanPerms(granted) };
    } catch (e) { return { ok: false, error: 'Could not save permissions. ' + dbErrText(e) }; }
}

async function resetAdminPassword(env, actor, username, password) {
    const target = await getAdminRow(env, username);
    if (!target || target.disabled) return { ok: false, error: 'Admin not found.' };
    if (!canManageTarget(actor, target)) return { ok: false, error: 'You can\u2019t reset the password for ' + target.username + '.' };
    const bad = passwordProblem(password);
    if (bad) return { ok: false, error: bad };
    const res = await setAdminPassword(env, target.username, password);
    return res.ok ? { ok: true, username: target.username } : res;
}

async function removeAdminAccount(env, actor, username) {
    const target = await getAdminRow(env, username);
    if (!target || target.disabled) return { ok: false, error: 'Admin not found.' };
    if (!canManageTarget(actor, target)) return { ok: false, error: target.owner ? 'The owner can\u2019t be removed.' : 'You can\u2019t remove ' + target.username + '.' };
    try {
        // Kept as a disabled row so an ADMIN_USERS secret entry can't bring it back.
        await env.DB.prepare('UPDATE admin_users SET disabled = 1, permissions = \'[]\', stamp = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ? COLLATE NOCASE')
            .bind(randomHex(8), target.username).run();
        forgetAdminCache(target.username);
        return { ok: true, username: target.username };
    } catch (e) { return { ok: false, error: 'Could not remove the admin. ' + dbErrText(e) }; }
}

// ---------------------------------------------------------------- UI
function permChecks(name, selected, opts = {}) {
    return '<div class="perm-grid">' + ADMIN_PERMISSIONS.map(p => {
        const locked = opts.lockAll || (p.id === 'users' && !opts.canGrantUsers);
        const on = (selected || []).includes(p.id);
        return '<label class="perm' + (locked ? ' locked' : '') + '" title="' + escapeHtml(p.hint) + '">' +
            '<input type="checkbox" name="' + name + '" value="' + p.id + '"' + (on ? ' checked' : '') + (locked ? ' disabled' : '') + '>' +
            '<span><b>' + escapeHtml(p.label) + '</b><small>' + escapeHtml(p.hint) + '</small></span></label>';
    }).join('') + '</div>';
}

function rolePill(u) {
    if (u.owner) return '<span class="role owner">' + ICONS.crown + 'Owner</span>';
    if (u.permissions.includes('users')) return '<span class="role lead">Team admin</span>';
    return '<span class="role">Admin</span>';
}

function renderAccountCard(user) {
    const pw = (n, label, ac) => '<label class="opt"><span>' + label + '</span><input type="password" name="' + n + '" autocomplete="' + ac + '" minlength="' + (n === 'current' ? 1 : ADMIN_PW_MIN) + '" maxlength="' + ADMIN_PW_MAX + '" required></label>';
    return '<section class="card" id="account-card"><div class="card-kicker">YOUR ACCOUNT</div>' +
        '<div class="acct-head"><span class="avatar">' + escapeHtml(user.username.slice(0, 1).toUpperCase()) + '</span><div><h2>' + escapeHtml(user.username) + '</h2>' + rolePill(user) + '</div></div>' +
        (user.legacy
            ? '<p class="db-err">Signed in from the ADMIN_USERS secret without the database. Repair the database to change your password here.</p>'
            : '<form method="POST" action="' + ADMIN_PATH + '/account/password" class="pw-form">' +
              pw('current', 'Current password', 'current-password') + pw('next', 'New password', 'new-password') + pw('confirm', 'Repeat new password', 'new-password') +
              '<p class="hint">At least ' + ADMIN_PW_MIN + ' characters. Other devices signed in as you are signed out.</p>' +
              '<button class="btn sm" type="submit">Change password</button></form>') +
        '</section>';
}

function renderTeamCards(user, team) {
    if (!adminCan(user, 'users')) return '';
    if (!team) {
        return '<section class="card span"><div class="card-kicker">TEAM</div><h2>Admins</h2><p class="db-err">Team management needs the D1 database (binding DB). Use Repair database in Operations.</p></section>';
    }
    const canGrantUsers = user.owner;
    const add = '<section class="card span" id="add-admin"><div class="card-kicker">ADD ADMIN</div><h2>Invite a new admin</h2><p>Give them a username and a starting password, then pick what they can manage.</p>' +
        '<form method="POST" action="' + ADMIN_PATH + '/users/create" class="add-form">' +
        '<div class="add-fields"><label class="opt"><span>Username</span><input name="username" required pattern="[A-Za-z0-9][A-Za-z0-9_\\-]{2,31}" maxlength="32" autocomplete="off" spellcheck="false" placeholder="e.g. sara"></label>' +
        '<label class="opt"><span>Starting password</span><span class="pw-row"><input type="text" name="password" id="newAdminPw" required minlength="' + ADMIN_PW_MIN + '" maxlength="' + ADMIN_PW_MAX + '" autocomplete="new-password" spellcheck="false"><button type="button" class="btn quiet sm" data-genpw="newAdminPw">Generate</button></span></label></div>' +
        permChecks('perm', ['providers'], { canGrantUsers }) +
        '<div class="actions-row"><button class="btn sm" type="submit">Add admin</button></div></form></section>';
    const rows = team.map(t => {
        const manage = canManageTarget(user, t);
        const me = t.username.toLowerCase() === user.username.toLowerCase();
        const meta = [t.createdBy && t.createdBy !== 'secret' ? 'Added by ' + t.createdBy : (t.createdBy === 'secret' ? 'From secret' : ''), t.lastLogin ? 'Last sign-in ' + t.lastLogin.slice(0, 16).replace('T', ' ') + ' UTC' : 'Never signed in'].filter(Boolean).join(' \u00b7 ');
        const head = '<div class="team-who"><span class="avatar sm">' + escapeHtml(t.username.slice(0, 1).toUpperCase()) + '</span><div><b>' + escapeHtml(t.username) + (me ? ' <em>(you)</em>' : '') + '</b><small>' + escapeHtml(meta) + '</small></div>' + rolePill(t) + '</div>';
        if (t.owner || !manage) {
            return '<li class="team-row">' + head + permChecks('perm_view', t.permissions, { lockAll: true }) +
                '<p class="hint">' + (t.owner ? 'The owner always has every permission.' : me ? 'You can\u2019t change your own permissions.' : 'Only the owner can change Team admins.') + '</p></li>';
        }
        return '<li class="team-row">' + head +
            '<form method="POST" action="' + ADMIN_PATH + '/users/update"><input type="hidden" name="username" value="' + escapeHtml(t.username) + '">' + permChecks('perm', t.permissions, { canGrantUsers }) +
            '<div class="actions-row"><button class="btn sm" type="submit">Save permissions</button></div></form>' +
            '<div class="row-tools">' +
            '<form method="POST" action="' + ADMIN_PATH + '/users/reset" class="inline"><input type="hidden" name="username" value="' + escapeHtml(t.username) + '"><input type="text" name="password" placeholder="New password" minlength="' + ADMIN_PW_MIN + '" maxlength="' + ADMIN_PW_MAX + '" required autocomplete="new-password" aria-label="New password for ' + escapeHtml(t.username) + '"><button class="btn quiet sm" type="submit">Reset password</button></form>' +
            '<form method="POST" action="' + ADMIN_PATH + '/users/remove" class="inline" data-confirm="Remove ' + escapeHtml(t.username) + '? They will be signed out right away."><input type="hidden" name="username" value="' + escapeHtml(t.username) + '"><button class="btn danger sm" type="submit">Remove</button></form>' +
            '</div></li>';
    }).join('');
    const list = '<section class="card span" id="team-list"><div class="card-head"><div><div class="card-kicker">TEAM</div><h2>Admins</h2><p>' + team.length + ' active ' + (team.length === 1 ? 'account' : 'accounts') + '. Changes sign that admin out of other sessions.</p></div></div>' +
        '<ul class="team">' + rows + '</ul></section>';
    return add + list;
}

const ADMIN_TEAM_JS = String.raw`
(function(){
  document.querySelectorAll('[data-genpw]').forEach(function(b){
    b.addEventListener('click', function(){
      var input = document.getElementById(b.getAttribute('data-genpw')); if (!input) return;
      var abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_!';
      var bytes = new Uint32Array(16); crypto.getRandomValues(bytes);
      var out = ''; for (var i = 0; i < bytes.length; i++) out += abc[bytes[i] % abc.length];
      input.value = out; input.focus(); input.select();
      b.textContent = 'Copy it now'; setTimeout(function(){ b.textContent = 'Generate'; }, 2400);
    });
  });
  document.querySelectorAll('form[data-confirm]').forEach(function(f){
    f.addEventListener('submit', function(e){ if (!confirm(f.getAttribute('data-confirm'))) e.preventDefault(); });
  });
})();
`;
