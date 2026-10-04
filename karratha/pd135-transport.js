(function (root) {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const PROJECT_URL = 'https://' + PROJECT + '.supabase.co';
  const PREFIX = 'k135_';
  const AUTH_KEY = 'karratha-pdc-auth-v1';
  const own = (object, key) => Object.prototype.hasOwnProperty.call(object || {}, key);
  const name = value => typeof value === 'string' && /^[a-z][a-z0-9_]{0,62}$/.test(value);
  function denied(message) {
    const error = new Error(message || 'This connection is not available for Department 135.');
    error.name = 'Department135ConnectionError';
    error.code = 'department135_connection_blocked';
    throw error;
  }
  function validatedMap(input) {
    if (!input || input.centre !== '135' || input.project_ref !== PROJECT || input.url !== PROJECT_URL) denied('Department 135 configuration is unavailable.');
    const result = { ready: input.ready === true, rpc: Object.create(null), tables: Object.create(null), realtime: Object.create(null), buckets: Object.create(null), context_rpc: input.context_rpc };
    for (const kind of ['rpc', 'tables']) {
      const targets = new Set();
      for (const [source, target] of Object.entries(input[kind] || {})) {
        if (!name(source) || !name(target) || !target.startsWith(PREFIX) || targets.has(target)) denied('Department 135 endpoint mapping is invalid.');
        targets.add(target); result[kind][source] = target;
      }
    }
    // A context check is the one existing dedicated Department 135 endpoint.
    if (result.context_rpc !== 'k135_get_native_engine_context') denied('Department 135 authority check is unavailable.');
    for (const [source, target] of Object.entries(input.realtime || {})) {
      if (!name(source) || !target || !name(target.table)
        || !(target.schema === 'public' && target.table.startsWith(PREFIX) || target.schema === 'karratha135_pdc' && target.table === source)) denied('Department 135 live updates are not configured.');
      result.realtime[source] = Object.freeze({ schema: target.schema, table: target.table });
    }
    for (const [source, target] of Object.entries(input.buckets || {})) {
      if (!/^[a-z][a-z0-9-]{0,62}$/.test(source) || typeof target !== 'string' || !/^(?:k135|karratha135)-[a-z0-9-]{1,48}$/.test(target)) denied('Department 135 photo storage is not configured.');
      result.buckets[source] = target;
    }
    return Object.freeze(result);
  }
  function create(options) {
    const map = validatedMap(options.map);
    const fetchNative = options.fetch;
    if (typeof fetchNative !== 'function') denied('Department 135 connection is unavailable.');
    const base = new URL(options.pageUrl);
    const directory = new URL('./', base);
    const assets = new Set(options.assets || []);
    const getEpoch = typeof options.getEpoch === 'function' ? options.getEpoch : () => 0;
    const bucketTargets = new Set(Object.values(map.buckets));
    const rpcTargets = new Set(Object.values(map.rpc));
    const tableTargets = new Set(Object.values(map.tables));
    function mapped(kind, key) {
      if (own(map[kind], key)) return map[kind][key];
      if (kind === 'rpc' && rpcTargets.has(key) || kind === 'tables' && tableTargets.has(key) || kind === 'buckets' && bucketTargets.has(key)) return key;
      return denied('This endpoint is not enabled for Department 135.');
    }
    function localAsset(url, method) {
      if (!['GET', 'HEAD'].includes(method) || url.origin !== directory.origin || !url.pathname.startsWith(directory.pathname)) denied();
      const relative = url.pathname.slice(directory.pathname.length);
      if (!assets.has(relative) || relative.split('/').some(part => !part || part === '..' || part === '.')) denied('This file is not part of the Department 135 board.');
      return url;
    }
    function route(raw, method = 'GET') {
      const url = new URL(raw, base);
      const verb = String(method || 'GET').toUpperCase();
      if (url.username || url.password || url.hash) denied();
      if (url.origin !== PROJECT_URL) return { url: localAsset(url, verb), kind: 'asset' };
      if (!map.ready) denied('Department 135 is waiting for its verified connection.');
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts[0] === 'auth' && parts[1] === 'v1') {
        const authPath = parts.slice(2).join('/');
        if (!['token', 'user', 'recover', 'verify', 'authorize', 'logout', 'settings'].includes(authPath)) denied('Use an existing approved account to sign in to Department 135.');
        if (authPath === 'logout' && url.searchParams.get('scope') !== 'local') denied('Department 135 signs out only its own browser session.');
        return { url, kind: 'auth' };
      }
      if (parts[0] === 'rest' && parts[1] === 'v1') {
        if (parts[2] === 'rpc' && parts.length === 4 && verb === 'POST') {
          const key = decodeURIComponent(parts[3]);
          if (!name(key)) denied();
          const target = key === map.context_rpc ? key : mapped('rpc', key);
          url.pathname = '/rest/v1/rpc/' + target;
          return { url, kind: 'rpc', source: key, target };
        }
        if (parts.length === 3 && ['GET', 'HEAD'].includes(verb)) {
          const key = decodeURIComponent(parts[2]);
          if (!name(key)) denied();
          // Existing board reads simple columns. Embedded relations require a
          // reviewed mapping; silently leaving a native relationship is unsafe.
          const select = url.searchParams.get('select') || '';
          if (/[():!]/.test(select)) denied('This related-data query has not been enabled for Department 135.');
          url.pathname = '/rest/v1/' + mapped('tables', key);
          return { url, kind: 'table', source: key };
        }
        denied('Department 135 records are changed through its protected actions.');
      }
      if (parts[0] === 'storage' && parts[1] === 'v1' && parts[2] === 'object') {
        const authenticated = parts[3] === 'authenticated';
        const bucketIndex = authenticated ? 4 : 3;
        if ((authenticated && verb !== 'GET') || (!authenticated && verb !== 'POST') || parts.length <= bucketIndex + 1) denied();
        const sourceBucket = decodeURIComponent(parts[bucketIndex]);
        const targetBucket = mapped('buckets', sourceBucket);
        const rawPath = parts.slice(bucketIndex + 1).join('/');
        let path;
        try { path = decodeURIComponent(rawPath); } catch (_) { denied(); }
        if (!path || path.length > 1024 || /[\x00-\x1f\\%]/.test(path) || path.split('/').some(part => !part || part === '.' || part === '..')) denied('The Department 135 photo path is invalid.');
        url.pathname = '/storage/v1/object/' + (authenticated ? 'authenticated/' : '') + targetBucket + '/' + rawPath;
        return { url, kind: 'storage' };
      }
      denied('This service is not enabled for Department 135.');
    }
    function guardedResponse(response, epoch) {
      const current = () => { if (getEpoch() !== epoch) denied('Department 135 access changed. Please reload the current information.'); };
      return new Proxy(response, { get(target, key) {
        if (key === 'body') denied('Read Department 135 responses through a complete guarded body.');
        if (key === 'clone') return () => { current(); return guardedResponse(target.clone(), epoch); };
        const value = Reflect.get(target, key, target);
        if (['json', 'text', 'blob', 'arrayBuffer', 'formData', 'bytes'].includes(key) && typeof value === 'function') return async (...args) => {
          current(); const result = await value.apply(target, args); current(); return result;
        };
        return typeof value === 'function' ? value.bind(target) : value;
      } });
    }
    async function guardedFetch(input, init) {
      const inputRequest = typeof Request !== 'undefined' && input instanceof Request ? input : null;
      const method = init?.method || inputRequest?.method || 'GET';
      const resolved = route(inputRequest ? inputRequest.url : String(input), method);
      const epoch = getEpoch();
      let next = { ...(init || {}) };
      if (resolved.kind !== 'asset') {
        // Supabase actions have no legitimate HTTP redirect. A redirect must
        // never bypass this allowlist and arrive at an original PMB endpoint.
        next.redirect = 'error';
        const headers = new Headers(next.headers || inputRequest?.headers || {});
        headers.set('Accept-Profile', 'public');
        headers.set('Content-Profile', 'public');
        next.headers = headers;
      }
      if (resolved.kind === 'rpc') {
        const body = next.body !== undefined ? next.body : inputRequest ? await inputRequest.clone().text() : undefined;
        if (typeof body !== 'string') denied('Department 135 action data is invalid.');
        let payload;
        try { payload = JSON.parse(body); } catch (_) { denied('Department 135 action data is invalid.'); }
        if (!payload || typeof payload !== 'object' || Array.isArray(payload)) denied();
        if (own(payload, 'p_bucket_id')) payload.p_bucket_id = mapped('buckets', payload.p_bucket_id);
        if (own(payload, 'p_photo_bucket_id')) payload.p_photo_bucket_id = mapped('buckets', payload.p_photo_bucket_id);
        next.body = JSON.stringify(payload);
      }
      let response;
      if (['rpc', 'table', 'storage'].includes(resolved.kind) && getEpoch() !== epoch) denied('Department 135 access changed. This request was not sent.');
      if (inputRequest) {
        const safe = new Request(resolved.url, inputRequest);
        response = await fetchNative(safe, next);
      } else {
        response = await fetchNative(resolved.url.toString(), next);
      }
      if (['rpc', 'table', 'storage'].includes(resolved.kind)) {
        if (getEpoch() !== epoch) denied('Department 135 access changed. Please reload the current information.');
        return guardedResponse(response, epoch);
      }
      return response;
    }
    function realtime(spec) {
      if (!map.ready || !spec || spec.schema !== 'public' || !name(spec.table) || !own(map.realtime, spec.table)) denied('This live update is not enabled for Department 135.');
      return { ...spec, schema: map.realtime[spec.table].schema, table: map.realtime[spec.table].table };
    }
    function wrapClient(client) {
      const channels = new WeakMap();
      const originals = new WeakMap();
      function wrapChannel(channel) {
        if (channels.has(channel)) return channels.get(channel);
        let proxy;
        proxy = new Proxy(channel, { get(target, key) {
          if (key === 'on') return (type, filter, callback) => {
            if (type !== 'postgres_changes') denied('This live channel is not enabled for Department 135.');
            if (typeof callback !== 'function') denied('This live update is invalid.');
            const registrationEpoch = getEpoch();
            target.on(type, realtime(filter), (...args) => {
              if (getEpoch() !== registrationEpoch) return;
              callback(...args);
            }); return proxy;
          };
          const value = Reflect.get(target, key, target);
          if (typeof value !== 'function') return value;
          return (...args) => { const result = value.apply(target, args); return result === target ? proxy : result; };
        } });
        channels.set(channel, proxy); originals.set(proxy, channel); return proxy;
      }
      const auth = new Proxy(client.auth, { get(target, key) {
        if (key === 'signOut') return options => target.signOut({ ...(options || {}), scope: 'local' });
        if (key === 'signUp') return async () => ({ data: { user: null, session: null }, error: { message: 'Please use an existing account. Ask your administrator to approve Department 135 access.' } });
        if (key === 'admin') return denied('Account administration is not available in this browser.');
        const value = Reflect.get(target, key, target); return typeof value === 'function' ? value.bind(target) : value;
      } });
      return new Proxy(client, { get(target, key) {
        if (key === 'auth') return auth;
        if (key === 'channel') return (topic, channelOptions) => wrapChannel(target.channel('k135:' + String(topic), channelOptions));
        if (key === 'removeChannel') return channel => target.removeChannel(originals.get(channel) || channel);
        const value = Reflect.get(target, key, target); return typeof value === 'function' ? value.bind(target) : value;
      } });
    }
    function wrapFactory(factory) {
      return (url, key, clientOptions) => {
        if (String(url).replace(/\/$/, '') !== PROJECT_URL || !map.ready) denied('Department 135 is waiting for its verified connection.');
        const original = clientOptions || {};
        const auth = { ...(original.auth || {}), storageKey: AUTH_KEY };
        const global = { ...(original.global || {}), fetch: guardedFetch };
        return wrapClient(factory(PROJECT_URL, key, { ...original, auth, global }));
      };
    }
    return Object.freeze({ route, fetch: guardedFetch, realtime, wrapClient, wrapFactory, ready: map.ready });
  }
  function install(options) {
    const window = options.root;
    if (!window || !window.supabase?.createClient || window.PDC135_CONNECTION) denied('Department 135 connection setup is unavailable.');
    let epoch = 0;
    let principal = '';
    const authority = () => {
      const context = window.PDC_AUTH_CONTEXT;
      const next = context ? JSON.stringify([context.userId, context.email, context.role, context.accountStatus, context.membership_version, context.engine_version, context.centreCode]) : '';
      // The own-role monitor is registered while sign-in is being verified.
      // First adoption belongs to that same locked generation. Replacement
      // of an existing authority always invalidates earlier callbacks.
      if (principal !== next) { if (principal) epoch++; principal = next; }
    };
    window.addEventListener('pdc-auth-locked', () => { epoch++; principal = ''; });
    window.addEventListener('pdc-auth-ready', authority);
    const transport = create({ map: options.map, fetch: window.fetch.bind(window), pageUrl: window.location.href, assets: options.assets, getEpoch: () => epoch });
    const factory = window.supabase.createClient.bind(window.supabase);
    window.fetch = transport.fetch;
    window.supabase = new Proxy(window.supabase, { get(target, key) { return key === 'createClient' ? transport.wrapFactory(factory) : Reflect.get(target, key, target); } });
    window.PDC135_CONNECTION = transport;
    return transport;
  }
  const api = Object.freeze({ create, install, validatedMap, AUTH_KEY, PROJECT_URL });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.PDC135_TRANSPORT = api;
})(typeof window !== 'undefined' ? window : globalThis);
