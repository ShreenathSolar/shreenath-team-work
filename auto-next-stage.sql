-- Shreenath Team Work: move a customer to the next stage automatically.
-- Paste this whole text in Supabase > SQL Editor > New query, then press Run. Safe to run more than once.

create or replace function public._stage_idx(w text) returns int language sql immutable as $$
  select case w
    when 'Site survey' then 1
    when 'Material shifting' then 2
    when 'Structure erection' then 3
    when 'Panel & inverter installation' then 4
    when 'Panel installation' then 4
    when 'Inverter installation' then 4
    when 'Wiring' then 5
    when 'Earthing' then 6
    when 'Lightning arrestor (LA)' then 7
    when 'Meter / net-metering' then 8
    when 'Testing & commissioning' then 9
    when 'Cleaning & finishing' then 10
    else null end
$$;

create or replace function public._stage_name(i int) returns text language sql immutable as $$
  select (array['Site survey','Material shifting','Structure erection','Panel & inverter installation','Wiring','Earthing','Lightning arrestor (LA)','Meter / net-metering','Testing & commissioning','Cleaning & finishing'])[i]
$$;

CREATE OR REPLACE FUNCTION public.update_progress(p_token uuid, p_task_id uuid, p_status text, p_progress integer, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.members; t public.tasks; prog int; idx int;
begin
  m := public._me(p_token);
  select * into t from public.tasks where id = p_task_id;
  if t.id is null then raise exception 'Task not found'; end if;
  if m.role <> 'admin' and t.assigned_to is distinct from m.id then raise exception 'NOT_ALLOWED'; end if;
  if p_status not in ('todo','in_progress','done','incomplete') then raise exception 'Bad status'; end if;
  prog := case when p_status = 'done' then 100 else greatest(0, least(100, coalesce(p_progress, t.progress))) end;
  update public.tasks set status = p_status, progress = prog, note = coalesce(nullif(p_note,''), note), updated_at = now()
   where id = p_task_id;
  insert into public.task_updates(task_id, member_id, status, progress, note)
   values (p_task_id, m.id, p_status, prog, p_note);

  -- when a stage becomes done, add the next stage for the same customer (if it is not there yet)
  if p_status = 'done' and t.status is distinct from 'done' then
    idx := public._stage_idx(t.work_type);
    if idx is not null and idx < 10 then
      if not exists (select 1 from public.tasks x where x.site_id = t.site_id and public._stage_idx(x.work_type) = idx + 1) then
        insert into public.tasks(site_id, assigned_to, work_type, details, work_date)
        values (t.site_id, null, public._stage_name(idx + 1), '', (now() at time zone 'Asia/Kolkata')::date);
      end if;
    end if;
  end if;
end $function$;
