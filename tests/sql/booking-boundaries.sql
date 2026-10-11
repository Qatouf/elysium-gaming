BEGIN;
CREATE TEMP TABLE qa_results(feature text,status text,detail text);
DO $qa$
DECLARE d date;v record;case_data jsonb;base jsonb;n integer=0;b record;c record;
BEGIN
 d=timezone('Europe/Stockholm',now())::date+14;
 base=jsonb_build_object('type','pc','date',d,'time','16:00','duration',60,'quantity',1,'name','QA isolated','email','qa-isolated@example.com','phone','0700000000');
 FOR case_data IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('type','invalid'),jsonb_build_object('type',null),jsonb_build_object('date',null),jsonb_build_object('date',d-30),jsonb_build_object('date',d+100),
  jsonb_build_object('time',null),jsonb_build_object('time','10:00'),jsonb_build_object('time','15:30'),jsonb_build_object('duration',null),jsonb_build_object('duration',0),jsonb_build_object('duration',61),
  jsonb_build_object('quantity',null),jsonb_build_object('quantity',0),jsonb_build_object('quantity',21),jsonb_build_object('type','ps5','quantity',3),
  jsonb_build_object('name',null),jsonb_build_object('name',' '),jsonb_build_object('name',repeat('a',101)),jsonb_build_object('email',null),jsonb_build_object('email','invalid'),jsonb_build_object('email','a@b'),
  jsonb_build_object('phone',null),jsonb_build_object('phone','123'),jsonb_build_object('phone',repeat('1',31))
 )) LOOP
  v=NULL;
  BEGIN
   case_data=base||case_data;
   PERFORM public.create_elysium_booking(case_data->>'type',(case_data->>'date')::date,(case_data->>'time')::time,(case_data->>'duration')::integer,(case_data->>'quantity')::integer,case_data->>'name',case_data->>'email',case_data->>'phone');
   RAISE EXCEPTION SQLSTATE 'P0003' USING MESSAGE='Invalid request unexpectedly accepted: '||case_data::text;
  EXCEPTION WHEN raise_exception THEN n=n+1;
  END;
 END LOOP;
 INSERT INTO qa_results VALUES('Invalid inputs','GODKÄND',n||' rejected cases');
 -- A future Friday, ending Saturday 03:00.
 d=d+((5-extract(isodow FROM d)::integer+7)%7);
 BEGIN
  SELECT * INTO b FROM public.create_elysium_booking('pc',d,'23:00',180,20,'QA isolated','qa-isolated@example.com','0700000000');
  SELECT available_resources INTO n FROM public.get_elysium_availability('pc',d+1,'00:30',60);
  IF n<>0 THEN RAISE EXCEPTION 'Overnight capacity failed'; END IF;
  BEGIN
   PERFORM public.create_elysium_booking('pc',d+1,'00:30',60,1,'QA isolated','qa-isolated@example.com','0700000000');
   RAISE EXCEPTION SQLSTATE 'P0003' USING MESSAGE='Overlap accepted';
  EXCEPTION WHEN raise_exception THEN IF sqlerrm NOT LIKE '%inte tillräckligt%' THEN RAISE; END IF; END;
  SELECT available_resources INTO n FROM public.get_elysium_availability('pc',d+1,'02:00',60);
  IF n<>20 THEN RAISE EXCEPTION 'Adjacent interval unavailable'; END IF;
  SELECT * INTO c FROM public.create_elysium_booking('ps5',d+1,'02:00',60,2,'QA isolated','qa-isolated@example.com','0700000000');
  IF NOT EXISTS(SELECT 1 FROM public.bookings WHERE id=c.booking_id AND timezone('Europe/Stockholm',end_at)::time='03:00') THEN RAISE EXCEPTION 'Closing boundary failed';END IF;
  RAISE EXCEPTION SQLSTATE 'P0002' USING MESSAGE='rollback';
 EXCEPTION WHEN no_data_found THEN NULL;
 END;
 INSERT INTO qa_results VALUES('Overnight and overlapping capacity','GODKÄND','20 PCs full across midnight; extra request denied; adjacent slots free; PS5 ends exactly 03:00');
 BEGIN
  PERFORM public.get_elysium_availability('pc',d+1,'02:30',60);
  RAISE EXCEPTION SQLSTATE 'P0003' USING MESSAGE='After closing accepted';
 EXCEPTION WHEN raise_exception THEN IF sqlerrm NOT LIKE '%öppettider%' THEN RAISE;END IF;END;
 INSERT INTO qa_results VALUES('After closing','GODKÄND','02:30+60 on Saturday rejected');
END $qa$;
SELECT * FROM qa_results;
ROLLBACK;
