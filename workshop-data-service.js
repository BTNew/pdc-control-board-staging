(function initWorkshopDataService(globalScope, factory) {
  'use strict';
  const api = factory(globalScope || {});
  if (globalScope) globalScope.PDC_WORKSHOP_DATA = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : null, function workshopDataServiceFactory(root) {
  'use strict';

  const REALTIME_TABLES = [
    'workshop_bookings',
    'workshop_booking_assignments',
    'workshop_booking_history',
    'workshop_bays',
    'workshop_technicians',
    'workshop_settings',
    'vehicles',
  ];

  const state = {
    mode: 'idle',
    userId: '',
    error: null,
    refreshPromise: null,
    initializePromise: null,
    realtimeChannel: null,
    realtimeStatus: 'closed',
    refreshTimer: null,
    stages: [],
    bays: [],
    technicians: [],
    settings: {},
    vehicles: [],
    plannerVehicles: [],
    bookings: [],
    plans: [],
    lastLoadedAt: '',
    listeners: new Set(),
  };

  function browserConfig() {
    const config = root?.PDC_SUPABASE_CONFIG || {};
    const workshop = config.workshop || {};
    return {
      // Cutover is explicit. Merely having an authenticated Supabase client must
      // not switch an existing browser before migration and reconciliation.
      sharedData: workshop.sharedData === true,
      realtime: workshop.realtime !== false,
      refreshDebounceMs: Math.max(50, Number(workshop.refreshDebounceMs) || 150),
    };
  }

  function client() {
    return root?.PDC_SUPABASE || null;
  }

  function authContext() {
    return root?.PDC_AUTH_CONTEXT || null;
  }

  function isEnabled() {
    return Boolean(browserConfig().sharedData && client() && authContext()?.userId);
  }

  function isReady() {
    return state.mode === 'ready' && Boolean(state.userId) && state.userId === cleanText(authContext()?.userId);
  }

  function isLoading() {
    return state.mode === 'loading';
  }

  function hasError() {
    return state.mode === 'error';
  }

  function safeClone(value) {
    if (typeof structuredClone === 'function') {
      try { return structuredClone(value); } catch (_error) {}
    }
    return JSON.parse(JSON.stringify(value));
  }

  function cleanText(value) {
    return String(value ?? '').trim();
  }

  function numericTime(value) {
    const parsed = Date.parse(String(value || ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function stageCode(value) {
    return cleanText(value).toUpperCase();
  }

  function vehicleKeyFromRow(vehicle = {}) {
    return cleanText(vehicle.permanent_vehicle_id || vehicle.stock_number || vehicle.id);
  }

  function plannerVehicleFromRow(vehicle = {}) {
    const source = vehicle.source_payload && typeof vehicle.source_payload === 'object' && !Array.isArray(vehicle.source_payload)
      ? safeClone(vehicle.source_payload)
      : {};
    const permanentKey = vehicleKeyFromRow(vehicle);
    return {
      ...source,
      id: cleanText(source.id || permanentKey || vehicle.id),
      databaseVehicleId: cleanText(vehicle.id),
      permanentVehicleId: cleanText(vehicle.permanent_vehicle_id),
      stock: cleanText(vehicle.stock_number || source.stock),
      order: cleanText(source.order || vehicle.permanent_vehicle_id),
      pdcJobcard: cleanText(vehicle.job_card_number || source.pdcJobcard),
      customer: cleanText(vehicle.customer_name || source.customer || source.client),
      client: cleanText(vehicle.customer_name || source.client || source.customer),
      vehicle: cleanText(source.vehicle || vehicle.model),
      toyotaVehicle: cleanText(source.toyotaVehicle || vehicle.model),
      make: cleanText(vehicle.make || source.make),
      model: cleanText(vehicle.model || source.model),
      pdcLocation: cleanText(vehicle.current_location || source.pdcLocation),
      pmbStage: cleanText(vehicle.pmb_stage || source.pmbStage),
      pmbBayStage: cleanText(vehicle.pmb_bay_stage || source.pmbBayStage),
      pmbBayNumber: cleanText(vehicle.pmb_bay_number || source.pmbBayNumber),
      visibleOnBoard: Boolean(vehicle.visible_on_board),
      lifecycleState: cleanText(vehicle.lifecycle_state),
      serverVersion: Number(vehicle.version) || 1,
      serverUpdatedAt: cleanText(vehicle.updated_at),
    };
  }

  function chooseAssignment(rows = []) {
    return [...rows].sort((a, b) => {
      const activeDelta = Number(Boolean(a.released_at)) - Number(Boolean(b.released_at));
      if (activeDelta) return activeDelta;
      const primaryDelta = Number(b.assignment_type === 'primary') - Number(a.assignment_type === 'primary');
      if (primaryDelta) return primaryDelta;
      return numericTime(b.assigned_at) - numericTime(a.assigned_at);
    })[0] || null;
  }

  function mapBookingRow(row = {}, indexes = {}) {
    const stage = indexes.stages.get(row.stage_id) || {};
    const bay = indexes.bays.get(row.bay_id) || {};
    const vehicle = indexes.vehicles.get(row.vehicle_id) || {};
    const assignment = chooseAssignment(indexes.assignments.get(row.id) || []);
    const technician = assignment ? indexes.technicians.get(assignment.technician_id) || {} : {};
    const durationMinutes = Math.max(1, Number(row.default_duration_minutes) || 180);
    const actualDurationMinutes = Number(row.actual_duration_minutes);
    return {
      id: cleanText(row.id),
      serverBookingId: cleanText(row.id),
      vehicleId: cleanText(row.vehicle_id),
      vehicleKey: vehicleKeyFromRow(vehicle),
      stage: stageCode(stage.code),
      bay: Number(bay.bay_number) || 1,
      startAt: cleanText(row.scheduled_start_at),
      endAt: cleanText(row.scheduled_end_at),
      hours: durationMinutes / 60,
      assignee: cleanText(technician.name),
      technicianId: cleanText(technician.id),
      status: cleanText(row.status) || 'planned',
      version: Number(row.version) || 1,
      createdAt: cleanText(row.created_at),
      updatedAt: cleanText(row.updated_at),
      startedAt: cleanText(row.actual_start_at),
      completedAt: cleanText(row.actual_end_at),
      actualHours: Number.isFinite(actualDurationMinutes) ? actualDurationMinutes / 60 : undefined,
      stoppageReason: cleanText(row.stoppage_reason),
      stoppageAt: cleanText(row.stoppage_started_at),
      stoppageMinutes: Number(row.stoppage_accumulated_minutes) || 0,
      returnedToQueueAt: cleanText(row.returned_to_queue_at),
      deletedAt: cleanText(row.deleted_at),
      deletedReason: cleanText(row.deleted_reason),
      source: cleanText(row.source || 'planner'),
      serverVehicle: {
        permanentVehicleId: cleanText(vehicle.permanent_vehicle_id),
        stock: cleanText(vehicle.stock_number),
        jobCard: cleanText(vehicle.job_card_number),
        customer: cleanText(vehicle.customer_name),
        model: cleanText(vehicle.model),
      },
    };
  }

  function ensureNoQueryError(result, label) {
    if (result?.error) {
      const error = new Error(`${label}: ${result.error.message || String(result.error)}`);
      error.code = result.error.code || 'query_failed';
      error.details = result.error.details || '';
      throw error;
    }
    return Array.isArray(result?.data) ? result.data : [];
  }

  async function loadSnapshot() {
    const supabase = client();
    if (!supabase) throw new Error('Supabase client is unavailable.');

    const [stagesResult, baysResult, techniciansResult, settingsResult, bookingsResult, assignmentsResult, vehiclesResult] = await Promise.all([
      supabase.from('workshop_stages').select('id,code,display_name,sort_order,is_physical,is_sublet,active,updated_at').eq('active', true).order('sort_order'),
      supabase.from('workshop_bays').select('id,stage_id,bay_number,code,display_name,is_active,is_sublet_row,default_technician_id,updated_at').eq('is_active', true).order('bay_number'),
      supabase.from('workshop_technicians').select('id,name,role_type,active,can_fit_stages,leave_calendar,updated_at').eq('active', true).order('name'),
      supabase.from('workshop_settings').select('id,key,value,scope,updated_at').eq('scope', 'global').order('key'),
      supabase.from('workshop_bookings').select('id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,actual_start_at,actual_end_at,actual_duration_minutes,stoppage_reason,stoppage_started_at,stoppage_accumulated_minutes,returned_to_queue_at,deleted_at,deleted_reason,source,version,created_at,updated_at').neq('status', 'deleted').order('scheduled_start_at'),
      supabase.from('workshop_booking_assignments').select('id,booking_id,technician_id,assignment_type,assigned_at,scheduled_start_at,scheduled_end_at,released_at,notes,updated_at').order('assigned_at', { ascending: false }),
      supabase.from('vehicles').select('id,permanent_vehicle_id,stock_number,job_card_number,customer_name,make,model,lifecycle_state,visible_on_board,current_location,pmb_stage,pmb_bay_stage,pmb_bay_number,source_payload,version,updated_at'),
    ]);

    const stages = ensureNoQueryError(stagesResult, 'Workshop stages could not be loaded');
    const bays = ensureNoQueryError(baysResult, 'Workshop bays could not be loaded');
    const technicians = ensureNoQueryError(techniciansResult, 'Workshop technicians could not be loaded');
    const settingsRows = ensureNoQueryError(settingsResult, 'Workshop settings could not be loaded');
    const bookings = ensureNoQueryError(bookingsResult, 'Workshop bookings could not be loaded');
    const assignments = ensureNoQueryError(assignmentsResult, 'Workshop assignments could not be loaded');
    const vehicles = ensureNoQueryError(vehiclesResult, 'Workshop vehicles could not be loaded');

    const indexes = {
      stages: new Map(stages.map(row => [row.id, row])),
      bays: new Map(bays.map(row => [row.id, row])),
      technicians: new Map(technicians.map(row => [row.id, row])),
      vehicles: new Map(vehicles.map(row => [row.id, row])),
      assignments: new Map(),
    };
    assignments.forEach(row => {
      if (!indexes.assignments.has(row.booking_id)) indexes.assignments.set(row.booking_id, []);
      indexes.assignments.get(row.booking_id).push(row);
    });

    const mappedBookings = bookings
      .map(row => mapBookingRow(row, indexes))
      .filter(row => row.id && row.vehicleKey && row.stage);

    const settings = Object.fromEntries(settingsRows.map(row => [row.key, row.value]));
    if (Number(settings.frontend_contract_version) < 1) {
      const error = new Error('Supabase migration 009_workshop_planner_frontend_contract.sql has not been applied. Shared Workshop Planner changes are blocked.');
      error.code = 'workshop_contract_missing';
      throw error;
    }

    state.stages = stages;
    state.bays = bays;
    state.technicians = technicians;
    state.settings = settings;
    state.vehicles = vehicles;
    state.plannerVehicles = vehicles.map(plannerVehicleFromRow);
    state.bookings = mappedBookings;
    state.plans = mappedBookings.filter(row => !['queued', 'deleted'].includes(row.status));
    state.userId = cleanText(authContext()?.userId);
    state.lastLoadedAt = new Date().toISOString();
    state.error = null;
  }

  function notify(reason = 'refresh') {
    const detail = { reason, lastLoadedAt: state.lastLoadedAt, realtimeStatus: state.realtimeStatus };
    state.listeners.forEach(listener => {
      try { listener(detail); } catch (error) { console.error('Workshop data listener failed', error); }
    });
    if (root?.dispatchEvent && typeof root.CustomEvent === 'function') {
      root.dispatchEvent(new root.CustomEvent('pdc-workshop-data-changed', { detail }));
    }
  }

  async function refresh(reason = 'manual') {
    if (!isEnabled()) return false;
    if (state.refreshPromise) return state.refreshPromise;
    state.refreshPromise = (async () => {
      try {
        await loadSnapshot();
        state.mode = 'ready';
        notify(reason);
        return true;
      } catch (error) {
        state.error = error;
        state.mode = 'error';
        notify('error');
        throw error;
      } finally {
        state.refreshPromise = null;
      }
    })();
    return state.refreshPromise;
  }

  function scheduleRefresh(reason = 'realtime') {
    if (state.refreshTimer) root.clearTimeout(state.refreshTimer);
    state.refreshTimer = root.setTimeout(() => {
      state.refreshTimer = null;
      refresh(reason).catch(error => console.error('Workshop realtime refresh failed', error));
    }, browserConfig().refreshDebounceMs);
  }

  function subscribeRealtime() {
    if (!browserConfig().realtime || !isEnabled() || state.realtimeChannel) return;
    const supabase = client();
    const channel = supabase.channel(`pdc-workshop-${authContext().userId}`);
    REALTIME_TABLES.forEach(table => {
      channel.on('postgres_changes', { event: '*', schema: 'public', table }, () => scheduleRefresh(`realtime:${table}`));
    });
    channel.subscribe(status => {
      state.realtimeStatus = cleanText(status).toLowerCase();
      notify('realtime-status');
    });
    state.realtimeChannel = channel;
  }

  async function initialize() {
    if (!isEnabled()) return false;
    const currentUserId = cleanText(authContext()?.userId);
    if (state.userId && state.userId !== currentUserId) await resetConnection();
    if (isReady()) return true;
    if (state.initializePromise) return state.initializePromise;
    state.mode = 'loading';
    state.initializePromise = (async () => {
      try {
        await refresh('initial-load');
        subscribeRealtime();
        return true;
      } catch (error) {
        state.error = error;
        state.mode = 'error';
        throw error;
      } finally {
        state.initializePromise = null;
      }
    })();
    return state.initializePromise;
  }

  async function retry() {
    state.mode = 'loading';
    state.error = null;
    const refreshed = await refresh('retry');
    subscribeRealtime();
    return refreshed;
  }

  function getPlans() {
    return safeClone(state.plans);
  }

  function getBookings() {
    return safeClone(state.bookings);
  }

  function getPlannerVehicles() {
    return safeClone(state.plannerVehicles);
  }

  function getPlannerVehicle(vehicleKey) {
    const requested = cleanText(vehicleKey).toLowerCase();
    if (!requested) return null;
    const matches = state.plannerVehicles.filter(vehicle => [vehicle.id, vehicle.databaseVehicleId, vehicle.permanentVehicleId, vehicle.stock, vehicle.order]
      .map(value => cleanText(value).toLowerCase())
      .includes(requested));
    return matches.length === 1 ? safeClone(matches[0]) : null;
  }

  function getStages() {
    return safeClone(state.stages);
  }

  function getBays(stage = '') {
    const code = stageCode(stage);
    const stageRow = state.stages.find(row => stageCode(row.code) === code);
    return safeClone(state.bays.filter(row => !code || row.stage_id === stageRow?.id));
  }

  function getTechnicians(roleType = '') {
    const role = cleanText(roleType).toLowerCase();
    return safeClone(state.technicians.filter(row => !role || row.role_type === role));
  }

  function getSettings() {
    return safeClone(state.settings);
  }

  function getStatus() {
    return {
      mode: state.mode,
      error: state.error ? state.error.message || String(state.error) : '',
      realtimeStatus: state.realtimeStatus,
      lastLoadedAt: state.lastLoadedAt,
      planCount: state.plans.length,
      bookingCount: state.bookings.length,
    };
  }

  function getBaySetup() {
    const technicianById = new Map(state.technicians.map(row => [row.id, row.name]));
    const stageById = new Map(state.stages.map(row => [row.id, row.code]));
    const setup = {};
    state.bays.forEach(bay => {
      const name = cleanText(technicianById.get(bay.default_technician_id));
      const code = stageCode(stageById.get(bay.stage_id));
      if (name && code) setup[`${code}:${Number(bay.bay_number) || 1}`] = name;
    });
    return setup;
  }

  function resolveVehicle(vehicleKey) {
    const requested = cleanText(vehicleKey).toLowerCase();
    if (!requested) return null;
    const matches = state.vehicles.filter(row => [row.permanent_vehicle_id, row.stock_number, row.id]
      .map(value => cleanText(value).toLowerCase())
      .includes(requested));
    if (matches.length > 1) {
      const error = new Error(`Vehicle ${vehicleKey} is ambiguous in the shared database. No workshop booking was changed.`);
      error.code = 'vehicle_ambiguous';
      throw error;
    }
    if (!matches.length) {
      const error = new Error(`Vehicle ${vehicleKey} is not in the shared Supabase vehicle table. Import or migrate the vehicle before scheduling it.`);
      error.code = 'vehicle_not_found';
      throw error;
    }
    return matches[0];
  }

  function resolvePlan(planOrId) {
    const id = cleanText(typeof planOrId === 'object' ? planOrId.id : planOrId);
    const plan = state.bookings.find(row => row.id === id);
    if (!plan) {
      const error = new Error('The workshop booking no longer exists. The shared planner has been refreshed.');
      error.code = 'booking_not_found';
      throw error;
    }
    return plan;
  }

  async function ensureTechnician(name, stage = '') {
    const cleanName = cleanText(name);
    if (!cleanName) return null;
    const existing = state.technicians.filter(row => row.name.toLowerCase() === cleanName.toLowerCase());
    if (existing.length === 1) return existing[0];
    if (existing.length > 1) throw new Error(`Technician/provider ${cleanName} is duplicated in Supabase.`);
    const roleType = stageCode(stage) === 'SUBLET' ? 'provider' : 'technician';
    const { data, error } = await client().rpc('workshop_ensure_technician', {
      p_name: cleanName,
      p_role_type: roleType,
    });
    if (error) throw new Error(error.message || 'The technician/provider could not be saved.');
    await refresh('technician-created');
    const id = cleanText(data);
    return state.technicians.find(row => row.id === id) || state.technicians.find(row => row.name.toLowerCase() === cleanName.toLowerCase()) || null;
  }

  function mutationError(payload = {}, fallback = 'The workshop change was rejected.') {
    const code = cleanText(payload.error || 'mutation_rejected');
    const conflict = payload.conflict || {};
    const existing = conflict.existing_booking || {};
    const stock = cleanText(existing.vehicle?.stock_number || existing.vehicle?.permanent_vehicle_id || 'another vehicle');
    const stage = cleanText(existing.stage?.display_name || existing.stage?.code);
    const bay = cleanText(existing.bay?.display_name || existing.bay?.bay_number);
    const when = cleanText(existing.scheduled_start_at);
    let message = fallback;
    if (code === 'bay_overlap') message = `That bay is already booked for ${stock}${stage ? ` in ${stage}` : ''}${bay ? ` (${bay})` : ''}${when ? ` from ${new Date(when).toLocaleString('en-AU')}` : ''}.`;
    else if (code === 'technician_overlap') message = `That technician/provider is already booked on ${stock}${when ? ` from ${new Date(when).toLocaleString('en-AU')}` : ''}.`;
    else if (code === 'version_conflict') message = 'Someone else changed this booking first. The shared planner has been refreshed; review the latest booking and try again.';
    else if (code === 'booking_exists') message = `An open ${stage || 'workshop'} booking already exists for ${stock}.`;
    const error = new Error(message);
    error.code = code;
    error.conflict = conflict;
    return error;
  }

  async function runRpc(name, parameters, reason) {
    const result = await client().rpc(name, parameters);
    if (result.error) {
      const error = new Error(result.error.message || `Workshop operation ${name} failed.`);
      error.code = result.error.code || 'rpc_failed';
      error.details = result.error.details || '';
      throw error;
    }
    const payload = result.data || {};
    if (payload.ok === false) throw mutationError(payload);
    await refresh(reason || name);
    return payload;
  }

  async function createBooking({ vehicleKey, stage, bay, startAt, hours, assignee = '', metadata = {} } = {}) {
    const vehicle = resolveVehicle(vehicleKey);
    const technician = await ensureTechnician(assignee, stage);
    const payload = await runRpc('workshop_create_booking', {
      p_vehicle_id: vehicle.id,
      p_stage_code: stageCode(stage),
      p_bay_number: Number(bay) || 1,
      p_scheduled_start_at: new Date(startAt).toISOString(),
      p_duration_minutes: Math.max(1, Math.round(Number(hours) * 60)),
      p_technician_id: technician?.id || null,
      p_metadata: metadata || {},
    }, 'booking-created');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function updateBooking(planOrId, { stage, bay, startAt, hours, assignee = '', eventType = 'moved', metadata = {} } = {}) {
    const plan = resolvePlan(planOrId);
    const technician = await ensureTechnician(assignee, stage || plan.stage);
    const payload = await runRpc('workshop_update_booking', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_stage_code: stageCode(stage || plan.stage),
      p_bay_number: Number(bay || plan.bay) || 1,
      p_scheduled_start_at: new Date(startAt || plan.startAt).toISOString(),
      p_duration_minutes: Math.max(1, Math.round(Number(hours || plan.hours) * 60)),
      p_technician_id: technician?.id || null,
      p_event_type: cleanText(eventType || 'moved'),
      p_metadata: metadata || {},
    }, `booking-${eventType || 'updated'}`);
    return resolvePlan(payload.booking?.booking_id);
  }

  async function startBooking(planOrId, metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_start_booking', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_actual_start_at: new Date().toISOString(),
      p_metadata: metadata || {},
    }, 'booking-started');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function recordStoppage(planOrId, reason, metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_record_stoppage', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_reason: cleanText(reason),
      p_metadata: metadata || {},
    }, 'booking-stoppage');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function resumeBooking(planOrId, metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_resume_booking', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_metadata: metadata || {},
    }, 'booking-resumed');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function completeBooking(planOrId, metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_complete_booking', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_actual_end_at: new Date().toISOString(),
      p_metadata: metadata || {},
    }, 'booking-completed');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function returnBookingToQueue(planOrId, reason = '', metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_return_booking_to_queue', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_reason: cleanText(reason) || null,
      p_metadata: metadata || {},
    }, 'booking-returned');
    return resolvePlan(payload.booking?.booking_id);
  }

  async function deleteBooking(planOrId, reason = '', metadata = {}) {
    const plan = resolvePlan(planOrId);
    const payload = await runRpc('workshop_delete_booking', {
      p_booking_id: plan.id,
      p_expected_version: Number(plan.version),
      p_reason: cleanText(reason) || null,
      p_metadata: metadata || {},
    }, 'booking-deleted');
    return payload.booking || null;
  }

  async function setBayDefault(stage, bay, assignee = '') {
    await runRpc('workshop_set_bay_default_technician', {
      p_stage_code: stageCode(stage),
      p_bay_number: Number(bay) || 1,
      p_technician_name: cleanText(assignee) || null,
      p_role_type: stageCode(stage) === 'SUBLET' ? 'provider' : 'technician',
    }, 'bay-default-updated');
    return true;
  }

  function onChange(listener) {
    if (typeof listener !== 'function') return () => {};
    state.listeners.add(listener);
    return () => state.listeners.delete(listener);
  }

  async function resetConnection() {
    if (state.refreshTimer) root.clearTimeout(state.refreshTimer);
    state.refreshTimer = null;
    if (state.realtimeChannel && client()) {
      await client().removeChannel(state.realtimeChannel);
    }
    state.realtimeChannel = null;
    state.realtimeStatus = 'closed';
    state.mode = 'idle';
    state.userId = '';
    state.error = null;
    state.refreshPromise = null;
    state.initializePromise = null;
    state.stages = [];
    state.bays = [];
    state.technicians = [];
    state.settings = {};
    state.vehicles = [];
    state.plannerVehicles = [];
    state.bookings = [];
    state.plans = [];
    state.lastLoadedAt = '';
  }

  async function destroy() {
    await resetConnection();
    state.listeners.clear();
  }

  return Object.freeze({
    isEnabled,
    isReady,
    isLoading,
    hasError,
    initialize,
    retry,
    refresh,
    destroy,
    onChange,
    getStatus,
    getPlans,
    getBookings,
    getPlannerVehicles,
    getPlannerVehicle,
    getStages,
    getBays,
    getTechnicians,
    getSettings,
    getBaySetup,
    resolveVehicle,
    resolvePlan,
    createBooking,
    updateBooking,
    startBooking,
    recordStoppage,
    resumeBooking,
    completeBooking,
    returnBookingToQueue,
    deleteBooking,
    setBayDefault,
    _test: Object.freeze({ mapBookingRow, chooseAssignment, vehicleKeyFromRow, plannerVehicleFromRow, mutationError }),
  });
});
