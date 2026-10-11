DO $migration$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM vault.secrets WHERE name='elysium_booking_webhook_token') THEN
  PERFORM vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'elysium_booking_webhook_token','Internal booking email webhook authentication');
 END IF;
END;$migration$;
CREATE OR REPLACE FUNCTION public.verify_elysium_webhook_token(p_token text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public,vault AS $function$
DECLARE expected text;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN RETURN false;END IF;
 IF p_token IS NULL OR length(p_token)<>64 THEN RETURN false;END IF;
 SELECT decrypted_secret INTO expected FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_token' LIMIT 1;
 RETURN expected IS NOT NULL AND expected=p_token;
END;$function$;
REVOKE ALL ON FUNCTION public.verify_elysium_webhook_token(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.verify_elysium_webhook_token(text) TO service_role;
CREATE OR REPLACE FUNCTION public.notify_elysium_booking_confirmation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public,extensions,vault AS $function$
DECLARE jwt text;token text;
BEGIN
 IF new.status='confirmed' THEN
  SELECT decrypted_secret INTO jwt FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_anon_jwt' LIMIT 1;
  SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_token' LIMIT 1;
  IF jwt IS NULL OR token IS NULL THEN RAISE WARNING 'Missing booking webhook configuration';
  ELSE PERFORM net.http_post(url:='https://jbwebwdockhgivltgjdu.supabase.co/functions/v1/send-booking-confirmation',headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||jwt,'X-Elysium-Webhook-Token',token),body:=jsonb_build_object('booking_id',new.id),timeout_milliseconds:=10000);END IF;
 END IF;RETURN new;
END;$function$;
CREATE OR REPLACE FUNCTION public.notify_elysium_booking_cancellation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public,extensions,vault AS $function$
DECLARE jwt text;token text;
BEGIN
 IF new.status='cancelled' AND old.status IS DISTINCT FROM 'cancelled' THEN
  INSERT INTO public.booking_cancellation_emails(booking_id) VALUES(new.id) ON CONFLICT(booking_id) DO NOTHING;
  SELECT decrypted_secret INTO jwt FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_anon_jwt' LIMIT 1;
  SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE name='elysium_booking_webhook_token' LIMIT 1;
  IF jwt IS NULL OR token IS NULL THEN RAISE WARNING 'Missing booking webhook configuration';
  ELSE PERFORM net.http_post(url:='https://jbwebwdockhgivltgjdu.supabase.co/functions/v1/send-booking-cancellation',headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||jwt,'X-Elysium-Webhook-Token',token),body:=jsonb_build_object('booking_id',new.id),timeout_milliseconds:=10000);END IF;
 END IF;RETURN new;
END;$function$;
REVOKE ALL ON FUNCTION public.notify_elysium_booking_confirmation() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.notify_elysium_booking_cancellation() FROM PUBLIC,anon,authenticated;
