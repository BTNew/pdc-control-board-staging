-- STAGING ONLY. Preserve the canonical minute calendar while consuming each
-- unchanged interval once instead of scanning every elapsed minute.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.workshop_add_operational_minutes(timestamptz,integer)'::regprocedure)) <> 'b3c4cc68ca620419fcba35836ddd6606'
 THEN RAISE EXCEPTION 'Operational calendar definition changed; review before applying'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_add_operational_minutes(p_start timestamp with time zone, p_duration_minutes integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_limit timestamptz:=date_trunc('minute',p_start)+interval '90 days';
  v_settings jsonb;
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_cursor timestamptz:=date_trunc('minute',p_start);
  v_remaining integer:=p_duration_minutes;
  v_local timestamp;
  v_date date;
  v_clock time;
  v_day text;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
  v_boundaries integer[];
  v_boundary integer;
  v_span integer;
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes<0 then
    raise exception 'Operational minutes must be non-negative' using errcode='22023';
  end if;
  if p_duration_minutes=0 then return p_start; end if;

  select jsonb_object_agg(key,value) into v_settings
  from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
  begin
    v_start:=(v_settings->>'day_start_time')::time;
    v_end:=(v_settings->>'day_end_time')::time;
  exception when others then
    v_start:=null; v_end:=null;
  end;
  v_working_week:=v_settings->'working_week';
  v_closures:=v_settings->'closures';
  v_breaks:=v_settings->'break_windows';
  v_overtime:=v_settings->'overtime_windows';
  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;

  while v_remaining>0 and v_cursor<v_limit loop
    v_local:=v_cursor at time zone 'Australia/Perth';
    v_date:=v_local::date;
    v_day:=lower(to_char(v_local,'FMDay'));
    select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day)
      into v_workday;
    if not v_workday or exists(select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text) then
      v_cursor:=least((v_date+1)::timestamp at time zone 'Australia/Perth',v_limit);
      continue;
    end if;

    -- Availability can change only at a regular, overtime or break boundary.
    -- CEIL retains the old integer-minute comparisons for second-valued times.
    select array_agg(distinct n order by n) into v_boundaries from (
      select ceil(extract(epoch from v_start)/60)::integer n
      union all select ceil(extract(epoch from v_end)/60)::integer
      union all select 1440
      union all
      select ceil(extract(epoch from b.boundary)/60)::integer
      from jsonb_array_elements(v_overtime||v_breaks) w
      cross join lateral(values((w->>'start')::time),((w->>'end')::time)) b(boundary)
      where ((w ? 'date' and w->>'date'=v_date::text)
        or (not(w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in('global','working_day',v_day)))
    ) boundaries where n is not null;

    foreach v_boundary in array v_boundaries loop
      v_clock:=(v_cursor at time zone 'Australia/Perth')::time;
      v_span:=least(v_boundary-floor(extract(epoch from v_clock)/60)::integer,
        floor(extract(epoch from v_limit-v_cursor)/60)::integer);
      if v_span<=0 then continue; end if;
      v_regular:=v_clock>=v_start and v_clock<v_end;
      select exists(
        select 1 from jsonb_array_elements(v_overtime) w
        where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
          and ((w ? 'date' and w->>'date'=v_date::text)
            or (not(w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in('global','working_day',v_day)))
      ) into v_overtime_ok;
      select exists(
        select 1 from jsonb_array_elements(v_breaks) w
        where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
          and ((w ? 'date' and w->>'date'=v_date::text)
            or (not(w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in('global','working_day',v_day)))
      ) into v_break;
      if (v_regular or v_overtime_ok) and not v_break then
        if v_remaining<=v_span then return v_cursor+make_interval(mins=>v_remaining); end if;
        v_remaining:=v_remaining-v_span;
      end if;
      v_cursor:=v_cursor+make_interval(mins=>v_span);
      exit when v_cursor>=v_limit;
    end loop;
  end loop;
  raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
end $function$;
