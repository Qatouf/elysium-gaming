// Real deployed Supabase UMD SDK, fake transport only: no booking or email sent.
// Download pinned SDK to a temporary path; run with SUPABASE_SDK_PATH=/tmp/sdk.js.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(`${__dirname}/../booking.html`,'utf8');
const script=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]).join('\n').replace(/\n  init\(\);/,'');
const elements=new Map();class Element{constructor(){this.value='';this.textContent='';this.children=[];this.classList={add(){},remove(){}}}set innerHTML(v){this.html=v;this.children=[]}get innerHTML(){return this.html||''}appendChild(e){this.children.push(e)}addEventListener(){}focus(){}}
const el=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)};
const liveReadOnly=process.env.LIVE_READ_ONLY==='1';
let failed=false,creates=0;const requests=[];
const fakeFetch=async(url,options)=>{const endpoint=new URL(url).pathname;requests.push(endpoint);if(liveReadOnly){if(!endpoint.endsWith('/opening_hours')&&!endpoint.endsWith('/booking_packages')&&!endpoint.endsWith('/get_elysium_availability'))throw Error('Live write forbidden');return fetch(url,options);}if(failed)return Response.json({message:'fake unavailable'},{status:503});let data;
 if(endpoint.endsWith('/opening_hours'))data=Array.from({length:7},(_,i)=>({day_of_week:i+1,active:true,open_time:'16:00:00',close_time:i<4?'01:00:00':'03:00:00',next_day_close:true}));
 else if(endpoint.endsWith('/booking_packages'))data=[{resource_type:'pc',name:'1 timme',duration_minutes:60,price_sek:49,sort_order:1}];
 else if(endpoint.endsWith('/get_elysium_availability'))data=[{total_resources:20,available_resources:20}];
 else if(endpoint.endsWith('/create_elysium_booking')){creates++;data=[{booking_number:'SYNTHETIC',total_price_sek:49}];}
 else throw Error(`Unexpected SDK request: ${endpoint}`);
 return Response.json(data);
};
const ctx=vm.createContext({console:{log:console.log,error(){}},URL,fetch:fakeFetch,Headers,Request,Response,setTimeout,clearTimeout,AbortController,WebSocket,TextEncoder,TextDecoder,Intl,Date,document:{getElementById:el,querySelectorAll:()=>[],createElement:()=>new Element()}});
vm.runInContext(fs.readFileSync(process.env.SUPABASE_SDK_PATH,'utf8'),ctx);
const factory=ctx.supabase.createClient;ctx.supabase.createClient=(url,key)=>factory(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fakeFetch}});
vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);
(async()=>{
 assert.equal(run('typeof db.from("opening_hours").select("*").catch'),'undefined');
 await run('init()');assert.equal(el('packageGrid').children.length,liveReadOnly?3:1);assert.equal(el('message').textContent,'');assert(requests.some(x=>x.endsWith('/opening_hours')));assert(requests.some(x=>x.endsWith('/booking_packages')));
 el('bookingDate').value=run('addCalendarDays(bookingDate.min,14)');el('quantity').value='1';run('selectedDuration=60;selectedPackagePrice=49');await run('loadAvailableTimes()');assert(el('timeGrid').children.length>0);assert(el('timeGrid').children.some(e=>!e.disabled));
 if(liveReadOnly){console.log('PASS: real SDK + public production API: initialization, opening hours, 3 PC packages and availability; all writes forbidden');return;}
 el('customerName').value='QA isolated';el('customerEmail').value='qa-isolated@example.com';el('customerPhone').value='0700000000';run('selectedStartTime="16:00"');await run('createBooking()');assert.equal(creates,1);assert.equal(el('confirmedBookingNumber').textContent,'SYNTHETIC');assert.equal(el('bookButton').disabled,false);
 failed=true;await run('loadPackages()');assert(el('packageGrid').innerHTML.includes('Kunde inte hämta priser'));run('selectedDuration=60');await run('loadAvailableTimes()');assert.equal(run('loadingTimes'),false);assert(el('timeGrid').children.every(e=>e.disabled));
 console.log('PASS: real Supabase SDK then-only query builders: full initialization, packages, availability, synthetic booking, provider failures; transport fully isolated');
})().catch(e=>{console.error(e);process.exitCode=1});
