CREATE OR REPLACE FUNCTION public.get_elysium_availability(p_resource_type text,p_booking_date date,p_start_time time,p_duration_minutes integer)
RETURNS TABLE(total_resources bigint,available_resources bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
 v_start timestamptz; v_end timestamptz; v_open time; v_close time;
 v_next_day boolean; v_operating_date date; v_open_at timestamptz; v_close_at timestamptz;
BEGIN
 IF p_resource_type IS NULL OR p_resource_type NOT IN ('pc','ps5') THEN RAISE EXCEPTION 'Ogiltig bokningstyp.'; END IF;
 IF p_booking_date IS NULL OR p_start_time IS NULL OR p_duration_minutes IS NULL OR p_duration_minutes<=0 THEN RAISE EXCEPTION 'Ogiltigt datum, starttid eller speltid.'; END IF;
 IF p_booking_date>timezone('Europe/Stockholm',now())::date+90 THEN RAISE EXCEPTION 'Du kan boka högst 90 dagar framåt.'; END IF;
 IF p_booking_date<timezone('Europe/Stockholm',now())::date THEN RAISE EXCEPTION 'Datumet har passerat.'; END IF;
 v_start=(p_booking_date::timestamp+p_start_time) AT TIME ZONE 'Europe/Stockholm';
 v_end=v_start+make_interval(mins=>p_duration_minutes);
 IF v_start<=now() THEN RAISE EXCEPTION 'Starttiden har passerat.'; END IF;
 v_operating_date=p_booking_date;
 SELECT open_time,close_time,next_day_close INTO v_open,v_close,v_next_day
 FROM public.opening_hours WHERE day_of_week=extract(isodow FROM v_operating_date)::integer AND active;
 -- Early calendar-day starts belong to the preceding day's overnight window.
 IF NOT FOUND OR p_start_time<v_open THEN
  v_operating_date=p_booking_date-1;
  SELECT open_time,close_time,next_day_close INTO v_open,v_close,v_next_day
  FROM public.opening_hours WHERE day_of_week=extract(isodow FROM v_operating_date)::integer AND active AND next_day_close;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bokningen ligger utanför Elysiums öppettider.'; END IF;
 END IF;
 v_open_at=(v_operating_date::timestamp+v_open) AT TIME ZONE 'Europe/Stockholm';
 v_close_at=((v_operating_date+CASE WHEN v_next_day THEN 1 ELSE 0 END)::timestamp+v_close) AT TIME ZONE 'Europe/Stockholm';
 IF v_start<v_open_at OR v_end>v_close_at THEN RAISE EXCEPTION 'Bokningen ligger utanför Elysiums öppettider.'; END IF;
 RETURN QUERY SELECT count(*)::bigint,count(*) FILTER(WHERE
  NOT EXISTS(SELECT 1 FROM public.booking_resources br WHERE br.resource_id=r.id AND br.active AND tstzrange(br.start_at,br.end_at,'[)')&&tstzrange(v_start,v_end,'[)'))
  AND NOT EXISTS(SELECT 1 FROM public.blocked_times bt WHERE bt.resource_id=r.id AND
   tstzrange((bt.blocked_date::timestamp+bt.start_time) AT TIME ZONE 'Europe/Stockholm',
    ((bt.blocked_date+CASE WHEN bt.end_time<=bt.start_time THEN 1 ELSE 0 END)::timestamp+bt.end_time) AT TIME ZONE 'Europe/Stockholm','[)')&&tstzrange(v_start,v_end,'[)'))
 )::bigint FROM public.resources r WHERE r.type=p_resource_type AND r.active;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_elysium_booking(p_resource_type text, p_booking_date date, p_start_time time without time zone, p_duration_minutes integer, p_quantity integer, p_customer_name text, p_customer_email text, p_customer_phone text)
 RETURNS TABLE(booking_id uuid, booking_number text, total_price_sek integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare

    v_booking_id uuid;

    v_booking_number text;

    v_start timestamptz;
    v_end timestamptz;

    v_end_local timestamp;

    v_price integer;
    v_total integer;

    v_available bigint;

    v_resource record;

    v_counter integer := 0;

begin
    if p_resource_type is null or p_booking_date is null or p_start_time is null
       or p_duration_minutes is null or p_quantity is null or p_quantity<1
       or p_customer_name is null or p_customer_email is null or p_customer_phone is null then
        raise exception 'Alla bokningsuppgifter måste vara ifyllda.';
    end if;
    -- Serialize allocations for each type; retain exclusion constraint as final protection.
    perform pg_advisory_xact_lock(hashtextextended('elysium-booking-'||p_resource_type,0));


    -- -----------------------------------------
    -- Grundkontroller
    -- -----------------------------------------

    if p_resource_type not in ('pc', 'ps5') then

        raise exception
        'Ogiltig bokningstyp.';

    end if;


    if p_quantity < 1 then

        raise exception
        'Välj minst en plats.';

    end if;


    if p_resource_type = 'pc'
       and p_quantity > 20 then

        raise exception
        'Max 20 datorer kan bokas.';

    end if;


    if p_resource_type = 'ps5'
       and p_quantity > 2 then

        raise exception
        'Max 2 PS5-zoner kan bokas.';

    end if;


    -- -----------------------------------------
    -- Kundnamn
    -- -----------------------------------------

    p_customer_name :=
        trim(p_customer_name);


    if length(p_customer_name) < 2
       or length(p_customer_name) > 100 then

        raise exception
        'Kontrollera kundens namn.';

    end if;


    -- -----------------------------------------
    -- E-post
    -- -----------------------------------------

    p_customer_email :=
        lower(trim(p_customer_email));


    if length(p_customer_email) > 150
       or p_customer_email !~
       '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    then

        raise exception
        'Kontrollera e-postadressen.';

    end if;


    -- -----------------------------------------
    -- Telefonnummer
    -- -----------------------------------------

    p_customer_phone :=
        trim(p_customer_phone);


    if length(p_customer_phone) < 7
       or length(p_customer_phone) > 30
       or p_customer_phone !~ '^[+0-9 ()-]+$'
       or length(regexp_replace(p_customer_phone,'[^0-9]','','g')) < 7 then

        raise exception
        'Kontrollera telefonnumret.';

    end if;


    -- -----------------------------------------
    -- Kontrollera paket och pris
    -- -----------------------------------------

    select bp.price_sek

    into v_price

    from public.booking_packages bp

    where bp.resource_type =
          p_resource_type

      and bp.duration_minutes =
          p_duration_minutes

      and bp.active = true

    limit 1;


    if v_price is null then

        raise exception
        'Det valda bokningspaketet finns inte.';

    end if;


    -- PS5 står just nu på 0 kr.
    -- Vi låter inte ett sådant paket gå live av misstag.

    if v_price <= 0 then

        raise exception
        'Priset för denna bokning är inte aktiverat ännu.';

    end if;


    -- -----------------------------------------
    -- Kontrollera öppettider och tillgänglighet
    -- genom vår availability-funktion
    -- -----------------------------------------

    select a.available_resources

    into v_available

    from public.get_elysium_availability(

        p_resource_type,
        p_booking_date,
        p_start_time,
        p_duration_minutes

    ) a;


    if v_available < p_quantity then

        raise exception
        'Det finns inte tillräckligt många lediga platser.';

    end if;


    -- -----------------------------------------
    -- Skapa riktiga tider
    -- -----------------------------------------

    v_start :=
        (
            p_booking_date::timestamp
            + p_start_time
        )
        at time zone 'Europe/Stockholm';


    v_end :=
        v_start
        + make_interval(
            mins => p_duration_minutes
        );


    v_end_local :=
        timezone(
            'Europe/Stockholm',
            v_end
        );


    -- -----------------------------------------
    -- Pris
    -- -----------------------------------------

    v_total :=
        v_price * p_quantity;


    -- -----------------------------------------
    -- Bokningsnummer
    --
    -- Exempel:
    -- ELY-261006-A1B2C3
    -- -----------------------------------------

    v_booking_number :=
        'ELY-' ||

        to_char(
            timezone(
                'Europe/Stockholm',
                now()
            ),
            'YYMMDD'
        )

        || '-' ||

        upper(
            substr(
                replace(
                    gen_random_uuid()::text,
                    '-',
                    ''
                ),
                1,
                6
            )
        );


    -- -----------------------------------------
    -- Skapa huvudbokningen
    -- -----------------------------------------

    insert into public.bookings (

        booking_number,

        customer_name,
        customer_email,
        customer_phone,

        resource_type,

        booking_date,

        start_time,
        end_time,

        start_at,
        end_at,

        duration_minutes,
        quantity,

        total_price_sek,

        status,
        payment_status

    )

    values (

        v_booking_number,

        p_customer_name,
        p_customer_email,
        p_customer_phone,

        p_resource_type,

        p_booking_date,

        p_start_time,
        v_end_local::time,

        v_start,
        v_end,

        p_duration_minutes,
        p_quantity,

        v_total,

        'confirmed',
        'unpaid'

    )

    returning id
    into v_booking_id;


    -- -----------------------------------------
    -- Välj automatiskt lediga resurser
    --
    -- FOR UPDATE hjälper vid samtidiga bokningar.
    -- Databasens exclusion constraint är sista
    -- skyddet mot dubbelbokning.
    -- -----------------------------------------

    for v_resource in

        select
            r.id,
            r.code

        from public.resources r

        where r.type =
              p_resource_type

          and r.active = true

          and not exists (

              select 1

              from public.booking_resources br

              where br.resource_id = r.id

                and br.active = true

                and tstzrange(
                    br.start_at,
                    br.end_at,
                    '[)'
                )
                &&
                tstzrange(
                    v_start,
                    v_end,
                    '[)'
                )
          )

          and not exists (

              select 1

              from public.blocked_times bt

              where bt.resource_id = r.id

                and tstzrange(

                    (
                        bt.blocked_date::timestamp
                        + bt.start_time
                    )
                    at time zone
                    'Europe/Stockholm',

                    (
                        (bt.blocked_date + case when bt.end_time <= bt.start_time then 1 else 0 end)::timestamp
                        + bt.end_time
                    )
                    at time zone
                    'Europe/Stockholm',

                    '[)'
                )

                &&

                tstzrange(
                    v_start,
                    v_end,
                    '[)'
                )
          )

        order by r.code

        for update

    loop

        exit when
            v_counter >= p_quantity;


        insert into public.booking_resources (

            booking_id,
            resource_id,

            start_at,
            end_at,

            active

        )

        values (

            v_booking_id,
            v_resource.id,

            v_start,
            v_end,

            true

        );


        v_counter :=
            v_counter + 1;

    end loop;


    -- -----------------------------------------
    -- Extra säkerhetskontroll
    -- -----------------------------------------

    if v_counter <> p_quantity then

        raise exception
        'Platserna hann bli bokade. Försök igen.';

    end if;


    -- -----------------------------------------
    -- Returnera bokningen
    -- -----------------------------------------

    return query

    select

        v_booking_id,
        v_booking_number,
        v_total;

end;
$function$

