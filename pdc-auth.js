(() => {
  'use strict';

  const state = {
    client: null,
    session: null,
    validatingSession: null,
    user: null,
    role: null,
    initialized: false,
    ownRoleChannel: null,
    ownRoleSubscriptionAttempt: null,
    passwordSetupUserId: null,
    // Monotonic ownership tokens for asynchronous session and role checks.
    // A completion may publish authority only if it still owns both tokens.
    authGeneration: 0,
    roleLookupGeneration: 0,
    roleLookupInFlight: 0,
    providerGeneration: 0,
    pendingProviderSessionGeneration: null,
    sessionAcceptanceBlocked: false,
    explicitSessionUserId: null,
    ownRoleChannelGeneration: 0,
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

  function authPrincipalKey(session) {
    const id = String(session?.user?.id || '').trim();
    const email = String(session?.user?.email || '').trim().toLowerCase();
    return id && email ? `${id}\n${email}` : '';
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
    state.ownRoleChannelGeneration += 1;
    state.ownRoleSubscriptionAttempt?.finish(false);
    state.ownRoleSubscriptionAttempt = null;
    if (state.ownRoleChannel && state.client && typeof state.client.removeChannel === 'function') {
      try {
        state.client.removeChannel(state.ownRoleChannel);
      } catch (_err) {
        // best-effort; the channel may already be closed
      }
    }
    state.ownRoleChannel = null;
  }

  function lockOwnRoleAuthority(reason, role = null) {
    // Revoke synchronously before notifying listeners. A lock event must not
    // expose the prior context, token, session, role, or monitor callback.
    state.authGeneration += 1;
    state.roleLookupGeneration += 1;
    unsubscribeOwnRoleChannel();
    state.session = null;
    state.validatingSession = null;
    state.passwordSetupUserId = null;
    state.user = null;
    state.role = null;
    delete window.PDC_AUTH_CONTEXT;
    delete window.__pdcCachedAccessToken;
    lockApplication();
    window.dispatchEvent(new CustomEvent('pdc-auth-locked', { detail: { reason } }));
    const statusMessages = {
      pending: ['Awaiting approval', 'Your account has been created and is awaiting administrator approval.', 'pending'],
      disabled: ['Access disabled', 'Your account access has been disabled. Contact an administrator if you believe this is an error.', 'account-disabled'],
      rejected: ['Registration not approved', 'Your registration was not approved. Contact an administrator for details.', 'rejected'],
    };
    const [title, body, cls] = statusMessages[role?.account_status] || ['Access not approved', 'Your access to the PDC Control Board could not be revalidated.', 'denied'];
    setMessage(title, body, cls);
  }

  function subscribeOwnRoleChannel(email) {
    unsubscribeOwnRoleChannel();
    if (!state.client || typeof state.client.channel !== 'function' || !email) return Promise.resolve(false);
    const channelGeneration = state.ownRoleChannelGeneration;
    return new Promise(resolve => {
      let settled = false;
      let timer = null;
      const finish = result => {
        if (settled) return;
        settled = true;
        if (timer !== null) window.clearTimeout(timer);
        if (state.ownRoleSubscriptionAttempt?.finish === finish) state.ownRoleSubscriptionAttempt = null;
        resolve(Boolean(result));
      };
      state.ownRoleSubscriptionAttempt = { finish };
      try {
        const channel = state.client
          .channel(`pdc_user_roles_own_row:${email}`)
          .on(
            'postgres_changes',
            { event: '*', schema: 'public', table: 'pdc_user_roles', filter: `email=eq.${email}` },
            () => {
              handleOwnRoleRowChanged().catch(() => lockOwnRoleAuthority('role_check_failed'));
            }
          );
        state.ownRoleChannel = channel;
        channel.subscribe(status => {
          if (channelGeneration !== state.ownRoleChannelGeneration || state.ownRoleChannel !== channel) {
            finish(false);
            return;
          }
          if (status === 'SUBSCRIBED') {
            finish(true);
            return;
          }
          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            finish(false);
            lockOwnRoleAuthority('role_monitor_unavailable');
          }
        });
        if (!settled) timer = window.setTimeout(() => {
          if (channelGeneration !== state.ownRoleChannelGeneration || state.ownRoleChannel !== channel) {
            finish(false);
            return;
          }
          finish(false);
          lockOwnRoleAuthority('role_monitor_unavailable');
        }, 10000);
      } catch (_err) {
        finish(false);
        lockOwnRoleAuthority('role_monitor_unavailable');
      }
    });
  }

  async function handleOwnRoleRowChanged() {
    const session = state.session || state.validatingSession;
    if (!session) return;
    const principalKey = authPrincipalKey(session);
    const authGeneration = state.authGeneration;
    const roleLookupGeneration = ++state.roleLookupGeneration;
    let role;
    let error;
    state.roleLookupInFlight += 1;
    try {
      ({ role, error } = await loadApprovedRole(session));
    } catch (caught) {
      error = caught;
    } finally {
      state.roleLookupInFlight = Math.max(0, state.roleLookupInFlight - 1);
    }
    if (
      authGeneration !== state.authGeneration
      || roleLookupGeneration !== state.roleLookupGeneration
      || !principalKey
      || ![state.session, state.validatingSession].some(current => authPrincipalKey(current) === principalKey)
    ) return;
    if (error || !role || role.account_status !== 'approved' || !approvedRole(role, session.user?.email)) {
      // No longer approved, or revalidation itself failed. Revoke before
      // notifying listeners and never retain authority without monitoring.
      lockOwnRoleAuthority(role ? role.account_status : (error ? 'role_check_failed' : 'not_found'), role);
      return;
    }
    // A newer live-row result may arrive while applySession() is revalidating
    // and has deliberately cleared state.role/context. In that case this
    // lookup owns the newest role generation and may unlock from its fresh
    // proof; the older applySession completion is generation-suppressed.
    if (!state.role) {
      await unlockApplication(session, role, authGeneration, roleLookupGeneration);
      return;
    }
    // Still approved -- if the role itself changed (e.g. viewer promoted to
    // controller), refresh the visible permissions live without requiring
    // a page reload.
    if (state.role.role !== role.role) {
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

  async function unlockApplication(session, roleRow, expectedAuthGeneration, expectedRoleLookupGeneration) {
    const monitored = await subscribeOwnRoleChannel(String(session.user.email || '').toLowerCase());
    if (
      !monitored
      || expectedAuthGeneration !== state.authGeneration
      || expectedRoleLookupGeneration !== state.roleLookupGeneration
      || (state.session !== session && state.validatingSession !== session)
    ) return false;
    state.session = session;
    state.validatingSession = null;
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
    return true;
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
    const authGeneration = ++state.authGeneration;
    // Any own-row lookup started under the previous session/role generation
    // is now obsolete, even when the replacement belongs to the same user.
    const roleLookupGeneration = ++state.roleLookupGeneration;
    lockApplication();
    unsubscribeOwnRoleChannel();
    // Revoke every local authority surface before synchronously notifying
    // listeners. The incoming session remains a local argument until after
    // the lock event, so listeners cannot observe unvalidated replacement
    // authority either.
    state.session = null;
    state.validatingSession = null;
    state.passwordSetupUserId = null;
    state.user = null;
    state.role = null;
    delete window.PDC_AUTH_CONTEXT;
    delete window.__pdcCachedAccessToken;
    try {
      window.dispatchEvent?.(new CustomEvent('pdc-auth-locked', { detail: { reason: session ? 'session-revalidate' : 'session-ended' } }));
    } catch (_err) { /* best-effort client-data teardown */ }
    // Stage 2A: stop the shared workshop reference-data realtime
    // subscriptions and periodic reconciliation timer on every session
    // teardown path (sign-out, lockout, session expiry).
    if (!session && typeof window.stopWorkshopReferenceDataReconciliationTimer === 'function') {
      window.stopWorkshopReferenceDataReconciliationTimer();
    }
    state.validatingSession = session || null;

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
      state.validatingSession = null;
      state.passwordSetupUserId = session.user?.id || null;
      setMessage('Create your PDC password', 'Use at least 12 characters with upper and lower-case letters, a number and a symbol.', 'password-setup');
      return;
    }

    setMessage('Checking PDC access…', 'Your identity is signed in. Checking the approved staff list.', 'checking');
    let role;
    let error;
    try {
      ({ role, error } = await loadApprovedRole(session));
    } catch (caught) {
      error = caught;
    }
    if (
      authGeneration !== state.authGeneration
      || roleLookupGeneration !== state.roleLookupGeneration
      || state.validatingSession !== session
    ) return;
    if (error || !role) {
      state.validatingSession = null;
      setMessage('Access not approved', `The account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
      return;
    }
    if (role.account_status === 'pending') {
      state.validatingSession = null;
      setMessage('Awaiting approval', 'Your account has been created and is awaiting administrator approval.', 'pending');
      return;
    }
    if (role.account_status === 'disabled') {
      state.validatingSession = null;
      setMessage('Access disabled', 'Your account access has been disabled. Contact an administrator if you believe this is an error.', 'account-disabled');
      return;
    }
    if (role.account_status === 'rejected') {
      state.validatingSession = null;
      setMessage('Registration not approved', 'Your registration was not approved. Contact an administrator for details.', 'rejected');
      return;
    }
    if (!approvedRole(role, session.user.email)) {
      state.validatingSession = null;
      setMessage('Access not approved', `The account ${session.user.email || 'you used'} is not on the PDC approved staff list.`, 'denied');
      return;
    }
    if (!await unlockApplication(session, role, authGeneration, roleLookupGeneration)) return;
    // Fire-and-forget: records the last successful sign-in timestamp for
    // the administrator user-management screen. Never blocks unlocking
    // the application on this succeeding.
    state.client.rpc('record_pdc_login', {}).then(() => {}, () => {});
  }

  function beginProviderSessionOperation() {
    state.sessionAcceptanceBlocked = false;
    state.explicitSessionUserId = null;
    const generation = ++state.providerGeneration;
    state.pendingProviderSessionGeneration = generation;
    return generation;
  }

  function completeProviderSessionOperation(generation, session = null) {
    if (generation !== state.providerGeneration || state.pendingProviderSessionGeneration !== generation) return false;
    state.pendingProviderSessionGeneration = null;
    if (session?.user?.id) state.explicitSessionUserId = session.user.id;
    return true;
  }

  function providerSessionOperationCurrent(generation) {
    return generation === state.providerGeneration && state.pendingProviderSessionGeneration === generation;
  }

  async function signInWithMicrosoft() {
    const providerGeneration = beginProviderSessionOperation();
    await applySession(null);
    if (!providerSessionOperationCurrent(providerGeneration)) return;
    const button = el('pdc-microsoft-login');
    if (button) button.disabled = true;
    setMessage('Opening Microsoft sign-in…', 'You will return here after Microsoft verifies your account.', 'checking');
    const config = authConfig();
    let error;
    try {
      ({ error } = await state.client.auth.signInWithOAuth({
        provider: config.provider,
        options: {
          scopes: 'email',
          redirectTo: safeRedirectTo(config.redirectTo),
        },
      }));
    } catch (caught) {
      error = caught;
    }
    if (!completeProviderSessionOperation(providerGeneration)) return;
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
    const providerGeneration = beginProviderSessionOperation();
    await applySession(null);
    if (!providerSessionOperationCurrent(providerGeneration)) return;
    if (button) button.disabled = true;
    setMessage('Signing in…', 'Checking your staff account and PDC access.', 'checking');
    let data;
    let error;
    try {
      ({ data, error } = await state.client.auth.signInWithPassword({ email, password }));
    } catch (caught) {
      error = caught;
    }
    if (!completeProviderSessionOperation(providerGeneration, data?.session)) return;
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
    const providerGeneration = beginProviderSessionOperation();
    const passwordSetupUserId = state.passwordSetupUserId;
    const button = el('pdc-save-password');
    if (button) button.disabled = true;
    let data;
    let error;
    try {
      ({ data, error } = await state.client.auth.updateUser({ password }));
    } catch (caught) {
      error = caught;
    }
    if (!providerSessionOperationCurrent(providerGeneration) || state.passwordSetupUserId !== passwordSetupUserId) return;
    if (button) button.disabled = false;
    if (error || !data?.user) {
      setMessage('Password could not be saved', error?.message || 'Request another invitation and try again.', 'password-setup');
      return;
    }
    let recoverySession;
    let recoveryError;
    try {
      const result = await state.client.auth.getSession();
      recoverySession = result?.data?.session || null;
      recoveryError = result?.error || null;
    } catch (caught) {
      recoveryError = caught;
    }
    if (!providerSessionOperationCurrent(providerGeneration) || state.passwordSetupUserId !== passwordSetupUserId) return;
    if (recoveryError || !recoverySession || recoverySession.user?.id !== passwordSetupUserId) {
      completeProviderSessionOperation(providerGeneration);
      state.passwordSetupRequired = false;
      state.passwordSetupUserId = null;
      await applySession(null);
      setMessage('Password saved; sign in again', 'Your password was updated, but this browser could not safely revalidate the recovery session. Sign in with your new password.', 'signed-out');
      return;
    }
    if (!completeProviderSessionOperation(providerGeneration, recoverySession)) return;
    if (el('pdc-new-password')) el('pdc-new-password').value = '';
    if (el('pdc-confirm-password')) el('pdc-confirm-password').value = '';
    state.passwordSetupRequired = false;
    state.passwordSetupUserId = null;
    window.history.replaceState({}, document.title, window.location.pathname);
    await applySession(recoverySession);
  }

  async function signOut() {
    // Local authority is revoked before any network wait. Provider sign-out
    // is best-effort transport cleanup and can never keep or resurrect the
    // unlocked shell when delayed or rejected.
    state.sessionAcceptanceBlocked = true;
    state.pendingProviderSessionGeneration = null;
    state.explicitSessionUserId = null;
    const providerGeneration = ++state.providerGeneration;
    const client = state.client;
    await applySession(null);
    if (client) {
      try {
        const { error } = await client.auth.signOut();
        if (error && providerGeneration === state.providerGeneration) {
          setMessage('Signed out locally', 'The remote sign-out request could not be confirmed. Close this browser or try again before signing in.', 'signed-out');
        }
      } catch (_err) {
        if (providerGeneration === state.providerGeneration) {
          setMessage('Signed out locally', 'The remote sign-out request could not be confirmed. Close this browser or try again before signing in.', 'signed-out');
        }
      }
    }
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

    // Register provider events before initial discovery so a newer sign-out,
    // refresh, or replacement session supersedes a delayed getSession().
    state.client.auth.onAuthStateChange((event, session) => {
      // Supabase may emit SIGNED_IN before an explicit password/signup
      // promise resolves. That request owns session publication; suppress
      // uncorrelated callbacks until its generation completes.
      if (session && state.pendingProviderSessionGeneration !== null) return;
      if (session && state.explicitSessionUserId && session.user?.id !== state.explicitSessionUserId) return;
      // Supabase silently rotates access tokens for a still-signed-in user.
      // The already-approved context remains continuously monitored by the
      // user's role-row channel, so tearing the whole app down and recreating
      // that channel here adds no authority proof and can strand a healthy tab
      // on the checking overlay if Realtime subscription is briefly delayed.
      // Any different user, absent context/monitor, or blocked session still
      // takes the full fail-closed applySession() path below.
      if (
        event === 'TOKEN_REFRESHED'
        && session
        && !state.sessionAcceptanceBlocked
        && state.session?.user?.id
        && state.session.user.id === session.user?.id
        && authPrincipalKey(state.session) === authPrincipalKey(session)
        && state.role
        && state.ownRoleChannel
        && window.PDC_AUTH_CONTEXT?.userId === session.user?.id
      ) {
        state.session = session;
        state.user = session.user;
        window.__pdcCachedAccessToken = session.access_token || null;
        // Keep the hourly provider refresh as a secondary role-authority
        // reconciliation even while the live role monitor remains subscribed.
        // Revalidation runs without tearing down a proven context; any denial,
        // lookup failure, or role change is still handled fail-closed.
        if (state.roleLookupInFlight === 0) {
          Promise.resolve()
            .then(() => handleOwnRoleRowChanged())
            .catch(() => lockOwnRoleAuthority('role_check_failed'));
        }
        return;
      }
      if (event === 'SIGNED_OUT') {
        state.sessionAcceptanceBlocked = true;
        state.pendingProviderSessionGeneration = null;
      }
      if (event === 'PASSWORD_RECOVERY') state.sessionAcceptanceBlocked = false;
      const providerGeneration = ++state.providerGeneration;
      window.setTimeout(() => {
        if (providerGeneration !== state.providerGeneration) return;
        if (session && state.sessionAcceptanceBlocked) {
          applySession(null);
          return;
        }
        if (event === 'PASSWORD_RECOVERY') state.passwordSetupRequired = true;
        applySession(session);
      }, 0);
    });
    const providerGeneration = ++state.providerGeneration;
    let data;
    let error;
    try {
      ({ data, error } = await state.client.auth.getSession());
    } catch (caught) {
      error = caught;
    }
    if (providerGeneration === state.providerGeneration) {
      if (error) {
        setMessage('Session error', error.message || 'The saved session could not be checked.', 'signed-out');
      } else {
        await applySession(data.session);
      }
    }
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
    beginProviderOperation: beginProviderSessionOperation,
    providerOperationCurrent: providerSessionOperationCurrent,
    completeProviderOperation: completeProviderSessionOperation,
    authConfig,
    safeRedirectTo,
    validatePassword,
    showFormError,
    showFormSuccess,
    showSignInForm,
  });
})();
