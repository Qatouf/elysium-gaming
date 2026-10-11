revoke update on public.bookings from authenticated;
grant update (status) on public.bookings to authenticated;
create or replace function public.guard_elysium_direct_status_updates()
returns trigger language plpgsql set search_path='' as $$
begin
 if current_user = 'authenticated' and new.status is distinct from old.status and new.status <> 'completed' then
   raise exception 'Use the authorized booking RPC to change this status';
 end if;
 return new;
end; $$;
create trigger guard_elysium_direct_status_updates before update of status on public.bookings
for each row execute function public.guard_elysium_direct_status_updates();
revoke execute on function public.notify_elysium_booking_confirmation() from public,anon,authenticated;
revoke execute on function public.notify_elysium_booking_cancellation() from public,anon,authenticated;
