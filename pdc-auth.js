(() => {
  'use strict';

  const state = {
    client: null,
    session: null,
    user: null,
    role: null,
    initialized: false,
    passwordSetupRequired: /(?:^|[?#&])type=(?:invite|recovery)(?:[&#]|$)/.test(`${window.location.search}${window.location.hash}`),
  };

  const el = id => document.getElementById(id);

  function authConfig() {
    const config = window.PDC_SUPABASE_CONFIG || {};
    return {
      url: String(config.url || '').trim().replace(/\/$/, ''),
      publishableKey: String(config.publishableKey || '').trim(),
      mode: String(config.auth?.mode || 'password').trim().toLowerCase(),
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
    const passwordForm = el('pdc-password-form');
    const newPasswordForm = el('pdc-new-password-form');
    const deniedSignOut = el('pdc-auth-denied-signout');
    if (titleNode) titleNode.textContent = title;
    if (detailNode) detailNode.textContent = detail;
    const useMicrosoft = authConfig().mode === 'microsoft';
    if (loginButton) loginButton.hidden = mode !== 'signed-out' || !useMicrosoft;
    if (passwordForm) passwordForm.hidden = mode !== 'signed-out' || useMicrosoft;
    if (newPasswordForm) newPasswordForm.hidden = mode !== 'password-setup';
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
    if (!email) return { role: null, error: new Error('The signed-in account did not return an email address.') };
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
      const config = authConfig();
      setMessage(
        config.mode === 'microsoft' ? 'Microsoft sign-in required' : 'PDC staff sign-in',
        config.mode === 'microsoft' ? 'Use your approved work Microsoft account to open the PDC Control Board.' : 'Use your individually assigned PDC email and password.',
        'signed-out'
      );
      return;
    }

    if (state.passwordSetupRequired) {
      setMessage('Create your PDC password', 'Use at least 12 characters with upper and lower-case letters, a number and a symbol.', 'password-setup');
      return;
    }

    setMessage('Checking PDC access…', 'Your identity is signed in. Checking the approved staff list.', 'checking');
    const { role, error } = await loadApprovedRole(session);
    if (error || !approvedRole(role, session.user.email)) {
      setMessage('Access not approved', `The account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
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

  async function signInWithPassword(event) {
    event?.preventDefault();
    const email = String(el('pdc-login-email')?.value || '').trim().toLowerCase();
    const password = String(el('pdc-login-password')?.value || '');
    const button = el('pdc-password-login');
    if (!email || !password) {
      setMessage('PDC staff sign-in', 'Enter your assigned email address and password.', 'signed-out');
      return;
    }
    if (button) button.disabled = true;
    setMessage('Signing in…', 'Checking your staff account and PDC access.', 'checking');
    const { data, error } = await state.client.auth.signInWithPassword({ email, password });
    if (button) button.disabled = false;
    if (error || !data?.session) {
      if (el('pdc-login-password')) el('pdc-login-password').value = '';
      setMessage('Sign-in unsuccessful', 'The email or password was not accepted. Check your details or contact the PDC administrator.', 'signed-out');
      return;
    }
    await applySession(data.session);
  }

  async function saveNewPassword(event) {
    event?.preventDefault();
    const password = String(el('pdc-new-password')?.value || '');
    const confirmation = String(el('pdc-confirm-password')?.value || '');
    const strongEnough = password.length >= 12 && /[a-z]/.test(password) && /[A-Z]/.test(password) && /\d/.test(password) && /[^A-Za-z0-9]/.test(password);
    if (!strongEnough || password !== confirmation) {
      setMessage('Create your PDC password', password !== confirmation ? 'The two passwords do not match.' : 'Use at least 12 characters with upper and lower-case letters, a number and a symbol.', 'password-setup');
      return;
    }
    const button = el('pdc-save-password');
    if (button) button.disabled = true;
    const { data, error } = await state.client.auth.updateUser({ password });
    if (button) button.disabled = false;
    if (error || !data?.user) {
      setMessage('Password could not be saved', error?.message || 'Request another invitation and try again.', 'password-setup');
      return;
    }
    if (el('pdc-new-password')) el('pdc-new-password').value = '';
    if (el('pdc-confirm-password')) el('pdc-confirm-password').value = '';
    state.passwordSetupRequired = false;
    window.history.replaceState({}, document.title, window.location.pathname);
    await applySession(state.session);
  }

  async function signOut() {
    if (state.client) await state.client.auth.signOut();
    await applySession(null);
  }

  async function initialize() {
    lockApplication();
    const config = authConfig();
    if (!window.supabase?.createClient || !config.url || !config.publishableKey || config.publishableKey.includes('PASTE_')) {
      setMessage('Login setup required', 'The browser authentication configuration has not been installed for this deployment.', 'setup');
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
    el('pdc-password-form')?.addEventListener('submit', signInWithPassword);
    el('pdc-new-password-form')?.addEventListener('submit', saveNewPassword);
    el('pdc-auth-signout')?.addEventListener('click', signOut);
    el('pdc-auth-denied-signout')?.addEventListener('click', signOut);

    const { data, error } = await state.client.auth.getSession();
    if (error) {
      setMessage('Session error', error.message || 'The saved session could not be checked.', 'signed-out');
      return;
    }
    await applySession(data.session);
    state.client.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') state.passwordSetupRequired = true;
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
