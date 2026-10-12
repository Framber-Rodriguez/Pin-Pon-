/* PIN-PON online matchmaking — Framber Rodriguez. */
document.addEventListener('DOMContentLoaded', () => {
 const $=id=>document.getElementById(id), tr=text=>window.PongI18n?.translate(text)||text;
 const screen=document.createElement('section');screen.id='matchmaker-screen';screen.hidden=true;
 screen.setAttribute('aria-label','Online 1v1');
 screen.innerHTML=`<div class="mm-shell"><header class="mm-header"><span class="eyebrow">PIN-PON</span><h1>ONLINE 1v1</h1><p>Classic online · First to 15 points</p></header>
 <div id="mm-lobby"><div class="mm-server"><label for="mm-server">Server</label><select id="mm-server"><option value="arena-1">Server 1</option><option value="arena-2">Server 2</option><option value="arena-3">Server 3</option></select></div>
 <p>Only players on the same server can meet.</p><p id="mm-auth-note"></p><button id="mm-signin">Sign in</button>
 <div class="mm-actions"><button id="mm-find" class="menu-action">FIND MATCH</button><button id="mm-create">CREATE ROOM</button></div>
 <form id="mm-room-form"><label for="mm-room-code">Room code</label><input id="mm-room-code" maxlength="6" autocomplete="off" autocapitalize="characters" pattern="[A-Fa-f0-9]{6}" required><button id="mm-room-join" type="submit">JOIN ROOM</button></form>
 <p id="mm-status" role="status" aria-live="polite"></p><p id="mm-room-share" data-no-translate></p><button id="mm-cancel" hidden>CANCEL SEARCH</button></div>
 <div id="mm-game" hidden><div class="mm-score"><span id="mm-name1" data-no-translate></span><strong id="mm-score" data-no-translate>0 — 0</strong><span id="mm-name2" data-no-translate></span></div><p id="mm-your-side"></p>
 <div class="mm-court-wrap"><canvas id="mm-canvas" width="900" height="500" tabindex="0" aria-label="Online court"></canvas><div id="mm-result" hidden><h2 id="mm-outcome"></h2><p id="mm-finish-note"></p><button id="mm-rematch"></button><p id="mm-rematch-note" role="status"></p><button id="mm-new-search">BACK TO LOBBY</button></div></div>
 <p id="mm-network" role="status"></p><p>Arrow keys or W / S to move · Hold and drag for mouse control · Drag on touchscreens</p><button id="mm-leave">LEAVE MATCH</button></div>
 <button id="mm-back">Main Menu</button></div>`;
 document.body.appendChild(screen);
 const canvas=$('mm-canvas'),ctx=canvas.getContext('2d');
 let active=false,queue=false,match=null,timer=null,generation=0,flight=null,paintId=null;
 let keys=new Set(),target=null,pointer=null,previous=null,latest=null,receivedAt=0,blendMs=100,lastReceivedAt=0,lastSeq=-1;
 let failures=0,authReturn=false,leaving=false;
 const server=$('mm-server');try{server.value=localStorage.getItem('pong-online-server')||'arena-1';}catch(_){}
 function authenticated(){return !!window.PongOnline?.userId;}
 function client(){return window.PongOnline?.client;}
 function text(id,value){if($(id).textContent!==value)$(id).textContent=value;}
 function authUI(){
  const yes=authenticated();$('mm-signin').hidden=yes;
  text('mm-auth-note',yes?'Sign in to save your results':'Sign in to find an opponent');
  for(const id of ['mm-find','mm-create','mm-room-join'])$(id).disabled=!yes||queue||!!match||leaving;
  server.disabled=queue||!!match||leaving;$('mm-room-code').disabled=queue||!!match||leaving;
 }
 function clearInput(){keys.clear();target=null;if(pointer&&canvas.hasPointerCapture(pointer.id))canvas.releasePointerCapture(pointer.id);pointer=null;}
 function direction(){return (keys.has('arrowdown')||keys.has('s')?1:0)-(keys.has('arrowup')||keys.has('w')?1:0);}
 function stopPoll(){clearTimeout(timer);timer=null;}
 function schedule(ms){stopPoll();if(active&&(queue||match))timer=setTimeout(poll,ms);}
 async function rpc(name,args){const c=client();if(!c||!authenticated())throw Error('Verified sign-in required');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
 function errorMessage(error){const msg=error.message||'';return msg.includes('Room not found')?'Room not found':msg.includes('Rematch unavailable')?'Rematch unavailable':msg.includes('Verified sign-in')?'Sign in to find an opponent':'Connection interrupted. Trying to reconnect…';}
 function lobby(){
  queue=false;match=null;previous=latest=null;lastSeq=-1;clearInput();stopPoll();
  $('mm-lobby').hidden=false;$('mm-game').hidden=true;$('mm-cancel').hidden=true;$('mm-result').hidden=true;
  text('mm-room-share','');text('mm-status','');text('mm-rematch-note','');text('mm-network','');authUI();
 }
 function apply(data){
  if(data.kind==='idle'){lobby();text('mm-status','Search expired. Try again.');return;}
  if(data.kind==='waiting'){
   queue=true;match=null;$('mm-cancel').hidden=false;
   text('mm-status',data.room?'Waiting for your friend…':'Searching for an opponent…');
   text('mm-room-share',data.room?tr('Server')+' '+server.selectedOptions[0].text.replace(/[^0-9]/g,'')+' · '+data.room:'');authUI();return;
  }
  if(data.kind!=='match')throw Error('Invalid server response');
  const newMatch=match?.id!==data.id;
  if(newMatch){clearInput();lastSeq=-1;previous=latest=null;failures=0;}
  match=data;queue=false;$('mm-lobby').hidden=true;$('mm-game').hidden=false;$('mm-cancel').hidden=true;
  text('mm-name1',data.names[0]);text('mm-name2',data.names[1]);text('mm-score',data.state.ls+' — '+data.state.rs);
  text('mm-your-side',data.side==='left'?'You control the left paddle':'You control the right paddle');
  if(data.state.seq>=lastSeq){
   const now=performance.now();previous=latest||data.state;latest=data.state;blendMs=Math.max(40,Math.min(250,now-lastReceivedAt||100));receivedAt=now;lastReceivedAt=now;lastSeq=data.state.seq;
  }
  const ended=data.status!=='playing';$('mm-result').hidden=!ended;
  if(ended){
   clearInput();const won=data.winner===data.side;
   text('mm-outcome',data.winner?(won?'YOU WIN':'YOU LOSE'):'MATCH ENDED');
   text('mm-finish-note',data.reason==='timeout'?'Opponent disconnected':data.reason==='left'?'Opponent left the match':'First to 15 points');
   text('mm-rematch',won?'WIN AGAIN':'VENGEANCE');$('mm-rematch').hidden=!data.winner;
   $('mm-rematch').disabled=data.mineRequested||!data.canRematch;
   text('mm-rematch-note',!data.canRematch?'Rematch unavailable':data.mineRequested?'Waiting for your opponent to accept…':data.peerRequested?'Your opponent requested a rematch':'Both players must accept the rematch');
  }else if(newMatch)canvas.focus({preventScroll:true});
  authUI();
 }
 async function poll(){
  if(!active||(!queue&&!match)||leaving)return;
  const epoch=generation;
  const task=rpc('pong_online_poll',{p_match:match?.id||null,p_dir:direction(),p_target:target});flight=task;
  try{const data=await task;if(epoch!==generation||!active)return;failures=0;text('mm-network','');apply(data);schedule(match?.status==='playing'?70:750);}
  catch(error){if(epoch!==generation||!active)return;failures++;
   if((error.message||'').includes('Verified sign-in')){lobby();text('mm-status','Sign in to find an opponent');return;}
   text(match?'mm-network':'mm-status',errorMessage(error));clearInput();schedule(Math.min(3000,500*failures));
  }finally{if(flight===task)flight=null;}
 }
 async function join(kind,code=''){
  if(!authenticated()||queue||match||leaving)return;
  const epoch=++generation;for(const id of ['mm-find','mm-create','mm-room-join'])$(id).disabled=true;
  text('mm-status','Connecting…');const task=rpc('pong_online_join',{p_server:server.value,p_kind:kind,p_room:code});flight=task;
  try{const data=await task;if(epoch!==generation)return;apply(data);schedule(150);}
  catch(error){if(epoch===generation){text('mm-status',errorMessage(error));authUI();}}
  finally{if(flight===task)flight=null;}
 }
 async function leave(goMenu=false){
  if(leaving)return;leaving=true;generation++;stopPoll();clearInput();authUI();
  const pending=flight;try{if(pending)await pending.catch(()=>{});if(authenticated()&&(queue||match||pending))await rpc('pong_online_leave',{p_match:match?.id||null});}
  catch(_){text('mm-network','Connection interrupted. Trying to reconnect…');}
  finally{leaving=false;lobby();if(goMenu){active=false;screen.hidden=true;$('main-menu').hidden=false;$('menu-online').focus();}}
 }
 function draw(now){
  if(!active){paintId=null;return;}
  ctx.clearRect(0,0,900,500);ctx.fillStyle=$('backgroundColorPicker').value||'#071e2b';ctx.fillRect(0,0,900,500);
  ctx.strokeStyle='#82ddeb22';ctx.lineWidth=1;for(let x=0;x<900;x+=50){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,500);ctx.stroke();}for(let y=0;y<500;y+=50){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(900,y);ctx.stroke();}
  ctx.strokeStyle='#ffffff55';ctx.setLineDash([8,12]);ctx.beginPath();ctx.moveTo(450,0);ctx.lineTo(450,500);ctx.stroke();ctx.setLineDash([]);
  if(latest){
   const f=Math.max(0,Math.min(1,(now-receivedAt)/blendMs));const mix=k=>previous[k]+(latest[k]-previous[k])*f;
   // Goals reset the ball; do not draw a false sweep across the entire court.
   const reset=latest.ls!==previous.ls||latest.rs!==previous.rs;
   const ly=mix('ly'),ry=mix('ry');
   for(const [x,y,color] of [[30,ly,$('player1ColorPicker').value],[870,ry,$('player2ColorPicker').value]]){ctx.fillStyle=color;ctx.shadowColor=color;ctx.shadowBlur=16;ctx.fillRect(x,y,14,110);}
   const color=$('ballColorPicker').value;ctx.fillStyle=color;ctx.shadowColor=color;ctx.shadowBlur=18;ctx.beginPath();ctx.arc(reset?latest.x:mix('x'),reset?latest.y:mix('y'),8,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;
   if(latest.pause>0&&match?.status==='playing'){ctx.fillStyle='#061321';ctx.fillRect(345,215,210,70);ctx.fillStyle='#e9fcff';ctx.font='bold 28px system-ui';ctx.textAlign='center';ctx.fillText(String(Math.ceil(latest.pause)),450,260);}
  }
  paintId=requestAnimationFrame(draw);
 }
 $('menu-online').addEventListener('click',()=>{
  document.dispatchEvent(new CustomEvent('pong:pause'));active=true;screen.hidden=false;$('main-menu').hidden=true;$('game-container').hidden=true;$('game-header').hidden=true;
  lobby();if(!paintId)paintId=requestAnimationFrame(draw);$('mm-find').focus();
 });
 server.addEventListener('change',()=>{try{localStorage.setItem('pong-online-server',server.value);}catch(_){}text('mm-room-share','');});
 $('mm-find').addEventListener('click',()=>join('auto'));$('mm-create').addEventListener('click',()=>join('create'));
 $('mm-room-form').addEventListener('submit',e=>{e.preventDefault();join('room',$('mm-room-code').value.toUpperCase());});
 $('mm-cancel').addEventListener('click',()=>leave());$('mm-leave').addEventListener('click',()=>leave());$('mm-new-search').addEventListener('click',()=>leave());$('mm-back').addEventListener('click',()=>leave(true));
 $('mm-rematch').addEventListener('click',async()=>{
  if(!match||match.status!=='finished'||!match.canRematch||match.mineRequested)return;
  $('mm-rematch').disabled=true;const epoch=++generation;stopPoll();
  try{if(flight)await flight.catch(()=>{});const data=await rpc('pong_online_rematch',{p_match:match.id});if(epoch===generation){apply(data);schedule(100);}}
  catch(error){if(epoch===generation){text('mm-rematch-note',errorMessage(error));$('mm-rematch').disabled=false;schedule(750);}}
 });
 $('mm-signin').addEventListener('click',()=>{authReturn=true;screen.hidden=true;window.PongOnline?.showSignIn();});
 document.addEventListener('pong:authClosed',()=>{if(authReturn){authReturn=false;$('main-menu').hidden=true;screen.hidden=false;authUI();}});
 document.addEventListener('pong:authChanged',()=>{if(active){authUI();if(!authenticated()&&(queue||match)){generation++;stopPoll();lobby();}}});
 document.addEventListener('keydown',e=>{
  if(!active||!match||match.status!=='playing'||!['arrowup','arrowdown','w','s'].includes(e.key.toLowerCase())||e.target.closest('input,select,textarea'))return;
  e.preventDefault();e.stopPropagation();target=null;pointer=null;keys.add(e.key.toLowerCase());
 },true);
 document.addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));window.addEventListener('blur',clearInput);
 canvas.addEventListener('pointerdown',e=>{
  if(!match||match.status!=='playing'||e.button!==0)return;e.preventDefault();canvas.focus({preventScroll:true});
  pointer={id:e.pointerId,x:e.clientX,y:e.clientY,drag:e.pointerType!=='mouse'};canvas.setPointerCapture(e.pointerId);if(pointer.drag)setTarget(e);
 });
 function setTarget(e){if(keys.size||!pointer)return;const rect=canvas.getBoundingClientRect();target=Math.max(0,Math.min(1,((e.clientY-rect.top)/rect.height*500-55)/390));}
 canvas.addEventListener('pointermove',e=>{if(!pointer||pointer.id!==e.pointerId)return;if(e.pointerType==='mouse'&&!(e.buttons&1)){pointer=null;return;}if(Math.hypot(e.clientX-pointer.x,e.clientY-pointer.y)>=8)pointer.drag=true;if(pointer.drag)setTarget(e);});
 for(const type of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(type,e=>{if(pointer?.id===e.pointerId)pointer=null;});
 window.addEventListener('pagehide',()=>{if(authenticated()&&(queue||match))client()?.rpc('pong_online_leave',{p_match:match?.id||null});});
 authUI();
});
