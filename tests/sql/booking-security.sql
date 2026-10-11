BEGIN;
CREATE TEMP TABLE qa_results(feature text,status text,detail text);
DO $qa$
DECLARE b record;b2 record;d date;phone text;verified bool;
BEGIN
 d=timezone('Europe/Stockholm',now())::date+14;
 FOREACH phone IN ARRAY ARRAY['abcdefg','+++++++','123 abc 456'] LOOP
  BEGIN
   PERFORM public.create_elysium_booking('pc',d,'16:00',60,1,'QA isolated','qa-isolated@example.com',phone);RAISE EXCEPTION 'invalid phone accepted';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%telefonnumret%' THEN RAISE;END IF;END;
 END LOOP;
 INSERT INTO qa_results VALUES('Phone characters and digits','GODKÄND','3 invalid numbers rejected');
 SELECT * INTO b FROM public.create_elysium_booking('pc',d,'16:00',60,1,'QA isolated','qa-isolated@example.com','+46 (70) 000-00-00');
 SELECT * INTO b2 FROM public.create_elysium_booking('ps5',d,'16:00',60,1,'QA isolated','qa-isolated@example.com','0700000000');
 BEGIN
  INSERT INTO public.booking_resources(booking_id,resource_id,start_at,end_at,active)
  SELECT b2.booking_id,resource_id,start_at+interval '1 minute',end_at,true FROM public.booking_resources WHERE booking_id=b.booking_id LIMIT 1;
  RAISE EXCEPTION 'overlap constraint accepted duplicate';
 EXCEPTION WHEN exclusion_violation THEN NULL;END;
 INSERT INTO qa_results VALUES('Database exclusion constraint','GODKÄND','Direct overlapping allocation rejected');
 PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
 BEGIN PERFORM public.cancel_elysium_booking(b.booking_id);RAISE EXCEPTION 'anonymous cancellation accepted';
 EXCEPTION WHEN others THEN IF SQLERRM='anonymous cancellation accepted' THEN RAISE;END IF;END;
 IF has_function_privilege('anon','public.verify_elysium_webhook_token(text)','EXECUTE') OR has_function_privilege('authenticated','public.verify_elysium_webhook_token(text)','EXECUTE') THEN RAISE EXCEPTION 'webhook verification publicly callable';END IF;
 IF has_table_privilege('anon','public.bookings','SELECT') THEN RAISE EXCEPTION 'anonymous booking reads allowed';END IF;
 INSERT INTO qa_results VALUES('Public access restrictions','GODKÄND','Anonymous cancellation rejected; anonymous booking reads and token verifier denied');
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 IF public.verify_elysium_webhook_token(repeat('x',64)) THEN RAISE EXCEPTION 'wrong webhook token accepted';END IF;
 SELECT public.verify_elysium_webhook_token(decrypted_secret) INTO verified FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_token';
 IF verified IS DISTINCT FROM true THEN RAISE EXCEPTION 'internal webhook token rejected';END IF;
 INSERT INTO qa_results VALUES('Internal webhook authentication','GODKÄND','Valid internal token accepted; wrong token rejected; no token disclosed');
END;$qa$;
SELECT * FROM qa_results;
ROLLBACK;
