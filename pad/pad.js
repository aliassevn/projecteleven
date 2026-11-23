/* Cyberpad tablet-pagina.
 * Bewust ES5 (geen let/const/arrow functions/template strings), zodat het ook op Safari uit iOS 9 draait. */
(function () {
  'use strict';

  var KEY_TOKEN = 'cyberpad.token';
  var KEY_LAYOUT = 'cyberpad.layout';
  var KEY_PAGE = 'cyberpad.page';

  var LONG_MS = 500;     // lang indrukken
  var DOUBLE_MS = 280;   // max. tijd tussen twee tikken

  var MEETING_BUTTONS = {
    mute:  { icon: '🎤', label: 'Microfoon' },
    video: { icon: '📹', label: 'Camera' },
    hand:  { icon: '✋', label: 'Hand opsteken' },
    share: { icon: '🖥', label: 'Scherm delen' },
    leave: { icon: '📞', label: 'Ophangen' }
  };

  var app = {
    token: store('get', KEY_TOKEN),
    layout: null,
    values: {},
    page: parseInt(store('get', KEY_PAGE) || '0', 10) || 0,
    ws: null,
    mode: null,          // 'ws' of 'xhr'
    connected: false,
    wsFailures: 0,
    retryDelay: 1000,
    retryTimer: null,
    pollTimer: null,
    clockTimer: null,
    sliders: {},
    meetingKey: null,
    meetingHidden: false,
    meetingButtons: {},
    leaveArmed: null
  };

  // ---------- hulpjes ----------

  function store(op, k, v) {
    try {
      if (op === 'get') { return window.localStorage.getItem(k); }
      if (op === 'set') { window.localStorage.setItem(k, v); }
      if (op === 'del') { window.localStorage.removeItem(k); }
    } catch (e) { /* privémodus in oude Safari */ }
    return null;
  }

  function $(id) { return document.getElementById(id); }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) { e.className = cls; }
    if (text !== undefined && text !== null) { e.appendChild(document.createTextNode(text)); }
    return e;
  }

  function pad2(n) { return (n < 10 ? '0' : '') + n; }

  function request(method, path, body, cb) {
    var x = new XMLHttpRequest();
    x.open(method, path, true);
    x.timeout = 6000;
    x.setRequestHeader('Content-Type', 'application/json');
    if (app.token) { x.setRequestHeader('X-Cyberpad-Token', app.token); }
    x.onreadystatechange = function () {
      if (x.readyState !== 4) { return; }
      var data = null;
      try { data = JSON.parse(x.responseText); } catch (e) { data = null; }
      cb(x.status === 0 ? 'network' : null, x.status, data);
    };
    x.ontimeout = function () { /* onreadystatechange meldt status 0 */ };
    x.send(body ? JSON.stringify(body) : null);
  }

  var toastTimer = null;
  function toast(text) {
    var t = $('toast');
    t.textContent = text;
    t.className = 'toast show';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.className = 'toast'; }, 3500);
  }

  function setStatus(connected, text) {
    app.connected = connected;
    $('status-text').textContent = text;
    $('status-dot').className = connected ? 'dot on' : 'dot';
    document.body.className = connected ? '' : 'offline';
  }

  // ---------- koppelen ----------

  function deviceName() {
    var ua = navigator.userAgent;
    if (/iPad/.test(ua)) { return 'iPad'; }
    if (/iPhone/.test(ua)) { return 'iPhone'; }
    if (/Android/.test(ua)) { return /Mobile/.test(ua) ? 'Android-telefoon' : 'Android-tablet'; }
    if (/Macintosh/.test(ua) && 'ontouchend' in document) { return 'iPad'; }
    return 'Browser';
  }

  function showPair(msg) {
    disconnect();
    $('pair').className = 'pair';
    $('pair-msg').textContent = msg || '';
    $('pair-code').value = '';
    setStatus(false, 'NIET GEKOPPELD');
  }

  function hidePair() { $('pair').className = 'pair hidden'; }

  function doPair() {
    var code = $('pair-code').value.replace(/\D/g, '');
    if (code.length !== 6) { $('pair-msg').textContent = 'De code heeft 6 cijfers.'; return; }
    $('pair-btn').disabled = true;
    $('pair-msg').textContent = 'Bezig…';
    request('POST', '/api/pair', { code: code, name: deviceName() }, function (err, status, data) {
      $('pair-btn').disabled = false;
      if (status === 200 && data && data.token) {
        app.token = data.token;
        store('set', KEY_TOKEN, data.token);
        hidePair();
        connect();
      } else if (status === 429 && data) {
        $('pair-msg').textContent = 'Te veel pogingen. Probeer het over ' + data.seconds + ' seconden opnieuw.';
      } else if (status === 401) {
        $('pair-msg').textContent = 'Verkeerde code' + (data && data.attemptsLeft ? ' (nog ' + data.attemptsLeft + ' pogingen).' : '.');
      } else {
        $('pair-msg').textContent = 'Geen verbinding met de Mac. Staat Cyberpad aan?';
      }
    });
  }

  function forget(msg) {
    app.token = null;
    store('del', KEY_TOKEN);
    showPair(msg);
  }

  // ---------- verbinding ----------

  function disconnect() {
    clearTimeout(app.retryTimer);
    clearInterval(app.pollTimer);
    if (app.ws) {
      var ws = app.ws;
      app.ws = null;
      try { ws.close(); } catch (e) { /* al dicht */ }
    }
  }

  function connect() {
    disconnect();
    if (!app.token) { showPair(); return; }
    setStatus(false, 'VERBINDEN…');
    if (window.WebSocket && app.wsFailures < 3) { connectWs(); } else { connectXhr(); }
  }

  function scheduleReconnect() {
    clearTimeout(app.retryTimer);
    var secs = Math.round(app.retryDelay / 1000);
    setStatus(false, 'VERBINDING WEG · OPNIEUW OVER ' + secs + 'S');
    app.retryTimer = setTimeout(connect, app.retryDelay);
    app.retryDelay = Math.min(app.retryDelay * 2, 15000);
  }

  function onConnected(mode) {
    app.mode = mode;
    app.retryDelay = 1000;
    setStatus(true, mode === 'ws' ? 'ONLINE' : 'ONLINE · XHR');
  }

  function connectWs() {
    var url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws';
    var ws, opened = false;
    try { ws = new WebSocket(url); } catch (e) { app.wsFailures = 99; connectXhr(); return; }
    app.ws = ws;

    var openTimeout = setTimeout(function () {
      if (!opened) { try { ws.close(); } catch (e) { /* */ } }
    }, 5000);

    ws.onopen = function () {
      opened = true;
      clearTimeout(openTimeout);
      ws.send(JSON.stringify({ type: 'hello', token: app.token }));
    };
    ws.onmessage = function (ev) {
      var m;
      try { m = JSON.parse(ev.data); } catch (e) { return; }
      handle(m);
    };
    ws.onclose = function () {
      clearTimeout(openTimeout);
      if (app.ws !== ws) { return; } // bewust gesloten
      app.ws = null;
      if (!opened) { app.wsFailures++; }
      if (app.token) { scheduleReconnect(); }
    };
    ws.onerror = function () { /* onclose volgt */ };
  }

  function connectXhr() {
    request('GET', '/api/layout', null, function (err, status, data) {
      if (status === 401) { forget('Deze tablet is ontkoppeld. Koppel opnieuw.'); return; }
      // Mac helemaal onbereikbaar: volgende keer eerst weer WebSocket proberen.
      if (err || status !== 200 || !data) { app.wsFailures = 0; scheduleReconnect(); return; }
      onConnected('xhr');
      setLayout(data.layout);
      setValues(data.state);
      clearInterval(app.pollTimer);
      app.pollTimer = setInterval(poll, 1500);
    });
  }

  function poll() {
    request('GET', '/api/state', null, function (err, status, data) {
      if (status === 401) { forget('Deze tablet is ontkoppeld. Koppel opnieuw.'); return; }
      if (err || status !== 200) { clearInterval(app.pollTimer); scheduleReconnect(); return; }
      if (data && data.state) { setValues(data.state); }
    });
  }

  function handle(m) {
    switch (m.type) {
      case 'welcome': onConnected('ws'); break;
      case 'layout': setLayout(m.layout); break;
      case 'state': setValues(m.state); break;
      case 'ack': if (!m.ok && m.error) { toast(m.error); } break;
      case 'toast': toast(m.text); break;
      case 'unauthorized': forget('Deze tablet is ontkoppeld. Koppel opnieuw.'); break;
    }
  }

  function send(type, id, value, gesture) {
    var msg = { type: type, id: id };
    if (value !== undefined && value !== null) { msg.value = value; }
    if (gesture) { msg.gesture = gesture; }
    if (app.mode === 'ws' && app.ws && app.ws.readyState === 1) {
      app.ws.send(JSON.stringify(msg));
    } else if (app.mode === 'xhr' && app.connected) {
      request('POST', type === 'press' ? '/api/press' : '/api/slider', msg, function (err, status, data) {
        if (data && data.ok === false && data.error) { toast(data.error); }
        poll();
      });
    } else {
      toast('Geen verbinding met de Mac');
    }
  }

  // ---------- layout tekenen ----------

  function setLayout(layout) {
    if (!layout || !layout.pages) { return; }
    app.layout = layout;
    store('set', KEY_LAYOUT, JSON.stringify(layout));
    if (app.page >= layout.pages.length) { app.page = 0; }
    render();
  }

  function setValues(values) {
    if (!values) { return; }
    app.values = values;
    updateValues();
  }

  function render() {
    var L = app.layout;
    var pad = $('pad');
    pad.innerHTML = '';
    app.sliders = {};
    if (!L) { return; }

    renderTabs();
    var page = L.pages[app.page];
    var cols = L.columns || 5, rows = L.rows || 3;
    var gap = window.innerWidth < 600 ? 8 : 14;
    var W = pad.clientWidth, H = pad.clientHeight;
    var cw = (W - gap * (cols - 1)) / cols;
    var ch = (H - gap * (rows - 1)) / rows;

    for (var i = 0; i < page.tiles.length; i++) {
      var t = page.tiles[i];
      var w = t.w || 1, h = t.h || 1;
      var node = el('div', 'tile kind-' + (t.kind || 'button'));
      node.style.left = (t.x * (cw + gap)) + 'px';
      node.style.top = (t.y * (ch + gap)) + 'px';
      node.style.width = (w * cw + (w - 1) * gap) + 'px';
      node.style.height = (h * ch + (h - 1) * gap) + 'px';
      node.setAttribute('data-id', t.id);
      node.appendChild(el('span', 'corner'));

      if (t.kind === 'clock') {
        node.appendChild(el('div', 'clock-time', '--:--'));
        node.appendChild(el('div', 'clock-date', ''));
        if (h > 1) { node.className += ' big'; }
      } else if (t.kind === 'slider') {
        buildSlider(node, t);
      } else if (t.kind === 'agenda') {
        node.appendChild(el('div', 'agenda-head', 'VOLGENDE'));
        node.appendChild(el('div', 'agenda-title', '…'));
        node.appendChild(el('div', 'agenda-time', ''));
        node.appendChild(el('div', 'agenda-join', 'DEELNEMEN ›'));
        bindPress(node, t);
      } else {
        if (t.icon) { node.appendChild(el('div', 'icon', t.icon)); }
        node.appendChild(el('div', 'label', t.label));
        if (t.hasLong || t.hasDouble) {
          node.appendChild(el('span', 'gestures', (t.hasLong ? '◷' : '') + (t.hasDouble ? '⁑' : '')));
        }
        if (t.stateKey) { node.setAttribute('data-state', t.stateKey); }
        if (t.toggle) { node.setAttribute('data-toggle', t.id); }
        bindPress(node, t);
      }
      pad.appendChild(node);
    }
    updateClock();
    updateValues();
  }

  function renderTabs() {
    var tabs = $('tabs');
    tabs.innerHTML = '';
    var pages = app.layout.pages;
    document.documentElement.className = pages.length > 1 ? 'has-tabs' : '';
    if (pages.length < 2) { return; }
    for (var i = 0; i < pages.length; i++) {
      (function (idx) {
        var b = el('div', 'tab' + (idx === app.page ? ' active' : ''), pages[idx].name);
        bindTap(b, function () {
          app.page = idx;
          store('set', KEY_PAGE, String(idx));
          render();
        });
        tabs.appendChild(b);
      })(i);
    }
  }

  function updateValues() {
    var nodes = $('pad').childNodes;
    var toggles = app.values.toggles || {};
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute('data-state');
      var tog = nodes[i].getAttribute('data-toggle');
      if (!key && !tog) { continue; }
      var on = key ? app.values[key] === true : toggles[tog] === true;
      var cls = nodes[i].className.replace(/\s*\bactive\b/g, '');
      nodes[i].className = on ? cls + ' active' : cls;
    }
    for (var id in app.sliders) {
      if (app.sliders.hasOwnProperty(id)) { app.sliders[id].update(); }
    }
    updateAgenda();
    updateMeeting();
  }

  // ---------- agenda ----------

  function hm(ms) { var d = new Date(ms); return pad2(d.getHours()) + ':' + pad2(d.getMinutes()); }

  function dur(min) {
    if (min < 60) { return min + ' min'; }
    var h = Math.floor(min / 60), m = min % 60;
    return h + 'u' + (m ? ' ' + m + 'm' : '');
  }

  function updateAgenda() {
    var nodes = document.querySelectorAll('.kind-agenda');
    if (!nodes.length) { return; }
    var a = app.values.agenda || { status: 'noAccess' };
    var title, time, cls = '', join = false;
    if (a.status === 'ok') {
      var now = new Date().getTime();
      title = a.title;
      if (now < a.start) {
        var mins = Math.ceil((a.start - now) / 60000);
        time = hm(a.start) + '–' + hm(a.end) + ' · OVER ' + dur(mins).toUpperCase();
        if (mins <= 5) { cls = ' soon'; }
      } else {
        time = 'NU · NOG ' + dur(Math.max(1, Math.ceil((a.end - now) / 60000))).toUpperCase();
        cls = ' now';
      }
      join = a.hasLink === true;
    } else if (a.status === 'none') {
      title = 'Geen afspraken meer';
      time = 'VANDAAG EN MORGEN';
    } else if (a.status === 'denied') {
      title = 'Geen toegang tot Agenda';
      time = 'STA TOEGANG TOE OP DE MAC';
    } else {
      title = 'Agenda niet gekoppeld';
      time = 'KLIK OP TOESTAAN IN DE MENUBALK';
    }
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      n.querySelector('.agenda-title').textContent = title;
      n.querySelector('.agenda-time').textContent = time;
      n.querySelector('.agenda-join').style.display = join ? '' : 'none';
      n.className = n.className.replace(/\s*\b(soon|now|has-link)\b/g, '') + cls + (join ? ' has-link' : '');
    }
  }

  // ---------- vergaderpaneel ----------

  function updateMeeting() {
    var m = app.values.meeting;
    var overlay = $('meeting'), pill = $('meeting-pill');
    if (!m) {
      app.meetingKey = null;
      overlay.className = 'meeting hidden';
      pill.className = 'meeting-pill hidden';
      return;
    }
    var key = m.app + ':' + m.since;
    if (key !== app.meetingKey) {
      app.meetingKey = key;
      app.meetingHidden = false; // nieuwe vergadering: paneel automatisch tonen
      buildMeeting(m);
    }
    overlay.className = app.meetingHidden ? 'meeting hidden' : 'meeting';
    pill.className = app.meetingHidden ? 'meeting-pill' : 'meeting-pill hidden';
    pill.textContent = '● ' + m.name.toUpperCase();
    $('meeting-title').textContent = '// VERGADERING · ' + m.name.toUpperCase();

    var b = app.meetingButtons;
    if (b.mute) { setMeetingState(b.mute, m.muted, 'MIC UIT', 'MIC AAN', 'MICROFOON'); }
    if (b.video) { setMeetingState(b.video, m.video === null ? null : !m.video, 'CAMERA UIT', 'CAMERA AAN', 'CAMERA'); }
    $('meeting-note').textContent = m.statusSource === 'app' ? '' :
      m.statusSource === 'estimated' ? '≈ status bijgehouden door Cyberpad; kan afwijken als je in de app zelf klikt'
                                     : 'Status onbekend voor ' + m.name;
    updateMeetingClock();
  }

  // `off` = true betekent: mic/camera staat UIT → magenta.
  function setMeetingState(node, off, offText, onText, unknownText) {
    var label = node.querySelector('.label');
    var cls = node.className.replace(/\s*\b(active|unknown)\b/g, '');
    if (off === true) { label.textContent = offText; node.className = cls + ' active'; }
    else if (off === false) { label.textContent = onText; node.className = cls; }
    else { label.textContent = unknownText + ' ?'; node.className = cls + ' unknown'; }
  }

  function buildMeeting(m) {
    var grid = $('meeting-grid');
    grid.innerHTML = '';
    app.meetingButtons = {};
    for (var i = 0; i < m.actions.length; i++) {
      (function (action) {
        var spec = MEETING_BUTTONS[action];
        if (!spec) { return; }
        var node = el('div', 'tile mbtn mbtn-' + action);
        node.appendChild(el('span', 'corner'));
        node.appendChild(el('div', 'icon', spec.icon));
        node.appendChild(el('div', 'label', spec.label));
        bindTap(node, function () { meetingPress(action, node); });
        grid.appendChild(node);
        app.meetingButtons[action] = node;
      })(m.actions[i]);
    }
  }

  function meetingPress(action, node) {
    if (action === 'leave') {
      // Ophangen pas na een tweede tik binnen 3 seconden.
      if (!app.leaveArmed) {
        node.className += ' armed';
        node.querySelector('.label').textContent = 'NOG EEN KEER = OPHANGEN';
        app.leaveArmed = setTimeout(function () { disarmLeave(node); }, 3000);
        return;
      }
      disarmLeave(node);
    }
    flash(node);
    sendMeeting(action);
  }

  function disarmLeave(node) {
    clearTimeout(app.leaveArmed);
    app.leaveArmed = null;
    node.className = node.className.replace(/\s*\barmed\b/g, '');
    node.querySelector('.label').textContent = MEETING_BUTTONS.leave.label;
  }

  function sendMeeting(action) {
    if (app.mode === 'ws' && app.ws && app.ws.readyState === 1) {
      app.ws.send(JSON.stringify({ type: 'meeting', action: action }));
    } else if (app.mode === 'xhr' && app.connected) {
      request('POST', '/api/meeting', { action: action }, function (err, status, data) {
        if (data && data.ok === false && data.error) { toast(data.error); }
        poll();
      });
    } else {
      toast('Geen verbinding met de Mac');
    }
  }

  function updateMeetingClock() {
    var m = app.values.meeting;
    if (!m) { return; }
    var s = Math.max(0, Math.floor((new Date().getTime() - m.since) / 1000));
    var h = Math.floor(s / 3600), mm = Math.floor((s % 3600) / 60), ss = s % 60;
    $('meeting-since').textContent = (h ? h + ':' + pad2(mm) : mm) + ':' + pad2(ss);
  }

  // ---------- aanraken ----------

  var hasTouch = 'ontouchstart' in window;

  function bindTap(node, fn) {
    if (hasTouch) {
      node.addEventListener('touchend', function (e) { e.preventDefault(); fn(); }, false);
    } else {
      node.addEventListener('click', fn, false);
    }
  }

  // Tik, lang indrukken en dubbeltikken. Een enkele tik wacht alleen even als de knop ook een dubbeltik kent.
  function bindPress(node, t) {
    var moved = false, sx = 0, sy = 0, longTimer = null, longFired = false;
    var lastTap = 0, tapTimer = null;

    function down() { node.className += ' pressed'; }
    function up() { node.className = node.className.replace(/\s*\bpressed\b/g, ''); }

    function start(x, y) {
      moved = false; longFired = false; sx = x; sy = y;
      down();
      if (t.hasLong) {
        clearTimeout(longTimer);
        longTimer = setTimeout(function () {
          longFired = true;
          up();
          flash(node);
          fire(t.id, 'long');
        }, LONG_MS);
      }
    }

    function move(x, y) {
      if (Math.abs(x - sx) > 20 || Math.abs(y - sy) > 20) { moved = true; clearTimeout(longTimer); up(); }
    }

    function end() {
      clearTimeout(longTimer);
      up();
      if (moved || longFired) { return; }
      if (!t.hasDouble) { fire(t.id, 'tap'); return; }
      var now = new Date().getTime();
      if (now - lastTap < DOUBLE_MS) {
        clearTimeout(tapTimer);
        lastTap = 0;
        flash(node);
        fire(t.id, 'double');
      } else {
        lastTap = now;
        tapTimer = setTimeout(function () { lastTap = 0; fire(t.id, 'tap'); }, DOUBLE_MS);
      }
    }

    function cancel() { clearTimeout(longTimer); up(); }

    if (hasTouch) {
      node.addEventListener('touchstart', function (e) {
        e.preventDefault();
        start(e.touches[0].clientX, e.touches[0].clientY);
      }, false);
      node.addEventListener('touchmove', function (e) {
        move(e.touches[0].clientX, e.touches[0].clientY);
      }, false);
      node.addEventListener('touchend', function (e) { e.preventDefault(); end(); }, false);
      node.addEventListener('touchcancel', cancel, false);
    } else {
      var isDown = false;
      node.addEventListener('mousedown', function (e) { isDown = true; start(e.clientX, e.clientY); }, false);
      node.addEventListener('mouseup', function () { if (isDown) { isDown = false; end(); } }, false);
      node.addEventListener('mouseleave', function () { if (isDown) { isDown = false; moved = true; cancel(); } }, false);
    }
  }

  function flash(node) {
    node.className += ' flash';
    setTimeout(function () { node.className = node.className.replace(/\s*\bflash\b/g, ''); }, 250);
  }

  function fire(id, gesture) {
    if (navigator.vibrate) { try { navigator.vibrate(gesture === 'tap' ? 10 : 25); } catch (e) { /* */ } }
    send('press', id, null, gesture === 'tap' ? null : gesture);
  }

  function buildSlider(node, t) {
    var label = el('div', 'label', t.label);
    var value = el('div', 'slider-value', '--');
    var track = el('div', 'slider-track');
    var fill = el('div', 'slider-fill');
    track.appendChild(fill);
    node.appendChild(label);
    node.appendChild(value);
    node.appendChild(track);

    var dragging = false, lastSent = 0, pending = null;
    var key = 'volume';

    function show(v) {
      fill.style.width = Math.round(v * 100) + '%';
      value.textContent = Math.round(v * 100) + '%';
    }

    function fromX(clientX) {
      var r = track.getBoundingClientRect();
      var v = (clientX - r.left) / r.width;
      return Math.max(0, Math.min(1, v));
    }

    function move(clientX) {
      var v = fromX(clientX);
      show(v);
      var now = new Date().getTime();
      if (now - lastSent > 80) { lastSent = now; send('slider', t.id, v); pending = null; } else { pending = v; }
    }

    function end() {
      dragging = false;
      node.className = node.className.replace(/\s*\bpressed\b/g, '');
      if (pending !== null) { send('slider', t.id, pending); pending = null; }
    }

    function start(clientX) {
      dragging = true;
      node.className += ' pressed';
      move(clientX);
    }

    if (hasTouch) {
      node.addEventListener('touchstart', function (e) { e.preventDefault(); start(e.touches[0].clientX); }, false);
      node.addEventListener('touchmove', function (e) { e.preventDefault(); if (dragging) { move(e.touches[0].clientX); } }, false);
      node.addEventListener('touchend', function (e) { e.preventDefault(); end(); }, false);
      node.addEventListener('touchcancel', end, false);
    } else {
      node.addEventListener('mousedown', function (e) { start(e.clientX); }, false);
      document.addEventListener('mousemove', function (e) { if (dragging) { move(e.clientX); } }, false);
      document.addEventListener('mouseup', function () { if (dragging) { end(); } }, false);
    }

    app.sliders[t.id] = {
      update: function () {
        if (dragging) { return; }
        var v = app.values[key];
        if (typeof v === 'number') { show(v); } else { value.textContent = '--'; }
        var muted = app.values.muted === true;
        node.className = node.className.replace(/\s*\bmuted\b/g, '') + (muted ? ' muted' : '');
      }
    };
  }

  // ---------- klok ----------

  var DAYS = ['ZO', 'MA', 'DI', 'WO', 'DO', 'VR', 'ZA'];
  var MONTHS = ['JAN', 'FEB', 'MRT', 'APR', 'MEI', 'JUN', 'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEC'];

  function updateClock() {
    var d = new Date();
    var time = pad2(d.getHours()) + ':' + pad2(d.getMinutes());
    var date = DAYS[d.getDay()] + ' ' + d.getDate() + ' ' + MONTHS[d.getMonth()];
    var nodes = document.querySelectorAll('.kind-clock');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].querySelector('.clock-time').textContent = time;
      nodes[i].querySelector('.clock-date').textContent = date;
    }
  }

  // ---------- start ----------

  function init() {
    bindTap($('pair-btn'), doPair);
    $('pair-code').addEventListener('keyup', function (e) {
      if (e.keyCode === 13 || $('pair-code').value.replace(/\D/g, '').length === 6) { doPair(); }
    }, false);

    // Laatst bekende layout direct tonen, ook als de Mac (nog) niet bereikbaar is.
    var cached = store('get', KEY_LAYOUT);
    if (cached) { try { app.layout = JSON.parse(cached); } catch (e) { app.layout = null; } }
    render();

    var resizeTimer = null;
    window.addEventListener('resize', function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(render, 150);
    }, false);
    window.addEventListener('orientationchange', function () { setTimeout(render, 300); }, false);

    app.clockTimer = setInterval(function () { updateClock(); updateMeetingClock(); }, 1000);
    setInterval(updateAgenda, 15000);

    bindTap($('meeting-hide'), function () { app.meetingHidden = true; updateMeeting(); });
    bindTap($('meeting-pill'), function () { app.meetingHidden = false; updateMeeting(); });

    // Verbinding controleren als de tablet uit slaap komt.
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden && app.token && !app.connected) { app.retryDelay = 1000; connect(); }
    }, false);

    // Houd de WebSocket wakker (sommige routers sluiten stille verbindingen).
    setInterval(function () {
      if (app.mode === 'ws' && app.ws && app.ws.readyState === 1) {
        app.ws.send(JSON.stringify({ type: 'ping' }));
      }
    }, 25000);

    if (app.token) { connect(); } else { showPair(); }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, false);
  } else {
    init();
  }
})();
