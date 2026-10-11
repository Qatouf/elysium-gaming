BEGIN;
CREATE TEMP TABLE qa_results(feature text,status text,detail text);
DO $qa$
DECLARE d date;v record;n int=0;resource uuid;available bigint;
BEGIN
 FOR d IN SELECT timezone('Europe/Stockholm',now())::date+14+i FROM generate_series(0,6) i LOOP
  SELECT * INTO v FROM public.get_elysium_availability('pc',d,'16:00',60);IF v.total_resources<>20 THEN RAISE EXCEPTION 'PC resources mismatch';END IF;
  SELECT * INTO v FROM public.get_elysium_availability('ps5',d,'16:00',60);IF v.total_resources<>2 THEN RAISE EXCEPTION 'PS5 resources mismatch';END IF;
  BEGIN
   PERFORM public.get_elysium_availability('pc',d,'15:30',60);RAISE EXCEPTION 'before opening accepted';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%öppettider%' THEN RAISE;END IF;END;
  SELECT close_time INTO v FROM public.opening_hours WHERE day_of_week=extract(isodow from d)::int AND active;
  PERFORM public.get_elysium_availability('pc',d+1,v.close_time-interval '1 hour',60);
  BEGIN
   PERFORM public.get_elysium_availability('pc',d+1,v.close_time-interval '30 minutes',60);RAISE EXCEPTION 'after closing accepted';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%öppettider%' THEN RAISE;END IF;END;
  n=n+1;
 END LOOP;
 INSERT INTO qa_results VALUES('All weekly opening boundaries','GODKÄND',n||' operating days; opening, 30m before, exact closing and 30m after');
 d=timezone('Europe/Stockholm',now())::date+90;
 PERFORM public.get_elysium_availability('pc',d,'16:00',60);
 BEGIN PERFORM public.get_elysium_availability('pc',d+1,'16:00',60);RAISE EXCEPTION '91 days accepted';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%90 dagar%' THEN RAISE;END IF;END;
 INSERT INTO qa_results VALUES('90-day inclusive limit','GODKÄND','Day 90 accepted; day 91 rejected');
 d=timezone('Europe/Stockholm',now())::date+14;
 SELECT id INTO resource FROM public.resources WHERE type='pc' AND active LIMIT 1;
 INSERT INTO public.blocked_times(resource_id,blocked_date,start_time,end_time,reason) VALUES(resource,d+1,'00:00','00:30','QA rollback only');
 SELECT available_resources INTO available FROM public.get_elysium_availability('pc',d+1,'00:00',60);
 IF available<>19 THEN RAISE EXCEPTION 'overnight block ignored: %',available;END IF;
 SELECT available_resources INTO available FROM public.get_elysium_availability('pc',d,'23:30',60);
 IF available<>19 THEN RAISE EXCEPTION 'same-day block ignored';END IF;
 SELECT available_resources INTO available FROM public.get_elysium_availability('pc',d+1,'00:30',30);
 IF available<>20 THEN RAISE EXCEPTION 'adjacent block overlaps';END IF;
 INSERT INTO qa_results VALUES('Blocked station across midnight','GODKÄND','19 free during block; 20 free at adjacent end; rolled back');
END;$qa$;
SELECT * FROM qa_results;
ROLLBACK;
