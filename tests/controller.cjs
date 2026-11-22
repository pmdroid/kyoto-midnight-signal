const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');const fs=require('node:fs');
const output=process.env.KYOTO_TEST_OUTPUT||path.join(__dirname,'..','build','test-artifacts');fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--use-angle=swiftshader']});
 const context=await browser.newContext({viewport:{width:1280,height:800}});
 await context.addInitScript(()=>{
  window.testPad={id:'Xbox 360 Controller (STANDARD GAMEPAD)',index:0,connected:true,mapping:'standard',timestamp:0,axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};
  Object.defineProperty(navigator,'getGamepads',{value:()=>{testPad.timestamp=performance.now();return [testPad.connected?testPad:null,null,null,null]}});
  window.padConnection=connected=>{testPad.connected=connected;const e=new Event(connected?'gamepadconnected':'gamepaddisconnected');Object.defineProperty(e,'gamepad',{value:testPad});dispatchEvent(e)};
 });
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const press=async(i)=>{await page.evaluate(i=>testPad.buttons[i]={pressed:true,touched:true,value:1},i);await page.waitForTimeout(180);await page.evaluate(i=>testPad.buttons[i]={pressed:false,touched:false,value:0},i);await page.waitForTimeout(220)};
 const state=()=>page.evaluate(()=>__kyoto);
 const phase=async(p)=>page.waitForFunction(p=>__kyoto.phase===p,p,{timeout:18000});
 async function walk(x,y){for(let i=0;i<100;i++){const s=await state();const dx=x-s.position[0],dy=y-s.position[1];if(Math.hypot(dx,dy)<13){await page.evaluate(()=>testPad.axes=[0,0,0,0]);return}await page.evaluate(([x,y])=>{testPad.axes=[x,y,0,0]},[Math.abs(dx)>7?Math.sign(dx):0,Math.abs(dy)>7?Math.sign(dy):0]);await page.waitForTimeout(130)}throw new Error('Gamepad movement stalled')}
 await page.goto('http://127.0.0.1:8765/?qa=1');await page.waitForFunction(()=>window.__kyoto?.menu==='title',{},{timeout:60000});await page.evaluate(()=>padConnection(true));await page.waitForTimeout(400);await press(0);await page.waitForFunction(()=>__kyoto.menu==='');
 await page.screenshot({path:path.join(output,'v2-final-preview.png')});
 const cam=(await state()).camera[0];await walk(590,510);assert((await state()).camera[0]>cam+20);
 await press(3);assert((await state()).pets===1);
 await press(0);await phase(1);await press(0);await phase(4);await press(0);await phase(5);await press(0);await phase(7);
 await walk(475,415);await press(2);await phase(9);await page.waitForTimeout(800);await press(0);await phase(10);
 await press(9);await page.waitForFunction(()=>__kyoto.menu==='pause');await press(0);await page.waitForFunction(()=>__kyoto.menu==='');
 const zoom=(await state()).zoom;await press(5);assert((await state()).zoom>zoom,'Shoulder button adjusts camera');
 await page.evaluate(()=>padConnection(false));await page.waitForFunction(()=>__kyoto.menu==='pause');await page.evaluate(()=>padConnection(true));await page.waitForTimeout(300);await press(0);await page.waitForFunction(()=>__kyoto.menu==='');
 await page.waitForTimeout(1500);await page.reload();await page.waitForFunction(()=>window.__kyoto?.menu==='title',{},{timeout:60000});await page.evaluate(()=>padConnection(true));await page.waitForTimeout(300);await press(0);await phase(10);assert((await state()).pets===1);assert((await state()).zoom>zoom);
 assert.deepEqual(errors,[]);console.log('PASS: gamepad menus, movement with follow camera, fetch, sniff, pet, pause, zoom, disconnect/reconnect and persistent save/reload');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
