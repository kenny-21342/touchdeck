(() => {
  const $ = (s) => document.querySelector(s);
  const app = $('#app'), pad = $('#pad'), overlay = $('#pair-overlay');
  const pinInput = $('#pin'), error = $('#pair-error');
  let socket, connected = false, modifiers = new Set(), pointers = new Map(), gesture = null;
  const send = (data) => { if (connected && socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(data)); };
  const setConnection = (ok, name = '') => {
    connected = ok;
    $('#led').classList.toggle('on', ok);
    $('#connection-label').textContent = ok ? `CONNECTED${name ? ` · ${name.toUpperCase()}` : ''}` : 'PAIR YOUR MAC';
    app.classList.toggle('disconnected', !ok);
    overlay.classList.toggle('hidden', ok);
    if (!ok) { modifiers.clear(); document.querySelectorAll('.mod').forEach(b => b.classList.remove('selected')); }
  };
  const keyEvent = (key, down, extra = []) => send({action:'key',key,down,modifiers:[...modifiers,...extra]});
  const tapKey = (key) => { keyEvent(key,true); keyEvent(key,false); if (modifiers.has('shift')) toggleModifier('shift'); };

  function connect() {
    const pin = pinInput.value.trim();
    if (!/^\d{6}$/.test(pin)) { error.textContent = 'Enter the six digit code from your Mac.'; pinInput.focus(); return; }
    error.textContent = 'Connecting to your Mac…';
    const host = location.hostname || 'localhost';
    if (socket && socket.readyState < WebSocket.CLOSING) socket.close();
    let client;
    try { client = new WebSocket(`ws://${host}:8766`); socket = client; }
    catch { error.textContent = 'Could not reach the companion. Check the Wi-Fi address.'; return; }
    const timeout = setTimeout(() => { if (!connected && socket===client) { error.textContent = 'No response. Check the Mac companion and try again.'; client.close(); } }, 5000);
    client.onopen = () => client.send(JSON.stringify({action:'pair',pin}));
    client.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'paired') { clearTimeout(timeout); error.textContent = ''; setConnection(true, data.name); }
      else if (data.type === 'error') { clearTimeout(timeout); error.textContent = data.message; }
    };
    client.onerror = () => { clearTimeout(timeout); if(socket===client) error.textContent = 'Connection failed. Open this page from your Mac’s TouchDeck address.'; };
    client.onclose = () => { clearTimeout(timeout); if (socket===client && connected) setConnection(false); };
  }
  $('#connect').addEventListener('click', connect);
  pinInput.addEventListener('input', () => { pinInput.value = pinInput.value.replace(/\D/g,'').slice(0,6); });
  pinInput.addEventListener('keydown', e => { if (e.key === 'Enter') connect(); });
  $('#settings').addEventListener('click', () => { overlay.classList.remove('hidden'); pinInput.value = ''; pinInput.focus(); });

  const center = () => {
    const values = [...pointers.values()];
    return {x:values.reduce((a,p)=>a+p.x,0)/values.length,y:values.reduce((a,p)=>a+p.y,0)/values.length};
  };
  pad.addEventListener('pointerdown', e => {
    e.preventDefault(); pad.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId,{x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,startX:e.clientX,startY:e.clientY,moved:false});
    gesture = {count:pointers.size, start:gesture?.start ?? performance.now(), multi:pointers.size>1, moved:gesture?.moved ?? false};
  });
  pad.addEventListener('pointermove', e => {
    if (!pointers.has(e.pointerId)) return;
    e.preventDefault();
    const old = center(), p = pointers.get(e.pointerId);
    p.x=e.clientX; p.y=e.clientY;
    const next = center();
    if (pointers.size >= 2) {
      gesture.multi = true;
      for (const item of pointers.values()) if (Math.abs(item.x-item.startX)+Math.abs(item.y-item.startY)>8) { item.moved=true; gesture.moved=true; }
      const dy = next.y-old.y, dx = next.x-old.x;
      if (Math.abs(dx)+Math.abs(dy)>0) send({action:'scroll',dx:Math.round(dx*1.9),dy:Math.round(dy*1.9)});
    } else {
      // Trackpad emits incremental movement, independent of where the finger rests.
      const prevX=p.lastX, prevY=p.lastY;
      const mx=e.clientX-prevX, my=e.clientY-prevY;
      if (Math.abs(e.clientX-p.startX)+Math.abs(e.clientY-p.startY)>8) { p.moved=true; gesture.moved=true; }
      if (mx||my) send({action:'move',dx:mx,dy:my});
      p.lastX=e.clientX;p.lastY=e.clientY;
    }
    if (pointers.size>1) for (const item of pointers.values()) { item.lastX=item.x; item.lastY=item.y; }
  });
  pad.addEventListener('pointerup', e => {
    const p=pointers.get(e.pointerId); if (!p) return;
    pointers.delete(e.pointerId);
    if (gesture && pointers.size===0 && !gesture.moved && performance.now()-gesture.start<280) send({action:'click',button:gesture.multi?'right':'left'});
    if (!pointers.size) gesture=null;
  });
  pad.addEventListener('pointercancel', e=>{pointers.delete(e.pointerId);gesture=null;});

  document.querySelectorAll('[data-key]').forEach(button => button.addEventListener('pointerdown', e => {
    e.preventDefault();
    if (button.dataset.key === 'shift') toggleModifier('shift'); else tapKey(button.dataset.key);
  }));
  document.querySelectorAll('[data-shortcut]').forEach(button => button.addEventListener('click', () => tapKey(button.dataset.shortcut)));
  function toggleModifier(name) {
    if (modifiers.has(name)) { modifiers.delete(name); keyEvent(name,false); }
    else { modifiers.add(name); keyEvent(name,true); }
    document.querySelector(`[data-mod="${name}"]`)?.classList.toggle('selected',modifiers.has(name));
  }
  document.querySelectorAll('[data-mod]').forEach(button => button.addEventListener('click',()=>toggleModifier(button.dataset.mod)));
  $('#send-text').addEventListener('click',()=>{
    const input=$('#text-input'); if (!input.value) { input.focus(); return; }
    send({action:'text',text:input.value}); input.value=''; input.blur();
  });
  $('#text-input').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();$('#send-text').click();}});
  $('#keyboard-toggle').addEventListener('click',()=>$('#keyboard').classList.toggle('folded'));
  $('#keyboard-close').addEventListener('click',()=>$('#keyboard').classList.toggle('folded'));
  $('#mission').addEventListener('click',()=>tapKey('f3'));
  $('#desktop').addEventListener('click',()=>tapKey('f11'));
  setConnection(false);
})();
