BEGIN;
CREATE TEMP TABLE qa_results(feature text,status text,detail text);
DO $qa$
DECLARE pkg record;q int;b record;staff uuid;d date;tested int=0;queued int;
BEGIN
 SELECT user_id INTO staff FROM public.staff_profiles WHERE active LIMIT 1;
 d=timezone('Europe/Stockholm',now())::date+14;
 FOR pkg IN SELECT * FROM public.booking_packages WHERE active AND price_sek>0 AND resource_type IN ('pc','ps5') LOOP
  FOR q IN 1..CASE WHEN pkg.resource_type='pc' THEN 20 ELSE 2 END LOOP
   BEGIN
    SELECT * INTO b FROM public.create_elysium_booking(pkg.resource_type,d,'16:00',pkg.duration_minutes,q,'QA isolated','qa-isolated@example.com','0700000000');
    IF b.total_price_sek<>pkg.price_sek*q THEN RAISE EXCEPTION 'incorrect price';END IF;
    IF (SELECT count(*) FROM public.booking_resources WHERE booking_id=b.booking_id AND active)<>q THEN RAISE EXCEPTION 'station count mismatch';END IF;
    PERFORM set_config('request.jwt.claims',json_build_object('sub',staff,'role','authenticated')::text,true);
    PERFORM public.cancel_elysium_booking(b.booking_id);
    IF EXISTS(SELECT 1 FROM public.booking_resources WHERE booking_id=b.booking_id AND active) THEN RAISE EXCEPTION 'station not released';END IF;
    SELECT count(*) INTO queued FROM net.http_request_queue WHERE convert_from(body,'UTF8') LIKE '%'||b.booking_id||'%' AND length(headers->>'X-Elysium-Webhook-Token')=64;
    IF queued<>2 THEN RAISE EXCEPTION 'confirmation/cancellation webhook not authenticated: %',queued;END IF;
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='successful test rollback';
   EXCEPTION WHEN no_data_found THEN NULL;END;
   tested=tested+1;
  END LOOP;
 END LOOP;
 INSERT INTO qa_results VALUES('PC/PS5 package quantities, price, resources, cancellation, authenticated email queue','GODKÄND',tested||' combinations; all writes and queued HTTP requests rolled back');
END;$qa$;
SELECT * FROM qa_results;
ROLLBACK;
