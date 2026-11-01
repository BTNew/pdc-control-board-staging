-- r816 (F455): Craig 2 Nov 2026 06:06 AWST: "should we be creating fitter logins? so we know who worked on the vehicle?
-- initials then there dob? they dont have emails so the user/passcode needs to be done on the board". 06:09: "lets build it,
-- dont apply it yet until i get all the names etc.."
-- Every timer on the Fitters bay records a technician, but the shared tablet logins let anyone pick any name, so the hours
-- do not prove who did the work. 06:33: "lets use the mechanic ID which they get from TUNE as the username. password, use
-- there intials then mechanic ID?" 07:30: "maybe we use there name as the login and there fitter number as the pin number".
-- The fitter taps their name; the first PIN is their fitter (Tune mechanic) number. Anyone can work that out, so it is
-- temporary: at first sign-in the fitter picks their own 4 to 6 digit PIN (not a date of birth). An administrator creates the logins on the board (Bay Manager >
-- Fitter logins; one button creates every mechanic that has a Tune ID). 5 wrong passwords lock the login for 5 minutes.
-- A fitter is signed out after 10 idle minutes, or when signing in on another tablet.
-- The Fitters bay write RPCs (job command, Later, send / undo send) refuse work without a signed-in fitter, and refuse work
-- under another fitter's name, but ONLY once an administrator switches "Fitter sign-in required" on. Applying this changes
-- nothing on the tablets until then, so the names can be loaded first.
-- The session token travels in the x-pdc-fitter-session request header, so no existing RPC signature changes.
-- Undo: switch required off (admin_set_fitter_login_required_816(false, null)); the guards then return at once.
DO $r816$
DECLARE
  v_old text; v_new text; v_def text; v_pos int; sig regprocedure; f record;
  v_hook_old text := $h$'rpc/list_line_handoffs_583','rpc/set_line_later_627')$h$;
  v_hook_new text := $h$'rpc/list_line_handoffs_583','rpc/set_line_later_627',
   -- r816 (F455): fitter initials + PIN sign-in on the tablet.
   'rpc/fitter_login_state_816','rpc/fitter_sign_in_816','rpc/fitter_session_816','rpc/fitter_change_pin_816','rpc/fitter_sign_out_816')$h$;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (604, 605) OR fault_id = 'F455' OR added_in = 'r816') THEN RAISE EXCEPTION 'r816: sort 604/605 or F455 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r816: an import job is running'; END IF;

  -- Tables. Read and written only through the SECURITY DEFINER functions below.
  CREATE TABLE public.pdc_fitter_logins_816 (
    technician_id uuid PRIMARY KEY REFERENCES public.workshop_technicians(id),
    username text NOT NULL UNIQUE CHECK (username ~ '^[0-9]{2,6}$'),
    pin_hash text NOT NULL,
    must_change boolean NOT NULL DEFAULT true,
    failed_count integer NOT NULL DEFAULT 0,
    locked_until timestamptz,
    active boolean NOT NULL DEFAULT true,
    pin_set_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    created_by text,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_by text
  );
  CREATE TABLE public.pdc_fitter_sessions_816 (
    token_hash text PRIMARY KEY,
    technician_id uuid NOT NULL REFERENCES public.workshop_technicians(id),
    device_user uuid,
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    ended_at timestamptz,
    end_reason text
  );
  CREATE INDEX pdc_fitter_sessions_816_open ON public.pdc_fitter_sessions_816 (technician_id) WHERE ended_at IS NULL;
  CREATE TABLE public.pdc_fitter_login_events_816 (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    technician_id uuid,
    username text,
    event text NOT NULL,
    device_user uuid,
    actor_email text,
    at timestamptz NOT NULL DEFAULT clock_timestamp(),
    detail jsonb NOT NULL DEFAULT '{}'::jsonb
  );
  CREATE INDEX pdc_fitter_login_events_816_tech ON public.pdc_fitter_login_events_816 (technician_id, at DESC);
  CREATE TABLE pdc_ops.fitter_login_settings_816 (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    required boolean NOT NULL DEFAULT false,
    idle_minutes integer NOT NULL DEFAULT 10 CHECK (idle_minutes BETWEEN 2 AND 60),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_by text
  );
  INSERT INTO pdc_ops.fitter_login_settings_816 DEFAULT VALUES;
  ALTER TABLE public.pdc_fitter_logins_816 ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.pdc_fitter_sessions_816 ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.pdc_fitter_login_events_816 ENABLE ROW LEVEL SECURITY;
  ALTER TABLE pdc_ops.fitter_login_settings_816 ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON public.pdc_fitter_logins_816, public.pdc_fitter_sessions_816, public.pdc_fitter_login_events_816 FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON pdc_ops.fitter_login_settings_816 FROM PUBLIC, anon, authenticated;

  -- The Fitters bay request hook lets a fitter account call the sign-in RPCs.
  sig := 'public.pdc_check_fitter_request()'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, v_hook_old, ''))) / length(v_hook_old) <> 1 OR strpos(v_old, 'r816 (F455)') > 0 THEN RAISE EXCEPTION 'r816: hook anchor not found once'; END IF;
  v_new := replace(v_old, v_hook_old, v_hook_new);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r816: hook readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r816$;

