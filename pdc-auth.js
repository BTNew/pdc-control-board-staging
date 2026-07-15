(() => {
  'use strict';

  const state = {
    client: null,
    session: null,
    user: null,
    role: null,
    initialized: false,
  };

  const el = id => document.getElementById(id);

  function authConfig() {
    const config = window.PDC_SUPABASE_CONFIG || {};
    return {
      url: String(config.url || '').trim().replace(/\/$/, ''),
      publishableKey: String(config.publishableKey || '').trim(),
      provider: String(config.auth?.provider || 'azure').trim() || 'azure',
      redirectTo: String(config.auth?.redirectTo || `${window.location.origin}${window.location.pathname}`).trim(),
    };
  }

  function safeRedirectTo(candidate) {
    try {
      const redirect = new URL(candidate, window.location.origin);
      if (redirect.origin !== window.location.origin) return `${window.location.origin}${window.location.pathname}`;
      return redirect.href;
    } catch (_error) {
      return `${window.location.origin}${window.location.pathname}`;
    }
  }

  function approvedRole(roleRow, userEmail = '') {
    const email = String(userEmail || '').trim().toLowerCase();
    const roleEmail = String(roleRow?.email || '').trim().toLowerCase();
    const allowedRoles = new Set(['viewer', 'operator', 'importer', 'administrator']);
    return Boolean(roleRow?.active && email && roleEmail === email && allowedRoles.has(String(roleRow?.role || '')));
  }

  function setMessage(title, detail, mode = 'signed-out') {
    const titleNode = el('pdc-auth-title');
    const detailNode = el('pdc-auth-detail');
    const loginButton = el('pdc-microsoft-login');
    const deniedSignOut = el('pdc-auth-denied-signout');
    if (titleNode) titleNode.textContent = title;
    if (detailNode) detailNode.textContent = detail;
    if (loginButton) loginButton.hidden = mode !== 'signed-out';
    if (deniedSignOut) deniedSignOut.hidden = mode !== 'denied';
    document.body.dataset.authState = mode;
  }

  function lockApplication() {
    const shell = el('app-shell');
    if (!shell) return;
    shell.setAttribute('inert', '');
    shell.setAttribute('aria-hidden', 'true');
    document.body.classList.add('auth-pending');
    document.body.classList.remove('auth-approved');
  }

  function unlockApplication(session, roleRow) {
    state.session = session;
    state.user = session.user;
    state.role = roleRow;
    window.PDC_AUTH_CONTEXT = Object.freeze({
      userId: session.user.id,
      email: String(session.user.email || '').toLowerCase(),
      displayName: String(session.user.user_metadata?.full_name || session.user.user_metadata?.name || session.user.email || ''),
      role: roleRow.role,
    });

    const shell = el('app-shell');
    if (shell) {
      shell.removeAttribute('inert');
      shell.removeAttribute('aria-hidden');
    }
    const userLabel = el('pdc-auth-user');
    if (userLabel) {
      userLabel.textContent = `${window.PDC_AUTH_CONTEXT.displayName} · ${roleRow.role}`;
      userLabel.hidden = false;
    }
    const signOut = el('pdc-auth-signout');
    if (signOut) signOut.hidden = false;

    document.body.classList.remove('auth-pending');
    document.body.classList.add('auth-approved');
    document.body.dataset.authState = 'approved';
    window.dispatchEvent(new CustomEvent('pdc-auth-ready', { detail: window.PDC_AUTH_CONTEXT }));
  }

  async function loadApprovedRole(session) {
    const email = String(session?.user?.email || '').trim().toLowerCase();
    if (!email) return { role: null, error: new Error('Microsoft did not return a verified email address.') };
    const { data, error } = await state.client
      .from('pdc_user_roles')
      .select('email,role,active')
      .eq('email', email)
      .eq('active', true)
      .maybeSingle();
    return { role: data, error };
  }

  async function applySession(session) {
    lockApplication();
    state.session = session || null;
    state.user = session?.user || null;
    state.role = null;
    delete window.PDC_AUTH_CONTEXT;

    const userLabel = el('pdc-auth-user');
    const signOut = el('pdc-auth-signout');
    if (userLabel) userLabel.hidden = true;
    if (signOut) signOut.hidden = true;

    if (!session) {
      setMessage('Microsoft sign-in required', 'Use your approved work Microsoft account to open the PDC Control Board.', 'signed-out');
      return;
    }

    setMessage('Checking PDC access…', 'Your Microsoft identity is signed in. Checking the approved staff list.', 'checking');
    const { role, error } = await loadApprovedRole(session);
    if (error || !approvedRole(role, session.user.email)) {
      setMessage('Access not approved', `The Microsoft account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
      return;
    }
    unlockApplication(session, role);
  }

  async function signInWithMicrosoft() {
    const button = el('pdc-microsoft-login');
    if (button) button.disabled = true;
    setMessage('Opening Microsoft sign-in…', 'You will return here after Microsoft verifies your account.', 'checking');
    const config = authConfig();
    const { error } = await state.client.auth.signInWithOAuth({
      provider: config.provider,
      options: {
        scopes: 'email',
        redirectTo: safeRedirectTo(config.redirectTo),
      },
    });
    if (error) {
      setMessage('Microsoft sign-in unavailable', error.message || 'The Microsoft provider is not configured yet.', 'signed-out');
      if (button) button.disabled = false;
    }
  }

  async function signOut() {
    if (state.client) await state.client.auth.signOut();
    await applySession(null);
  }

  async function initialize() {
    lockApplication();
    const config = authConfig();
    if (!window.supabase?.createClient || !config.url || !config.publishableKey || config.publishableKey.includes('PASTE_')) {
      setMessage('Microsoft login setup required', 'The browser authentication configuration has not been installed for this deployment.', 'setup');
      return;
    }

    state.client = window.supabase.createClient(config.url, config.publishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    });
    window.PDC_SUPABASE = state.client;

    el('pdc-microsoft-login')?.addEventListener('click', signInWithMicrosoft);
    el('pdc-auth-signout')?.addEventListener('click', signOut);
    el('pdc-auth-denied-signout')?.addEventListener('click', signOut);

    const { data, error } = await state.client.auth.getSession();
    if (error) {
      setMessage('Microsoft session error', error.message || 'The saved session could not be checked.', 'signed-out');
      return;
    }
    await applySession(data.session);
    state.client.auth.onAuthStateChange((_event, session) => {
      window.setTimeout(() => applySession(session), 0);
    });
    state.initialized = true;
  }

  window.PDC_AUTH_READY = new Promise(resolve => {
    const start = async () => {
      await initialize();
      resolve(state);
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
    else start();
  });

  window.PDC_AUTH_TEST = Object.freeze({ approvedRole, safeRedirectTo });
})();
