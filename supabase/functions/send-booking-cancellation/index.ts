import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
Deno.serve(async (req: Request) => {
 if (req.method !== "POST") return new Response("Method not allowed",{status:405});
 const key=Deno.env.get("RESEND_API_KEY"), service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!key||!service) return Response.json({error:"Missing server configuration"},{status:503});
 if(!(req.headers.get("Authorization")??"").startsWith("Bearer ")) return new Response("Unauthorized",{status:401});
 let bookingId:string;
 try {const body=await req.json(); bookingId=body.booking_id; if(typeof bookingId!=="string"||!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(bookingId)) throw Error();}catch{return Response.json({error:"Invalid booking ID"},{status:400});}
 const db=createClient(Deno.env.get("SUPABASE_URL")!,service);
 const webhookToken=req.headers.get("X-Elysium-Webhook-Token")??"";
 const {data:trusted,error:trustError}=await db.rpc("verify_elysium_webhook_token",{p_token:webhookToken});
 if(trustError||trusted!==true)return new Response("Unauthorized",{status:401});
 const {data:b,error}=await db.from("bookings").select("id,booking_number,customer_name,customer_email,resource_type,booking_date,start_time,quantity,status").eq("id",bookingId).single();
 if(error||!b) return Response.json({error:"Not found"},{status:404});
 if(b.status!=="cancelled") return Response.json({skipped:true});
 const {data:queue,error:qe}=await db.from("booking_cancellation_emails").select("status").eq("booking_id",bookingId).single();
 if(qe||!queue) return Response.json({error:"No cancellation event"},{status:404});
 if(queue.status==="sent"||queue.status==="processing") return Response.json({skipped:"Already processed"});
 const {data:claimed,error:ce}=await db.from("booking_cancellation_emails").update({status:"processing",last_error:null}).eq("booking_id",bookingId).in("status",["pending","failed"]).select("booking_id");
 if(ce) return Response.json({error:"Unable to claim notification"},{status:500});
 if(!claimed?.length) return Response.json({skipped:"Already claimed"});
 const variables={CUSTOMER_NAME:String(b.customer_name),BOOKING_NUMBER:String(b.booking_number),ACTIVITY:b.resource_type==="pc"?"PC Gaming":b.resource_type==="ps5"?"PlayStation 5":String(b.resource_type),BOOKING_DATE:String(b.booking_date),START_TIME:String(b.start_time).slice(0,5),QUANTITY:String(b.quantity)};
 try{
 const result=await fetch("https://api.resend.com/emails",{method:"POST",headers:{"Authorization":`Bearer ${key}`,"Content-Type":"application/json","Idempotency-Key":`elysium-cancellation-${b.id}`},body:JSON.stringify({from:"Elysium Gaming Lounge <info@elysiumgaming.se>",to:[b.customer_email],reply_to:"info@elysiumgaming.se",template:{id:"c22d205e-b1db-4cf9-9c66-3701522b4857",variables}})});
 const response=await result.json().catch(()=>({}));
 await db.from("booking_cancellation_emails").update({status:result.ok?"sent":"failed",sent_at:result.ok?new Date().toISOString():null,last_error:result.ok?null:JSON.stringify(response).slice(0,1000)}).eq("booking_id",bookingId);
 return result.ok?Response.json({sent:true}):Response.json({error:"Resend rejected message"},{status:502});
 }catch(e){await db.from("booking_cancellation_emails").update({status:"failed",last_error:String(e).slice(0,1000)}).eq("booking_id",bookingId);return Response.json({error:"Email service unavailable"},{status:502});}
});