-- A PIN is 4 to 6 digits and not an obvious one (all the same digit, a run like 1234 / 4321, or 0000).
CREATE FUNCTION public.pdc_fitter_pin_problem_816(p_pin text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO 'pg_catalog' AS $f$
DECLARE d text := coalesce(p_pin, '');
BEGIN
  IF d !~ '^[0-9]{4,6}$' THEN RETURN 'pin_format'; END IF;
  IF d ~ '^(.)\1+$' OR strpos('0123456789', d) > 0 OR strpos('9876543210', d) > 0 THEN RETURN 'pin_too_simple'; END IF;
  RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_pin_problem_816(text) FROM PUBLIC, anon, authenticated;

-- A temporary password is the fitter number (2 to 6 digits), initials then fitter number (MR2686), or a good PIN.
-- It must be changed at first sign-in.
CREATE FUNCTION public.pdc_fitter_temp_problem_816(p_temp text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO 'pg_catalog' AS $f$
BEGIN
  IF upper(btrim(coalesce(p_temp, ''))) ~ '^([A-Z]{1,4})?[0-9]{2,6}$' THEN RETURN NULL; END IF;
  RETURN public.pdc_fitter_pin_problem_816(p_temp);
END $f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_temp_problem_816(text) FROM PUBLIC, anon, authenticated;

-- Initials from a name: first letter of each word (letters only), up to 4. "Mudassar Rasheed" -> MR.
CREATE FUNCTION public.pdc_fitter_initials_816(p_name text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog' AS $f$
  SELECT left(coalesce(string_agg(left(w, 1), '' ORDER BY n), ''), 4)
  FROM regexp_split_to_table(btrim(regexp_replace(upper(coalesce(p_name, '')), '[^A-Z ]', ' ', 'g')), '\s+') WITH ORDINALITY AS x(w, n)
  WHERE w <> ''
$f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_initials_816(text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pdc_fitter_role_816()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
  SELECT lower(btrim(coalesce(public.current_pdc_user_role()::text, '')))
$f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_role_816() FROM PUBLIC, anon, authenticated;

-- The open session for a token on this device, or NULL. p_touch keeps it alive.
CREATE FUNCTION public.pdc_fitter_session_lookup_816(p_token text, p_touch boolean)
RETURNS public.pdc_fitter_sessions_816 LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE s public.pdc_fitter_sessions_816; v_idle integer; v_now timestamptz := clock_timestamp();
BEGIN
  IF nullif(btrim(coalesce(p_token, '')), '') IS NULL OR auth.uid() IS NULL THEN RETURN NULL; END IF;
  SELECT idle_minutes INTO v_idle FROM pdc_ops.fitter_login_settings_816 WHERE singleton;
  SELECT * INTO s FROM public.pdc_fitter_sessions_816
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') AND ended_at IS NULL AND device_user = auth.uid();
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF s.last_seen_at < v_now - make_interval(mins => coalesce(v_idle, 10))
     OR NOT EXISTS (SELECT 1 FROM public.pdc_fitter_logins_816 l JOIN public.workshop_technicians t ON t.id = l.technician_id
                    WHERE l.technician_id = s.technician_id AND l.active AND t.active) THEN
    UPDATE public.pdc_fitter_sessions_816 SET ended_at = v_now, end_reason = 'idle' WHERE token_hash = s.token_hash;
    RETURN NULL;
  END IF;
  IF p_touch AND s.last_seen_at < v_now - interval '15 seconds' THEN
    UPDATE public.pdc_fitter_sessions_816 SET last_seen_at = v_now WHERE token_hash = s.token_hash;
    s.last_seen_at := v_now;
  END IF;
  RETURN s;
END $f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_session_lookup_816(text, boolean) FROM PUBLIC, anon, authenticated;

-- r816 (F455): NULL lets the Fitters bay write go ahead; otherwise the error code to return.
CREATE FUNCTION public.pdc_fitter_guard_816(p_technician_id uuid)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE s public.pdc_fitter_sessions_816; v_token text;
BEGIN
  IF NOT coalesce((SELECT required FROM pdc_ops.fitter_login_settings_816 WHERE singleton), false) THEN RETURN NULL; END IF;
  BEGIN
    v_token := current_setting('request.headers', true)::jsonb ->> 'x-pdc-fitter-session';
  EXCEPTION WHEN others THEN v_token := NULL;
  END;
  s := public.pdc_fitter_session_lookup_816(v_token, true);
  IF s.token_hash IS NULL THEN RETURN 'fitter_sign_in_required'; END IF;
  IF p_technician_id IS NOT NULL AND p_technician_id <> s.technician_id THEN RETURN 'fitter_not_this_mechanic'; END IF;
  RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION public.pdc_fitter_guard_816(uuid) FROM PUBLIC, anon, authenticated;

-- Tablet: is sign-in required, and the initials to pick from.
CREATE FUNCTION public.fitter_login_state_816()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_role text := public.pdc_fitter_role_816(); st pdc_ops.fitter_login_settings_816;
BEGIN
  IF v_role NOT IN ('fitter', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  SELECT * INTO st FROM pdc_ops.fitter_login_settings_816 WHERE singleton;
  RETURN jsonb_build_object('ok', true, 'required', coalesce(st.required, false), 'idle_minutes', coalesce(st.idle_minutes, 10),
    'fitters', (SELECT coalesce(jsonb_agg(jsonb_build_object('username', l.username, 'name', t.name) ORDER BY t.name), '[]'::jsonb)
                FROM public.pdc_fitter_logins_816 l JOIN public.workshop_technicians t ON t.id = l.technician_id
                WHERE l.active AND t.active));
END $f$;

CREATE FUNCTION public.fitter_sign_in_816(p_username text, p_pin text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE
  v_role text := public.pdc_fitter_role_816(); v_user text := upper(btrim(coalesce(p_username, '')));
  l public.pdc_fitter_logins_816; v_name text; v_token text; v_now timestamptz := clock_timestamp(); v_idle integer;
BEGIN
  IF v_role NOT IN ('fitter', 'operator', 'administrator') OR auth.uid() IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:fitter-login:' || v_user, 0));
  SELECT l2.* INTO l FROM public.pdc_fitter_logins_816 l2 JOIN public.workshop_technicians t ON t.id = l2.technician_id
  WHERE l2.username = v_user AND l2.active AND t.active FOR UPDATE OF l2;
  IF NOT FOUND THEN
    INSERT INTO public.pdc_fitter_login_events_816(username, event, device_user) VALUES (left(v_user, 8), 'unknown_user', auth.uid());
    RETURN jsonb_build_object('ok', false, 'error', 'fitter_sign_in_failed');
  END IF;
  IF l.locked_until > v_now THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fitter_locked', 'locked_until', l.locked_until);
  END IF;
  IF extensions.crypt(upper(btrim(coalesce(p_pin, ''))), l.pin_hash) <> l.pin_hash THEN
    UPDATE public.pdc_fitter_logins_816
    SET failed_count = CASE WHEN failed_count + 1 >= 5 THEN 0 ELSE failed_count + 1 END,
        locked_until = CASE WHEN failed_count + 1 >= 5 THEN v_now + interval '5 minutes' ELSE locked_until END
    WHERE technician_id = l.technician_id;
    INSERT INTO public.pdc_fitter_login_events_816(technician_id, username, event, device_user, detail)
    VALUES (l.technician_id, l.username, CASE WHEN l.failed_count + 1 >= 5 THEN 'locked' ELSE 'wrong_pin' END, auth.uid(), jsonb_build_object('attempt', l.failed_count + 1));
    IF l.failed_count + 1 >= 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'fitter_locked', 'locked_until', v_now + interval '5 minutes'); END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'fitter_sign_in_failed', 'attempts_left', 5 - (l.failed_count + 1));
  END IF;
  UPDATE public.pdc_fitter_logins_816 SET failed_count = 0, locked_until = NULL WHERE technician_id = l.technician_id;
  -- One fitter, one tablet: sign this fitter out anywhere else.
  UPDATE public.pdc_fitter_sessions_816 SET ended_at = v_now, end_reason = 'signed_in_elsewhere'
  WHERE technician_id = l.technician_id AND ended_at IS NULL;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO public.pdc_fitter_sessions_816(token_hash, technician_id, device_user, started_at, last_seen_at)
  VALUES (encode(extensions.digest(v_token, 'sha256'), 'hex'), l.technician_id, auth.uid(), v_now, v_now);
  INSERT INTO public.pdc_fitter_login_events_816(technician_id, username, event, device_user) VALUES (l.technician_id, l.username, 'signed_in', auth.uid());
  SELECT name INTO v_name FROM public.workshop_technicians WHERE id = l.technician_id;
  SELECT idle_minutes INTO v_idle FROM pdc_ops.fitter_login_settings_816 WHERE singleton;
  RETURN jsonb_build_object('ok', true, 'token', v_token, 'must_change', l.must_change, 'idle_minutes', coalesce(v_idle, 10),
    'fitter', jsonb_build_object('technician_id', l.technician_id, 'username', l.username, 'name', v_name));
END $f$;

CREATE FUNCTION public.fitter_session_816(p_token text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE s public.pdc_fitter_sessions_816; l public.pdc_fitter_logins_816; v_name text;
BEGIN
  IF public.pdc_fitter_role_816() NOT IN ('fitter', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  s := public.pdc_fitter_session_lookup_816(p_token, true);
  IF s.token_hash IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'fitter_sign_in_required'); END IF;
  SELECT * INTO l FROM public.pdc_fitter_logins_816 WHERE technician_id = s.technician_id;
  SELECT name INTO v_name FROM public.workshop_technicians WHERE id = s.technician_id;
  RETURN jsonb_build_object('ok', true, 'must_change', l.must_change,
    'fitter', jsonb_build_object('technician_id', s.technician_id, 'username', l.username, 'name', v_name));
END $f$;

CREATE FUNCTION public.fitter_change_pin_816(p_token text, p_current_pin text, p_new_pin text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE s public.pdc_fitter_sessions_816; l public.pdc_fitter_logins_816; v_problem text;
BEGIN
  IF public.pdc_fitter_role_816() NOT IN ('fitter', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  s := public.pdc_fitter_session_lookup_816(p_token, true);
  IF s.token_hash IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'fitter_sign_in_required'); END IF;
  SELECT * INTO l FROM public.pdc_fitter_logins_816 WHERE technician_id = s.technician_id FOR UPDATE;
  IF extensions.crypt(upper(btrim(coalesce(p_current_pin, ''))), l.pin_hash) <> l.pin_hash THEN RETURN jsonb_build_object('ok', false, 'error', 'fitter_pin_wrong'); END IF;
  v_problem := public.pdc_fitter_pin_problem_816(p_new_pin);
  IF v_problem IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', v_problem); END IF;
  IF p_new_pin = upper(btrim(coalesce(p_current_pin, ''))) THEN RETURN jsonb_build_object('ok', false, 'error', 'pin_same'); END IF;
  UPDATE public.pdc_fitter_logins_816 SET pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 8)), must_change = false,
         pin_set_at = clock_timestamp(), updated_at = clock_timestamp(), updated_by = l.username
  WHERE technician_id = l.technician_id;
  INSERT INTO public.pdc_fitter_login_events_816(technician_id, username, event, device_user) VALUES (l.technician_id, l.username, 'pin_changed', auth.uid());
  RETURN jsonb_build_object('ok', true);
END $f$;

CREATE FUNCTION public.fitter_sign_out_816(p_token text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE s public.pdc_fitter_sessions_816;
BEGIN
  IF public.pdc_fitter_role_816() NOT IN ('fitter', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  s := public.pdc_fitter_session_lookup_816(p_token, false);
  IF s.token_hash IS NOT NULL THEN
    UPDATE public.pdc_fitter_sessions_816 SET ended_at = clock_timestamp(), end_reason = 'signed_out' WHERE token_hash = s.token_hash;
    INSERT INTO public.pdc_fitter_login_events_816(technician_id, event, device_user) VALUES (s.technician_id, 'signed_out', auth.uid());
  END IF;
  RETURN jsonb_build_object('ok', true);
END $f$;

-- Administrator: Bay Manager > Fitter logins.
CREATE FUNCTION public.admin_list_fitter_logins_816()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE st pdc_ops.fitter_login_settings_816;
BEGIN
  IF public.pdc_fitter_role_816() <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT * INTO st FROM pdc_ops.fitter_login_settings_816 WHERE singleton;
  RETURN jsonb_build_object('ok', true, 'required', st.required, 'idle_minutes', st.idle_minutes,
    'technicians', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'technician_id', t.id, 'name', t.name, 'code', t.code,
        'username', l.username, 'active', l.active, 'must_change', l.must_change, 'locked_until', l.locked_until,
        'pin_set_at', l.pin_set_at,
        'last_sign_in', (SELECT max(e.at) FROM public.pdc_fitter_login_events_816 e WHERE e.technician_id = t.id AND e.event = 'signed_in'),
        'timed_jobs_14d', (SELECT count(*) FROM pdc_fitter_private.operation_timing o WHERE o.technician_id = t.id AND o.updated_at > clock_timestamp() - interval '14 days'))
      ORDER BY (l.username IS NULL), t.name), '[]'::jsonb)
      FROM public.workshop_technicians t LEFT JOIN public.pdc_fitter_logins_816 l ON l.technician_id = t.id
      WHERE t.active AND t.role_type = 'technician'));
END $f$;

CREATE FUNCTION public.admin_set_fitter_login_816(p_technician_id uuid, p_username text, p_temp_pin text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_user text := upper(btrim(coalesce(p_username, ''))); v_problem text; v_email text := public.current_actor_email(); v_now timestamptz := clock_timestamp();
BEGIN
  IF public.pdc_fitter_role_816() <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workshop_technicians WHERE id = p_technician_id AND active) THEN RETURN jsonb_build_object('ok', false, 'error', 'technician_not_found'); END IF;
  IF v_user !~ '^[0-9]{2,6}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'username_format'); END IF;
  IF EXISTS (SELECT 1 FROM public.pdc_fitter_logins_816 WHERE username = v_user AND technician_id <> p_technician_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'username_taken');
  END IF;
  v_problem := public.pdc_fitter_temp_problem_816(p_temp_pin);
  IF v_problem IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', v_problem); END IF;
  INSERT INTO public.pdc_fitter_logins_816(technician_id, username, pin_hash, must_change, created_by, updated_by)
  VALUES (p_technician_id, v_user, extensions.crypt(upper(btrim(p_temp_pin)), extensions.gen_salt('bf', 8)), true, v_email, v_email)
  ON CONFLICT (technician_id) DO UPDATE SET username = excluded.username, pin_hash = excluded.pin_hash, must_change = true,
    failed_count = 0, locked_until = NULL, active = true, pin_set_at = v_now, updated_at = v_now, updated_by = v_email
  WHERE public.pdc_fitter_logins_816.technician_id = excluded.technician_id;
  -- A new temporary PIN signs the fitter out everywhere.
  UPDATE public.pdc_fitter_sessions_816 SET ended_at = v_now, end_reason = 'pin_reset' WHERE technician_id = p_technician_id AND ended_at IS NULL;
  INSERT INTO public.pdc_fitter_login_events_816(technician_id, username, event, device_user, actor_email) VALUES (p_technician_id, v_user, 'pin_set_by_admin', auth.uid(), v_email);
  RETURN jsonb_build_object('ok', true, 'username', v_user);
END $f$;

-- One button: a login for every active mechanic with a Tune mechanic ID and no login yet.
-- Username = mechanic ID; first PIN = the fitter number itself (Craig 07:30), changed at first sign-in.
CREATE FUNCTION public.admin_create_fitter_logins_from_tune_816()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_email text := public.current_actor_email(); t record; v_created integer := 0; v_skipped jsonb := '[]'::jsonb; v_ini text;
BEGIN
  IF public.pdc_fitter_role_816() <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  FOR t IN SELECT w.id, w.name, btrim(w.code) code FROM public.workshop_technicians w
           WHERE w.active AND w.role_type = 'technician' AND NOT EXISTS (SELECT 1 FROM public.pdc_fitter_logins_816 l WHERE l.technician_id = w.id)
           ORDER BY w.name LOOP
    v_ini := public.pdc_fitter_initials_816(t.name);
    IF coalesce(t.code, '') !~ '^[0-9]{2,6}$' THEN v_skipped := v_skipped || jsonb_build_object('name', t.name, 'reason', 'no_mechanic_id'); CONTINUE; END IF;
    IF v_ini = '' THEN v_skipped := v_skipped || jsonb_build_object('name', t.name, 'reason', 'no_initials'); CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM public.pdc_fitter_logins_816 WHERE username = t.code) THEN
      v_skipped := v_skipped || jsonb_build_object('name', t.name, 'reason', 'username_taken'); CONTINUE;
    END IF;
    INSERT INTO public.pdc_fitter_logins_816(technician_id, username, pin_hash, must_change, created_by, updated_by)
    VALUES (t.id, t.code, extensions.crypt(t.code, extensions.gen_salt('bf', 8)), true, v_email, v_email);
    INSERT INTO public.pdc_fitter_login_events_816(technician_id, username, event, device_user, actor_email)
    VALUES (t.id, t.code, 'created_from_tune', auth.uid(), v_email);
    v_created := v_created + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'created', v_created, 'skipped', v_skipped);
