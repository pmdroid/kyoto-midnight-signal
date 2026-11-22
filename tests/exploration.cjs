const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
const output=process.env.KYOTO_TEST_OUTPUT || path.join(__dirname,'..','build','test-artifacts');fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--use-angle=swiftshader']});
 const context=await browser.newContext({viewport:{width:1280,height:800}});
 const page=await context.newPage();const errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 await page.goto('http://127.0.0.1:8765/?qa=1');
 await page.waitForFunction(()=>window.__kyoto?.menu==='title',{},{timeout:60000});
 await page.keyboard.press('Enter');await page.waitForFunction(()=>window.__kyoto?.menu==='');
 await page.waitForTimeout(700);
 const state=()=>page.evaluate(()=>__kyoto);
 const phase=async(n)=>page.waitForFunction(n=>__kyoto.phase===n,n,{timeout:15000});
 const key=async(k,ms=250)=>{await page.keyboard.press(k);await page.waitForTimeout(ms)};
 const snap=async(name)=>page.screenshot({path:path.join(output,name+'.png')});
 // Move with actual key input while the camera follows, then click a visible destination.
 async function walk(x,y){
  const deadline=Date.now()+24000;
  while(Date.now()<deadline){
   const s=await state();const dx=x-s.position[0],dy=y-s.position[1];
   if(Math.hypot(dx,dy)<14)return;
   const kx=Math.abs(dx)>8?(dx>0?'d':'a'):null,ky=Math.abs(dy)>8?(dy>0?'s':'w'):null;
   if(kx)await page.keyboard.down(kx);if(ky)await page.keyboard.down(ky);
   await page.waitForTimeout(Math.min(260,Math.max(65,Math.hypot(dx,dy)*7)));
   if(kx)await page.keyboard.up(kx);if(ky)await page.keyboard.up(ky);
   await page.waitForTimeout(70);
  }
  throw new Error('Walk stuck toward '+[x,y]+' '+JSON.stringify(await state()));
 }
 await snap('v2-start');
 const initial=await state();assert(initial.zoom>=2.6);assert(initial.room==='apartment');
 await walk(590,510);await key('e');await phase(1);await key('e');await phase(4);
 await key('e');await phase(5);await key('e');await phase(7);
 await walk(475,415);await key('q');await phase(9);await page.waitForTimeout(900);await key('e');await phase(10);
 await walk(474,396);await key('e');await phase(12);
 await walk(890,500);await walk(1195,600);await walk(1414,604);
 await key('e');await phase(13);
 const far=await state();assert(far.camera[0]-initial.camera[0]>500,'Camera follows into previously offscreen area');
 await snap('v2-door');
 await walk(1370,603);await key('e');await page.waitForFunction(()=>__kyoto.room==='hallway');await page.waitForTimeout(700);
 await snap('v2-hall');
 await walk(800,470);await walk(1346,463);await key('e');assert((await state()).room==='hallway');
 // Return home for the repair component. Doorways are bidirectional.
 await walk(800,470);await walk(237,444);await key('e');await page.waitForFunction(()=>__kyoto.room==='apartment');await page.waitForTimeout(600);
 await walk(1200,605);await walk(1230,450);await walk(1230,327);await walk(1275,320);await key('e');assert((await state()).cell);
 await snap('v2-workbench');
 await walk(1230,327);await walk(1230,450);await walk(1080,620);await walk(1060,850);await walk(1265,843);await key('e');assert((await state()).found.moon_home);
 await snap('v2-hidden-nook');
 // Reload in a far corner; room, discovery and component must persist.
 await page.waitForTimeout(1600);await page.reload();await page.waitForFunction(()=>window.__kyoto?.menu==='title',{},{timeout:60000});await key('Enter');await page.waitForFunction(()=>__kyoto.menu==='');
 assert((await state()).found.moon_home && (await state()).cell);
 await walk(1060,850);await walk(1060,620);await walk(1370,603);await key('e');await page.waitForFunction(()=>__kyoto.room==='hallway');await page.waitForTimeout(600);
 await walk(800,470);await walk(1152,445);await key('e');assert((await state()).flags.powered && !(await state()).cell);
 await walk(1440,550);await walk(1440,854);assert.equal((await state()).interaction,'Ask Kyoto');await key('q');await key('e');assert((await state()).found.moon_hall);
 await walk(1440,550);await walk(1346,463);await key('e');await page.waitForFunction(()=>__kyoto.room==='courtyard');await page.waitForTimeout(600);
 await snap('v2-courtyard');
 await walk(420,575);await walk(480,370);await key('e');assert((await state()).found.moon_garden);
 await walk(650,374);await walk(1040,378);await walk(1145,398);await key('e');await page.waitForFunction(()=>__kyoto.menu==='complete');
 assert((await state()).flags.greenhouse);
 await snap('v2-finale');
 await key('Enter');await page.waitForFunction(()=>__kyoto.menu==='');
 assert.deepEqual(errors,[]);
 console.log('PASS: real keyboard walkthrough, scrolling camera, all 3 rooms, bidirectional doors, repair, hidden sniff clue, persistent save/reload, 3 moon pieces, greenhouse, continued exploration');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
