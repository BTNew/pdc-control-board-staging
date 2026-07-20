(() => {
  'use strict';

  const state = {
    client: null,
    session: null,
    user: null,
    role: null,
    initialized: false,
    ownRoleChannel: null,
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
    const createAccountForm = el('pdc-create-account-form');
    const forgotPasswordForm = el('pdc-forgot-password-form');
    const deniedSignOut = el('pdc-auth-denied-signout');
    const pendingNotice = el('pdc-auth-pending-notice');
    const disabledNotice = el('pdc-auth-disabled-notice');
    const rejectedNotice = el('pdc-auth-rejected-notice');
    if (titleNode) titleNode.textContent = title;
    if (detailNode) detailNode.textContent = detail;
    const useMicrosoft = authConfig().mode === 'microsoft';
    if (loginButton) loginButton.hidden = mode !== 'signed-out' || !useMicrosoft;
    if (passwordForm) passwordForm.hidden = mode !== 'signed-out' || useMicrosoft;
    if (newPasswordForm) newPasswordForm.hidden = mode !== 'password-setup';
    if (createAccountForm) createAccountForm.hidden = mode !== 'create-account';
    if (forgotPasswordForm) forgotPasswordForm.hidden = mode !== 'forgot-password';
    if (deniedSignOut) deniedSignOut.hidden = mode !== 'denied';
    if (pendingNotice) pendingNotice.hidden = mode !== 'pending';
    if (disabledNotice) disabledNotice.hidden = mode !== 'account-disabled';
    if (rejectedNotice) rejectedNotice.hidden = mode !== 'rejected';
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

  // ---------------------------------------------------------------------
  // Own-row realtime lockout (independent-review remediation, finding #5 /
  // critical blocker #5).
  //
  // Previously this module only re-checked the signed-in user's role/status
  // on initial load and on Supabase Auth state changes (token refresh,
  // sign-in, sign-out) -- never on a live database change to their own
  // pdc_user_roles row. RLS correctly blocked new reads/writes the moment
  // an account was disabled, but an already-open browser tab could keep
  // showing previously-loaded operational data and an unlocked application
  // shell indefinitely, until the user happened to reload or sign out.
  //
  // Every signed-in browser now subscribes to postgres_changes on its own
  // pdc_user_roles row (filtered server-side by email, so a browser never
  // receives another user's row). On any change, it re-verifies the
  // account's live account_status/role and, if no longer approved,
  // immediately locks the shell, clears in-memory/operational state via a
  // 'pdc-auth-locked' event the rest of the app listens for, and
  // unsubscribes every operational realtime channel. A role change between
  // viewer/controller/administrator while still approved updates the
  // visible label and re-fires 'pdc-auth-ready' without requiring a reload.
  // ---------------------------------------------------------------------
  function unsubscribeOwnRoleChannel() {
    if (state.ownRoleChannel && state.client && typeof state.client.removeChannel === 'function') {
      try {
        state.client.removeChannel(state.ownRoleChannel);
      } catch (_err) {
        // best-effort; the channel may already be closed
      }
    }
    state.ownRoleChannel = null;
  }

  function subscribeOwnRoleChannel(email) {
    unsubscribeOwnRoleChannel();
    if (!state.client || typeof state.client.channel !== 'function' || !email) return;
    const channel = state.client
      .channel(`pdc_user_roles_own_row:${email}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'pdc_user_roles', filter: `email=eq.${email}` },
        () => {
          handleOwnRoleRowChanged();
        }
      )
      .subscribe();
    state.ownRoleChannel = channel;
  }

  async function handleOwnRoleRowChanged() {
    if (!state.session) return;
    const { role, error } = await loadApprovedRole(state.session);
    if (error || !role || role.account_status !== 'approved' || !approvedRole(role, state.session.user?.email)) {
      // No longer approved (disabled, rejected, reverted to pending, or the
      // row vanished). Lock immediately -- do not wait for the user to
      // reload or sign out, and do not leave previously-rendered
      // operational data visible in an inert-but-still-DOM-present shell.
      window.dispatchEvent(new CustomEvent('pdc-auth-locked', { detail: { reason: role ? role.account_status : 'not_found' } }));
      unsubscribeOwnRoleChannel();
      state.role = null;
      delete window.PDC_AUTH_CONTEXT;
      delete window.__pdcCachedAccessToken;
      lockApplication();
      const statusMessages = {
        pending: ['Awaiting approval', 'Your account has been created and is awaiting administrator approval.', 'pending'],
        disabled: ['Access disabled', 'Your account access has been disabled. Contact an administrator if you believe this is an error.', 'account-disabled'],
        rejected: ['Registration not approved', 'Your registration was not approved. Contact an administrator for details.', 'rejected'],
      };
      const [title, body, cls] = statusMessages[role?.account_status] || ['Access not approved', 'Your access to the PDC Control Board is no longer approved.', 'denied'];
      setMessage(title, body, cls);
      return;
    }
    // Still approved -- if the role itself changed (e.g. viewer promoted to
    // controller), refresh the visible permissions live without requiring
    // a page reload.
    if (state.role && state.role.role !== role.role) {
      state.role = role;
      window.PDC_AUTH_CONTEXT = Object.freeze({
        ...window.PDC_AUTH_CONTEXT,
        role: role.role,
      });
      const userLabel = el('pdc-auth-user');
      if (userLabel) userLabel.textContent = `${window.PDC_AUTH_CONTEXT.displayName} · ${role.role}`;
      window.dispatchEvent(new CustomEvent('pdc-auth-ready', { detail: window.PDC_AUTH_CONTEXT }));
    }
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
    // Cached for synchronous callers (workshop-data-service.js via
    // getPdcSupabaseAccessToken() in app.js) that need the current access
    // token without an async round-trip. Cleared on sign-out / session
    // loss in applySession() below, and refreshed on every auth state
    // change (including silent token refresh), so it never goes stale for
    // more than one event loop tick.
    window.__pdcCachedAccessToken = session.access_token || null;

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
    subscribeOwnRoleChannel(window.PDC_AUTH_CONTEXT.email);
  }

  async function loadApprovedRole(session) {
    const email = String(session?.user?.email || '').trim().toLowerCase();
    if (!email) return { role: null, error: new Error('The signed-in account did not return an email address.') };
    const { data, error } = await state.client
      .from('pdc_user_roles')
      .select('email,role,active,account_status')
      .eq('email', email)
      .maybeSingle();
    return { role: data, error };
  }

  async function applySession(session) {
    lockApplication();
    // Clear every operational-data surface before validating a replacement
    // session. This also covers ordinary sign-out/session-expiry, not only a
    // realtime role lockout, so a subsequent login cannot briefly inherit
    // rendered advice from the previous account.
    try {
      window.dispatchEvent?.(new CustomEvent('pdc-auth-locked', { detail: { reason: session ? 'session-revalidate' : 'session-ended' } }));
    } catch (_err) { /* best-effort client-data teardown */ }
    unsubscribeOwnRoleChannel();
    // Stage 2A: stop the shared workshop reference-data realtime
    // subscriptions and periodic reconciliation timer on every session
    // teardown path (sign-out, lockout, session expiry) -- this is the
    // single chokepoint all of those already route through, so it
    // never polls or holds open channels with a signed-out session.
    // Only stop on teardown (session === null), never on a real sign-in.
    if (!session && typeof window.stopWorkshopReferenceDataReconciliationTimer === 'function') {
      window.stopWorkshopReferenceDataReconciliationTimer();
    }
    state.session = session || null;
    state.user = session?.user || null;
    state.role = null;
    delete window.PDC_AUTH_CONTEXT;
    delete window.__pdcCachedAccessToken;

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
    if (error || !role) {
      setMessage('Access not approved', `The account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
      return;
    }
    if (role.account_status === 'pending') {
      setMessage('Awaiting approval', 'Your account has been created and is awaiting administrator approval.', 'pending');
      return;
    }
    if (role.account_status === 'disabled') {
      setMessage('Access disabled', 'Your account access has been disabled. Contact an administrator if you believe this is an error.', 'account-disabled');
      return;
    }
    if (role.account_status === 'rejected') {
      setMessage('Registration not approved', 'Your registration was not approved. Contact an administrator for details.', 'rejected');
      return;
    }
    if (!approvedRole(role, session.user.email)) {
      setMessage('Access not approved', `The account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
      return;
    }
    unlockApplication(session, role);
    // Fire-and-forget: records the last successful sign-in timestamp for
    // the administrator user-management screen. Never blocks unlocking
    // the application on this succeeding.
    state.client.rpc('record_pdc_login', {}).then(() => {}, () => {});
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

  function validatePassword(password) {
    return password.length >= 12 && /[a-z]/.test(password) && /[A-Z]/.test(password) && /\d/.test(password) && /[^A-Za-z0-9]/.test(password);
  }

  function showFormError(id, message) {
    const node = el(id);
    if (!node) return;
    node.textContent = message;
    node.hidden = !message;
  }

  function showFormSuccess(id, message) {
    const node = el(id);
    if (!node) return;
    node.textContent = message;
    node.hidden = !message;
  }

  async function forgotPassword(event) {
    event?.preventDefault();
    showFormError('pdc-forgot-error', '');
    showFormSuccess('pdc-forgot-success', '');
    const email = String(el('pdc-forgot-email')?.value || '').trim().toLowerCase();
    if (!email) { showFormError('pdc-forgot-error', 'Enter your work email address.'); return; }

    const button = el('pdc-forgot-submit');
    if (button) button.disabled = true;
    const config = authConfig();
    const { error } = await state.client.auth.resetPasswordForEmail(email, {
      redirectTo: safeRedirectTo(config.redirectTo),
    });
    if (button) button.disabled = false;

    // Deliberately show the same success message whether or not the
    // email exists, to avoid leaking which addresses are registered.
    if (error && error.status && error.status >= 500) {
      showFormError('pdc-forgot-error', 'Could not send the reset email right now. Try again shortly.');
      return;
    }
    showFormSuccess('pdc-forgot-success', 'If that email is registered, a password reset link has been sent.');
    el('pdc-forgot-email').value = '';
  }

  function showCreateAccountForm() {
    setMessage('Create your PDC account', 'Enter your details below. An administrator must approve your account before you can access any data.', 'create-account');
  }

  function showForgotPasswordForm() {
    setMessage('Reset your password', 'Enter your work email and we will send you a password reset link.', 'forgot-password');
  }

  function showSignInForm() {
    const config = authConfig();
    setMessage(config.mode === 'microsoft' ? 'Microsoft sign-in required' : 'PDC staff sign-in', config.mode === 'microsoft' ? 'Use your approved work Microsoft account to open the PDC Control Board.' : 'Use your individually assigned PDC email and password.', 'signed-out');
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
    el('pdc-forgot-password-form')?.addEventListener('submit', forgotPassword);
    el('pdc-show-create-account')?.addEventListener('click', showCreateAccountForm);
    el('pdc-show-forgot-password')?.addEventListener('click', showForgotPasswordForm);
    el('pdc-signup-back-to-login')?.addEventListener('click', showSignInForm);
    el('pdc-forgot-back-to-login')?.addEventListener('click', showSignInForm);
    el('pdc-pending-signout')?.addEventListener('click', signOut);
    el('pdc-disabled-signout')?.addEventListener('click', signOut);
    el('pdc-rejected-signout')?.addEventListener('click', signOut);

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

  // Exposed only for the OPTIONAL, staging-only self-registration module
  // (pdc-auth-registration.js). This object exists on every deployment
  // (including production) but is inert unless that separate script is
  // also loaded, which it is not on the production entry point. Kept
  // deliberately narrow: state.client so registration can call
  // supabase-js auth methods, applySession/authConfig/safeRedirectTo so
  // the registration module can render the same locked-shell state
  // machine consistently, and validatePassword/showFormError/
  // showFormSuccess so both modules render identical password-strength
  // and error/success UI.
  window.PDC_AUTH_SHARED = Object.freeze({
    getClient: () => state.client,
    applySession,
    authConfig,
    safeRedirectTo,
    validatePassword,
    showFormError,
    showFormSuccess,
    showSignInForm,
  });
})();
