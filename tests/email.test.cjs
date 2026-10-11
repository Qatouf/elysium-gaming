// Executes the deployed handlers with fake database and fake Resend; no network.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const id='00000000-0000-0000-0000-000000000001';
async function test(slug){
 const source=fs.readFileSync(`${__dirname}/../supabase/functions/${slug}/index.ts`,'utf8').replace(/^import .*;\n/gm,'').replace('req: Request','req').replace('bookingId:string','bookingId').replace('get("SUPABASE_URL")!','get("SUPABASE_URL")');
 let handler,trusted=true,claim=true,networkError=false,ok=true,calls=0,lastBody,updates=[];
 const cancel=slug.endsWith('cancellation');
 const booking={id,booking_number:'SYNTHETIC',customer_name:'QA isolated',customer_email:'qa-isolated@example.com',resource_type:'pc',booking_date:'2026-10-17',start_time:'00:30:00',duration_minutes:60,quantity:2,total_price_sek:98,status:cancel?'cancelled':'confirmed'};
 const db={rpc:async(name)=>({data:name==='verify_elysium_webhook_token'?trusted:claim,error:null}),from(table){let update=false;const chain={select(){return chain},eq(){return chain},in(){return chain},update(v){updates.push(v);update=true;return chain},single:async()=>({data:table==='bookings'?booking:{status:claim?'pending':'sent'},error:null}),then(resolve){return Promise.resolve({data:update&&claim?[{booking_id:id}]:[],error:null}).then(resolve)}};return chain}};
 vm.runInNewContext(source,{Deno:{env:{get:()=> 'FAKE'},serve:f=>handler=f},createClient:()=>db,Request,Response,Date,fetch:async(url,opts)=>{calls++;lastBody=JSON.parse(opts.body);assert(opts.headers['Idempotency-Key'].includes(id));if(networkError)throw Error('fake outage');return Response.json({mock:true},{status:ok?200:503})}});
 const request=()=>new Request('https://isolated.invalid',{method:'POST',headers:{Authorization:'Bearer FAKE','X-Elysium-Webhook-Token':'FAKE'},body:JSON.stringify({booking_id:id})});
 trusted=false;assert.equal((await handler(request())).status,401);assert.equal(calls,0);
 trusted=true;claim=false;assert.equal((await handler(request())).status,200);assert.equal(calls,0);
 claim=true;assert.equal((await handler(request())).status,200);assert.equal(calls,1);assert.equal(lastBody.to[0],'qa-isolated@example.com');assert.equal(lastBody.template.variables.BOOKING_DATE,'2026-10-17');assert.equal(lastBody.template.variables.START_TIME,'00:30');assert.equal(updates.at(-1).status,'sent');
 ok=false;assert.equal((await handler(request())).status,502);assert.equal(updates.at(-1).status,'failed');
 networkError=true;assert.equal((await handler(request())).status,502);assert.equal(updates.at(-1).status,'failed');
 assert.equal((await handler(new Request('https://isolated.invalid'))).status,405);
 assert.equal((await handler(new Request('https://isolated.invalid',{method:'POST',headers:{Authorization:'Bearer FAKE'},body:'invalid'}))).status,400);
 console.log(`PASS: ${slug}: webhook authorization, idempotency, template data, success, provider/network failure, invalid request; no real email`);
}
(async()=>{await test('send-booking-confirmation');await test('send-booking-cancellation')})().catch(e=>{console.error(e);process.exitCode=1});