END $f$;

CREATE FUNCTION public.admin_set_fitter_login_active_816(p_technician_id uuid, p_active boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_email text := public.current_actor_email();
BEGIN
  IF public.pdc_fitter_role_816() <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  UPDATE public.pdc_fitter_logins_816 SET active = coalesce(p_active, false), updated_at = clock_timestamp(), updated_by = v_email WHERE technician_id = p_technician_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'login_not_found'); END IF;
  IF NOT coalesce(p_active, false) THEN
    UPDATE public.pdc_fitter_sessions_816 SET ended_at = clock_timestamp(), end_reason = 'disabled' WHERE technician_id = p_technician_id AND ended_at IS NULL;
  END IF;
  INSERT INTO public.pdc_fitter_login_events_816(technician_id, event, device_user, actor_email) VALUES (p_technician_id, CASE WHEN p_active THEN 'enabled' ELSE 'disabled' END, auth.uid(), v_email);
  RETURN jsonb_build_object('ok', true);
END $f$;

CREATE FUNCTION public.admin_set_fitter_login_required_816(p_required boolean, p_idle_minutes integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_email text := public.current_actor_email(); v_logins integer;
BEGIN
  IF public.pdc_fitter_role_816() <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF p_idle_minutes IS NOT NULL AND p_idle_minutes NOT BETWEEN 2 AND 60 THEN RETURN jsonb_build_object('ok', false, 'error', 'idle_minutes_range'); END IF;
  SELECT count(*) INTO v_logins FROM public.pdc_fitter_logins_816 WHERE active;
  IF coalesce(p_required, false) AND v_logins = 0 THEN RETURN jsonb_build_object('ok', false, 'error', 'no_fitter_logins'); END IF;
  UPDATE pdc_ops.fitter_login_settings_816 SET required = coalesce(p_required, false), idle_minutes = coalesce(p_idle_minutes, idle_minutes),
         updated_at = clock_timestamp(), updated_by = v_email WHERE singleton;
  INSERT INTO public.pdc_fitter_login_events_816(event, device_user, actor_email, detail)
  VALUES (CASE WHEN p_required THEN 'required_on' ELSE 'required_off' END, auth.uid(), v_email, jsonb_build_object('idle_minutes', p_idle_minutes));
  RETURN jsonb_build_object('ok', true, 'required', coalesce(p_required, false), 'active_logins', v_logins);
END $f$;

DO $grants$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY['public.fitter_login_state_816()', 'public.fitter_sign_in_816(text,text)', 'public.fitter_session_816(text)',
    'public.fitter_change_pin_816(text,text,text)', 'public.fitter_sign_out_816(text)', 'public.admin_list_fitter_logins_816()',
    'public.admin_set_fitter_login_816(uuid,text,text)', 'public.admin_set_fitter_login_active_816(uuid,boolean)',
    'public.admin_create_fitter_logins_from_tune_816()',
    'public.admin_set_fitter_login_required_816(boolean,integer)'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
  END LOOP;
END $grants$;

-- The Fitters bay writes check the signed-in fitter (only while "required" is on).
DO $guards$
DECLARE
  f record; v_old text; v_new text; v_def text; v_pos integer; v_line text;
BEGIN
  FOR f IN SELECT * FROM (VALUES
      ('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure, 'p_technician_id'),
      ('public.handoff_operation_line_583(uuid,uuid,text,text,uuid)'::regprocedure, 'NULL'),
      ('public.undo_line_handoff_583(uuid,text,uuid)'::regprocedure, 'NULL'),
      ('public.set_line_later_627(uuid,text,text,text)'::regprocedure, 'NULL')) AS x(sig, tech) LOOP
    SELECT prosrc INTO v_old FROM pg_proc WHERE oid = f.sig;
    IF strpos(v_old, 'r816 (F455)') > 0 THEN RAISE EXCEPTION 'r816: % already guarded', f.sig; END IF;
    IF (SELECT prorettype FROM pg_proc WHERE oid = f.sig) <> 'jsonb'::regtype THEN RAISE EXCEPTION 'r816: % does not return jsonb', f.sig; END IF;
    v_pos := strpos(v_old, E'\nBEGIN\n');
    IF v_pos = 0 THEN RAISE EXCEPTION 'r816: no BEGIN line in %', f.sig; END IF;
    v_line := format(E' -- r816 (F455): a signed-in fitter does the work, under their own name.\n IF public.pdc_fitter_guard_816(%1$s) IS NOT NULL THEN RETURN jsonb_build_object(''ok'',false,''error'',public.pdc_fitter_guard_816(%1$s)); END IF;\n', f.tech);
    v_new := substr(v_old, 1, v_pos + 6) || v_line || substr(v_old, v_pos + 7);
    v_def := regexp_replace(pg_get_functiondef(f.sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
    IF (SELECT prosrc FROM pg_proc WHERE oid = f.sig) <> v_new THEN RAISE EXCEPTION 'r816: % readback differs', f.sig; END IF;
    UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
  END LOOP;
END $guards$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('fitter_logins_guarded_816', 'F455',
  'Fitters (r816): the four Fitters bay write RPCs check the signed-in fitter, the hook allows the sign-in RPCs, and no PIN is stored in plain text.',
  $chk$
SELECT (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
        AND proname IN ('fitter_job_command', 'handoff_operation_line_583', 'undo_line_handoff_583', 'set_line_later_627')
        AND strpos(prosrc, 'pdc_fitter_guard_816(') > 0) = 4
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure), 'rpc/fitter_sign_in_816') > 0
   AND NOT EXISTS (SELECT 1 FROM public.pdc_fitter_logins_816 WHERE pin_hash !~ '^\$2[abxy]\$')
   AND NOT has_table_privilege('authenticated', 'public.pdc_fitter_logins_816', 'SELECT')
 AS ok, 'fitter logins guarded' AS detail
$chk$, true, 604, 'r816'),
  ('fitter_pin_rules_816', 'F455',
  'Fitters (r816): a PIN is 4 to 6 digits and never all one digit or a run (1234, 4321); a temporary password may be initials then mechanic ID.',
  $chk$
SELECT public.pdc_fitter_pin_problem_816('1234') = 'pin_too_simple' AND public.pdc_fitter_pin_problem_816('0000') = 'pin_too_simple'
   AND public.pdc_fitter_pin_problem_816('987654') = 'pin_too_simple' AND public.pdc_fitter_pin_problem_816('12a4') = 'pin_format'
   AND public.pdc_fitter_pin_problem_816('123') = 'pin_format' AND public.pdc_fitter_pin_problem_816('2580') IS NULL
   AND public.pdc_fitter_pin_problem_816('MR2686') = 'pin_format' AND public.pdc_fitter_temp_problem_816('mr2686') IS NULL
   AND public.pdc_fitter_temp_problem_816('2345') IS NULL
   AND public.pdc_fitter_initials_816('Mudassar Rasheed') = 'MR' AND public.pdc_fitter_initials_816('Chelsea Rees # 2') = 'CR'
 AS ok, 'PIN rules hold' AS detail
$chk$, true, 605, 'r816');
