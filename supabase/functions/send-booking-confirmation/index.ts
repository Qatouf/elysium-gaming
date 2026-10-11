import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
Deno.serve(async (req: Request) => {
  if(req.method!=="POST") return new Response("Method not allowed",{status:405});
  const key=Deno.env.get("RESEND_API_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!key || !service) return Response.json({error:"Missing server configuration"},{status:503});
  const bearer=req.headers.get("Authorization")??"";
  if(!bearer.startsWith("Bearer ")) return new Response("Unauthorized",{status:401});
  let bookingId:string;
  try {
    const body=await req.json();
    bookingId=body.booking_id ?? body.record?.id;
    if(typeof bookingId!=="string" || !/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(bookingId)) throw Error();
  }catch {return Response.json({error:"Invalid booking ID"},{status:400});}
  const db=createClient(Deno.env.get("SUPABASE_URL")!,service);
 const webhookToken=req.headers.get("X-Elysium-Webhook-Token")??"";
 const {data:trusted,error:trustError}=await db.rpc("verify_elysium_webhook_token",{p_token:webhookToken});
 if(trustError||trusted!==true)return new Response("Unauthorized",{status:401});
  const {data:b,error}=await db.from("bookings").select("id,booking_number,customer_name,customer_email,resource_type,booking_date,start_time,duration_minutes,quantity,total_price_sek,status").eq("id",bookingId).single();
  if(error||!b) return Response.json({error:"Not found"},{status:404});
  if(b.status!=="confirmed") return Response.json({skipped:true});
  const {data:claim,error:claimError}=await db.rpc("claim_elysium_confirmation",{p_booking_id:bookingId});
  if(claimError) return Response.json({error:"Unable to claim confirmation"},{status:500});
  if(!claim) return Response.json({skipped:"Already processed"});
  const duration=Number(b.duration_minutes);
  const variables={
    CUSTOMER_NAME:String(b.customer_name),
    BOOKING_NUMBER:String(b.booking_number),
    ACTIVITY:b.resource_type==="pc"?"PC Gaming":b.resource_type==="ps5"?"PlayStation 5":String(b.resource_type),
    BOOKING_DATE:String(b.booking_date),
    START_TIME:String(b.start_time).slice(0,5),
    DURATION:duration%60===0?`${duration/60} timmar`:`${duration} minuter`,
    QUANTITY:String(b.quantity),
    TOTAL_PRICE:`${b.total_price_sek} kr`
  };
  try{
    const result=await fetch("https://api.resend.com/emails",{
      method:"POST",
      headers:{"Authorization":`Bearer ${key}`,"Content-Type":"application/json","Idempotency-Key":`elysium-booking-${b.id}`},
      body:JSON.stringify({from:"Elysium Gaming Lounge <info@elysiumgaming.se>",to:[b.customer_email],reply_to:"info@elysiumgaming.se",template:{id:"2ea6a31a-21fb-4df5-b42c-fe4ce69e0d26",variables}})
    });
    const response=await result.json().catch(()=>({}));
    await db.from("booking_confirmation_emails").update({status:result.ok?"sent":"failed",last_error:result.ok?null:JSON.stringify(response).slice(0,1000),sent_at:result.ok?new Date().toISOString():null}).eq("booking_id",bookingId);
    if(!result.ok) return Response.json({error:"Resend rejected message"},{status:502});
    return Response.json({sent:true});
  }catch(e){
    await db.from("booking_confirmation_emails").update({status:"failed",last_error:String(e).slice(0,1000)}).eq("booking_id",bookingId);
    return Response.json({error:"Email service unavailable"},{status:502});
  }
});
