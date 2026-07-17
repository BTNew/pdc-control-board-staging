// PDC Control Board — staging-only individual account self-registration.
//
// This file must NEVER be loaded by the production entry point
// (index.html). It is only referenced from staging.html. Production's
// test_microsoft_auth.js explicitly asserts pdc-auth.js contains no
// `.signUp(` call; this separate, optional module is where that
// capability lives instead, so production never gains public
// registration by way of a shared-file change.
//
// Depends on pdc-auth.js already having run (window.PDC_AUTH_SHARED) --
// loaded after pdc-auth.js in staging.html's script order.
(() => {
  'use strict';

  const el = id => document.getElementById(id);

  function shared() {
    if (!window.PDC_AUTH_SHARED) {
      throw new Error('pdc-auth-registration.js requires pdc-auth.js to load first');
    }
    return window.PDC_AUTH_SHARED;
  }

  async function signUp(event) {
    event?.preventDefault();
    const { getClient, authConfig, safeRedirectTo, validatePassword, showFormError, showFormSuccess, applySession } = shared();
    showFormError('pdc-signup-error', '');
    showFormSuccess('pdc-signup-success', '');

    const fullName = String(el('pdc-signup-full-name')?.value || '').trim();
    const email = String(el('pdc-signup-email')?.value || '').trim().toLowerCase();
    const password = String(el('pdc-signup-password')?.value || '');
    const confirmPassword = String(el('pdc-signup-confirm-password')?.value || '');

    if (!fullName) { showFormError('pdc-signup-error', 'Enter your full name.'); return; }
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { showFormError('pdc-signup-error', 'Enter a valid work email address.'); return; }
    if (!validatePassword(password)) { showFormError('pdc-signup-error', 'Password must be at least 12 characters with upper and lower-case letters, a number and a symbol.'); return; }
    if (password !== confirmPassword) { showFormError('pdc-signup-error', 'The two passwords do not match.'); return; }

    const button = el('pdc-signup-submit');
    if (button) button.disabled = true;
    const config = authConfig();
    const { data, error } = await getClient().auth.signUp({
      email, password,
      options: {
        data: { full_name: fullName },
        emailRedirectTo: safeRedirectTo(config.redirectTo),
      },
    });
    if (button) button.disabled = false;

    if (error) {
      showFormError('pdc-signup-error', error.message || 'Could not create the account. Try again.');
      return;
    }
    if (data?.user && !data.session) {
      // Email confirmation required (the normal, expected path) -- no
      // session yet until the user clicks the confirmation link. The
      // database trigger handle_new_pdc_auth_user() has already created
      // a pending/role=NULL/inactive pdc_user_roles row for this user by
      // this point (see migration 018) -- nothing further needed here.
      showFormSuccess('pdc-signup-success', 'Account created. Check your email and click the confirmation link, then sign in.');
      el('pdc-signup-full-name').value = '';
      el('pdc-signup-email').value = '';
      el('pdc-signup-password').value = '';
      el('pdc-signup-confirm-password').value = '';
      return;
    }
    if (data?.session) {
      // Some Supabase Auth configurations auto-confirm; in that case a
      // session is returned immediately -- fall through to the normal
      // session flow, which will correctly show "Awaiting approval"
      // since the new account row is pending/role=NULL either way.
      await applySession(data.session);
    }
  }

  function showCreateAccountForm() {
    // setMessage is not exposed (it is pdc-auth.js's own concern); the
    // registration module reuses the same DOM elements pdc-auth.js
    // already wired hidden-state for, so all it needs to do is trigger a
    // mode switch pdc-auth.js already knows how to render. Simplest safe
    // approach without duplicating setMessage: directly toggle the
    // relevant hidden attributes here, matching pdc-auth.js's own logic
    // for the 'create-account' mode.
    const passwordForm = el('pdc-password-form');
    const createAccountForm = el('pdc-create-account-form');
    const forgotPasswordForm = el('pdc-forgot-password-form');
    const titleNode = el('pdc-auth-title');
    const detailNode = el('pdc-auth-detail');
    if (passwordForm) passwordForm.hidden = true;
    if (forgotPasswordForm) forgotPasswordForm.hidden = true;
    if (createAccountForm) createAccountForm.hidden = false;
    if (titleNode) titleNode.textContent = 'Create your PDC account';
    if (detailNode) detailNode.textContent = 'Enter your details below. An administrator must approve your account before you can access any data.';
    document.body.dataset.authState = 'create-account';
  }

  function backToSignIn() {
    const { showSignInForm } = shared();
    const createAccountForm = el('pdc-create-account-form');
    if (createAccountForm) createAccountForm.hidden = true;
    showSignInForm();
  }

  function wire() {
    el('pdc-create-account-form')?.addEventListener('submit', signUp);
    el('pdc-show-create-account')?.addEventListener('click', showCreateAccountForm);
    el('pdc-signup-back-to-login')?.addEventListener('click', backToSignIn);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire, { once: true });
  else wire();

  window.PDC_AUTH_REGISTRATION_TEST = Object.freeze({ signUp });
})();
