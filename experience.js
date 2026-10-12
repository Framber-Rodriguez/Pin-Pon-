/* PIN-PON experience and online integration — Framber Rodriguez. */
document.addEventListener('DOMContentLoaded', () => {
 const $ = id => document.getElementById(id);
 const t = text => window.PongI18n?.translate(text) || text;
 // Film credits: one continuous position, with manual scrubbing and idle resume.
 const roll=$('credits-roll'),screen=$('credits-screen'),mask=screen.querySelector('.credits-mask');
 let pos=0,last=0,id=null,idleUntil=0,drag=null;
 function paint(){roll.style.transform=`translateY(${pos}px)`;}
 function manual(delta){pos=Math.min(innerHeight*.75,Math.max(-roll.offsetHeight,pos+delta));idleUntil=performance.now()+1600;paint();}
 function frame(now){
  if(screen.hidden){id=null;return;}
  const dt=Math.min(now-last,50);last=now;
  if(now>idleUntil && !drag){pos-=dt*(roll.offsetHeight+innerHeight*.75)/55000;paint();}
  if(pos<-roll.offsetHeight){$('close-credits').click();id=null;return;}
  id=requestAnimationFrame(frame);
 }
 document.addEventListener('pong:credits',()=>{
  if(id)cancelAnimationFrame(id);roll.classList.add('rolling');pos=innerHeight*.75;idleUntil=0;last=performance.now();paint();id=requestAnimationFrame(frame);
 });
 mask.addEventListener('wheel',e=>{e.preventDefault();manual(-e.deltaY);},{passive:false});
 mask.addEventListener('pointerdown',e=>{if(e.button!==0)return;drag={id:e.pointerId,y:e.clientY};mask.setPointerCapture(e.pointerId);});
 mask.addEventListener('pointermove',e=>{if(!drag||drag.id!==e.pointerId)return;manual(e.clientY-drag.y);drag.y=e.clientY;});
 function release(){drag=null;idleUntil=performance.now()+1600;}
 mask.addEventListener('pointerup',release);mask.addEventListener('pointercancel',release);
 // Auth and leaderboard are unavailable until a real project is configured.
 const panel=document.createElement('section');panel.id='online-screen';panel.hidden=true;panel.setAttribute('aria-label','GLOBAL LEADERBOARD');
 panel.innerHTML=`<div class="online-panel"><p class="eyebrow">PIN-PON</p><h2>GLOBAL LEADERBOARD</h2>
 <p>Ranked: solo vs AI, 10 points, 1 point per goal, no undo. Classic and items have separate boards.</p>
 <p>Only public names appear. Your email stays private.</p><div id="auth-area">
 <form id="auth-form"><label for="login-email">Email</label><input id="login-email" type="email" autocomplete="email" required maxlength="254"><button type="submit" id="email-login">Send login link</button></form>
 <div id="oauth-buttons" class="auth-controls"></div><div id="profile-controls" hidden><label for="public-name">Display name</label> <input id="public-name" maxlength="24" autocomplete="nickname"> <button id="save-name">Save name</button> <button id="signout">Sign out</button></div><p id="auth-message" role="status"></p></div>
 <div class="online-filters"><label for="board-difficulty">AI Difficulty:</label><select id="board-difficulty"><option value="easy">Easy</option><option value="normal" selected>Normal</option><option value="hard">Hard</option><option value="veryHard">Very Hard</option><option value="impossible">Impossible</option></select><label for="board-items">POWER-UPS</label><select id="board-items"><option value="classic">Classic</option><option value="items">Items</option></select><button id="board-refresh">Refresh</button></div>
 <p id="online-message" role="status"></p><table id="leaderboard-table"><thead><tr><th>Rank</th><th>Player</th><th>Wins</th><th>Points</th></tr></thead><tbody id="board-rows" data-no-translate></tbody></table>
 <p>Results are reported by the browser, not verified by a game server.</p><button id="online-close">Main Menu</button></div>`;
 document.body.appendChild(panel);
 const notice=document.createElement('p');notice.id='ranking-message';notice.setAttribute('role','status');$('game-container').appendChild(notice);
 let client=null,user=null,fetchGeneration=0;
 window.PongOnline={get userId(){return user?.id || null;}};
 const cfg=window.PONG_CONFIG || {};
 function message(id,text){$(id).textContent=text;}
 function authUI(){
  $('auth-form').hidden=!!user;$('oauth-buttons').hidden=!!user;$('profile-controls').hidden=!user;
  if(user) $('public-name').value=user.user_metadata?.pong_name || '';
 }
 async function board(){
  const gen=++fetchGeneration;$('board-rows').replaceChildren();
  if(!client){message('online-message','Leaderboard setup pending.');return;}
  message('online-message','Loading…');
  try {
   const {data,error}=await client.rpc('pong_leaderboard',{p_difficulty:$('board-difficulty').value,p_ruleset:$('board-items').value});
   if(gen!==fetchGeneration)return;if(error)throw error;
   for(const [i,row] of (data||[]).entries()){
    const tr=document.createElement('tr');
    for(const value of [i+1,row.display_name,row.wins,row.points]){const td=document.createElement('td');td.textContent=String(value);tr.appendChild(td);}
    $('board-rows').appendChild(tr);
   }
   message('online-message',data?.length?'':'No results yet.');
  }catch(_){if(gen===fetchGeneration)message('online-message','Could not connect. Try again.');}
 }
 $('menu-leaderboard').addEventListener('click',()=>{panel.hidden=false;$('main-menu').hidden=true;board();$('online-close').focus();});
 function close(){panel.hidden=true;$('main-menu').hidden=false;$('menu-play').focus();}
 $('online-close').addEventListener('click',close);
 document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!panel.hidden)close();});
 $('board-difficulty').addEventListener('change',board);$('board-items').addEventListener('change',board);$('board-refresh').addEventListener('click',board);
 $('auth-form').addEventListener('submit',async e=>{
  e.preventDefault();if(!client)return;const button=$('email-login');button.disabled=true;
  try{const {error}=await client.auth.signInWithOtp({email:$('login-email').value.trim(),options:{emailRedirectTo:location.origin+location.pathname}});if(error)throw error;message('auth-message','Check your email for the login link.');}
  catch(_){message('auth-message','Could not connect. Try again.');}finally{button.disabled=false;}
 });
 $('save-name').addEventListener('click',async()=>{
  if(!client||!user)return;const name=$('public-name').value.trim();if(name.length<2){$('public-name').focus();return;}
  const {error}=await client.auth.updateUser({data:{pong_name:name}});message('auth-message',error?'Could not connect. Try again.':'Saved.');
 });
 $('signout').addEventListener('click',async()=>{if(!client)return;const {error}=await client.auth.signOut();if(error)message('auth-message','Could not connect. Try again.');});
 document.addEventListener('pong:result',async e=>{
  const r=e.detail;
  if(!client){message('ranking-message','Leaderboard setup pending.');return;}
  if(!user||!r.session){message('ranking-message','Sign in to save your results');return;}
  if(!r.eligible){message('ranking-message','Practice result — not ranked.');return;}
  message('ranking-message','Saving result…');
  try{const {error}=await client.rpc('pong_submit_result',{p_match_id:r.id,p_difficulty:r.difficulty,p_ruleset:r.items?'items':'classic',p_player_score:r.playerScore,p_opponent_score:r.opponentScore});if(error)throw error;message('ranking-message','Result saved.');}
  catch(_){message('ranking-message','Could not connect. Try again.');}
 });
 async function setup(){
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(cfg.supabaseUrl)||!cfg.supabasePublishableKey){
   $('email-login').disabled=true;$('login-email').disabled=true;message('auth-message','Leaderboard setup pending.');return;
  }
  try{
   const sdk=await import('https://esm.sh/@supabase/supabase-js@2.57.4');
   client=sdk.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey,{auth:{flowType:'pkce',detectSessionInUrl:true}});
   client.auth.onAuthStateChange((_event,session)=>{user=session?.user||null;authUI();});
   const {data,error}=await client.auth.getSession();if(error)throw error;user=data.session?.user||null;authUI();
   for(const provider of (cfg.providers||[]).filter(p=>['google','discord','facebook'].includes(p))){
    const b=document.createElement('button');b.textContent=provider[0].toUpperCase()+provider.slice(1);b.dataset.noTranslate='';
    b.addEventListener('click',async()=>{const {error}=await client.auth.signInWithOAuth({provider,options:{redirectTo:location.origin+location.pathname}});if(error)message('auth-message','Could not connect. Try again.');});$('oauth-buttons').appendChild(b);
   }
   if(!panel.hidden)board();
  }catch(_){client=null;message('auth-message','Could not connect. Try again.');$('email-login').disabled=true;}
 }
 setup();
});
