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
    page: 0,
    // Pagina onthouden op id (profielen kunnen pagina's weglaten of verschuiven).
    pageId: store('get', KEY_PAGE),
    ctxPage: undefined,  // contextpagina waar de Mac nu om vraagt
    returnPage: null,    // pagina om naar terug te gaan als de app weer weg is
    autoPage: false,     // huidige pagina is automatisch gekozen
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
    var idx = pageIndex(app.pageId);
    if (idx < 0 && /^\d+$/.test(app.pageId || '')) { idx = parseInt(app.pageId, 10); } // oud: nummer
    app.page = idx >= 0 && idx < layout.pages.length ? idx : 0;
    app.ctxPage = undefined; // contextpagina opnieuw toepassen op de nieuwe pagina's
    var pn = $('profile-name');
    if (pn) { pn.textContent = layout.profile ? '· ' + layout.profile.name.toUpperCase() : ''; }
    render();
  }

  function pageIndex(id) {
    var pages = (app.layout && app.layout.pages) || [];
    for (var i = 0; i < pages.length; i++) { if (pages[i].id === id) { return i; } }
    return -1;
  }

  // auto = gekozen door de actieve app op de Mac; dan niet onthouden als jouw keuze.
  function goPage(idx, auto) {
    app.page = idx;
    app.autoPage = !!auto;
    if (!auto) {
      app.pageId = app.layout.pages[idx].id;
      store('set', KEY_PAGE, app.pageId);
    }
    render();
  }

  // Contextpagina: springt naar de pagina van de actieve app en terug als die app weer weg is.
  function updateContext() {
    var L = app.layout;
    if (!L) { return; }
    var target = (app.values.context && app.values.context.page) || null;
    if (target === app.ctxPage) { return; }
    app.ctxPage = target;
    var cur = L.pages[app.page];
    if (target) {
      var idx = pageIndex(target);
      if (idx < 0 || idx === app.page) { return; }
      if (app.returnPage === null && cur) { app.returnPage = app.autoPage ? null : cur.id; }
      goPage(idx, true);
    } else if (app.autoPage) {
      var back = pageIndex(app.returnPage || app.pageId);
      app.returnPage = null;
      goPage(back >= 0 ? back : 0, false);
    }
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
    stopPhotoTimers();
    if (!L) { return; }

    // Opgeslagen paginanummer kan buiten een oudere of kortere layout vallen.
    if (!L.pages || !L.pages.length) { return; }
    if (!(app.page >= 0 && app.page < L.pages.length)) { app.page = 0; }
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
      } else if (WIDGETS[t.kind]) {
        node.setAttribute('data-widget', t.kind);
        node.cpTile = t;
        WIDGETS[t.kind].build(node, t);
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
        var cls = 'tab' + (idx === app.page ? ' active' : '') + (pages[idx].context ? ' context' : '');
        if (idx === app.page && app.autoPage) { cls += ' auto'; }
        var b = el('div', cls, pages[idx].name);
        bindTap(b, function () {
          // Zelf kiezen gaat altijd voor; niet meer terugspringen.
          app.returnPage = null;
          goPage(idx, false);
        });
        tabs.appendChild(b);
      })(i);
    }
  }

  // Statussleutel: ingebouwd ("muted"), Home Assistant ("ha:light.x") of MQTT ("mqtt:huis/state").
  var TRUTHY = { on: 1, 'true': 1, '1': 1, yes: 1, aan: 1, open: 1, online: 1 };
  function stateEntity(key) {
    if (key.indexOf('ha:') === 0) { return (app.values.ha || {})[key.slice(3)] || { status: 'waiting' }; }
    return null;
  }
  function stateOn(key) {
    var e = stateEntity(key);
    if (e) { return e.on === true; }
    if (key.indexOf('mqtt:') === 0) {
      var v = (app.values.mqtt || {})[key.slice(5)];
      return typeof v === 'string' && TRUTHY[v.replace(/^\s+|\s+$/g, '').toLowerCase()] === 1;
    }
    return app.values[key] === true;
  }
  /// Niet bereikbaar: koppeling weg, apparaat onbekend of offline.
  function stateStale(key) {
    var e = stateEntity(key);
    if (e) { return e.status !== 'ok'; }
    if (key.indexOf('mqtt:') === 0) {
      return (app.values.integrations || {}).mqtt !== 'connected' || (app.values.mqtt || {})[key.slice(5)] === undefined;
    }
    return false;
  }
  function stateLevel(key) {
    var e = stateEntity(key);
    if (e) { return e.status === 'ok' ? e.level : undefined; }
    return app.values[key];
  }

  function updateValues() {
    var nodes = $('pad').childNodes;
    var toggles = app.values.toggles || {};
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute('data-state');
      var tog = nodes[i].getAttribute('data-toggle');
      if (!key && !tog) { continue; }
      var on = key ? stateOn(key) : toggles[tog] === true;
      var cls = nodes[i].className.replace(/\s*\b(active|stale)\b/g, '');
      if (on) { cls += ' active'; }
      if (key && stateStale(key)) { cls += ' stale'; }
      nodes[i].className = cls;
    }
    for (var id in app.sliders) {
      if (app.sliders.hasOwnProperty(id)) { app.sliders[id].update(); }
    }
    updateAgenda();
    updateMeeting();
    updateWidgets();
    updateContext();
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
  function bindPress(node, t, handler) {
    var moved = false, sx = 0, sy = 0, longTimer = null, longFired = false;
    var lastTap = 0, tapTimer = null;
    var go = handler || function (g) { fire(t.id, g); };

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
          go('long');
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
      if (!t.hasDouble) { go('tap'); return; }
      var now = new Date().getTime();
      if (now - lastTap < DOUBLE_MS) {
        clearTimeout(tapTimer);
        lastTap = 0;
        flash(node);
        go('double');
      } else {
        lastTap = now;
        tapTimer = setTimeout(function () { lastTap = 0; go('tap'); }, DOUBLE_MS);
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
    var key = t.stateKey || 'volume';

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
        var v = stateLevel(key);
        if (typeof v === 'number') { show(v); } else { value.textContent = '--'; fill.style.width = '0%'; }
        var muted = key === 'volume' ? app.values.muted === true : key === 'micVolume' ? app.values.micMuted === true : false;
        setCls(node, 'stale', stateStale(key));
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


  // ---------- widgets ----------

  function sendWidget(id, action, value) {
    var msg = { type: 'widget', id: id, action: action };
    if (value !== undefined && value !== null) { msg.value = value; }
    if (app.mode === 'ws' && app.ws && app.ws.readyState === 1) {
      app.ws.send(JSON.stringify(msg));
    } else if (app.mode === 'xhr' && app.connected) {
      request('POST', '/api/widget', msg, function (err, status, data) {
        if (data && data.ok === false && data.error) { toast(data.error); }
        poll();
      });
    } else {
      toast('Geen verbinding met de Mac');
    }
  }

  function q(node, cls) { return node.querySelector('.' + cls); }
  function setText(node, cls, text) { var e = q(node, cls); if (e && e.textContent !== text) { e.textContent = text; } }
  function setCls(node, name, on) {
    var re = new RegExp('\\s*\\b' + name + '\\b', 'g');
    var c = node.className.replace(re, '');
    node.className = on ? c + ' ' + name : c;
  }

  function mmss(sec) {
    sec = Math.max(0, Math.round(sec));
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    return (h ? h + ':' + pad2(m) : m) + ':' + pad2(s);
  }

  function bytes(n) {
    if (n >= 1073741824) { return (n / 1073741824).toFixed(1) + ' GB'; }
    if (n >= 1048576) { return (n / 1048576).toFixed(1) + ' MB'; }
    if (n >= 1024) { return Math.round(n / 1024) + ' KB'; }
    return n + ' B';
  }

  // `fast` = aanroep van de secondetimer: alleen tegels die zelf meetellen bijwerken.
  function updateWidgets(fast) {
    var nodes = document.querySelectorAll('[data-widget]');
    var all = app.values.widgets || {};
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i], t = n.cpTile, w = WIDGETS[t.kind];
      if (fast && !w.ticks) { continue; }
      w.update(n, t, all[t.id] || {});
    }
  }

  var photoTimers = [];
  function stopPhotoTimers() {
    for (var i = 0; i < photoTimers.length; i++) { clearInterval(photoTimers[i]); }
    photoTimers = [];
  }

  var WIDGETS = {
    weather: {
      build: function (node, t) {
        node.appendChild(el('div', 'w-top'));
        q(node, 'w-top').appendChild(el('span', 'w-icon', '…'));
        q(node, 'w-top').appendChild(el('span', 'w-temp', ''));
        node.appendChild(el('div', 'w-desc', ''));
        node.appendChild(el('div', 'w-range', ''));
        node.appendChild(el('div', 'w-place', t.label));
        bindPress(node, t, function () { sendWidget(t.id, 'refresh'); });
      },
      update: function (node, t, d) {
        if (d.status === 'ok') {
          setText(node, 'w-icon', d.icon);
          setText(node, 'w-temp', Math.round(d.temp) + '°');
          setText(node, 'w-desc', d.desc);
          var r = [];
          if (d.max !== undefined) { r.push('↑' + d.max + '° ↓' + d.min + '°'); }
          if (d.rain !== undefined) { r.push('☂ ' + d.rain + '%'); }
          setText(node, 'w-range', r.join('  ·  '));
          setText(node, 'w-place', (d.place || t.label).toUpperCase());
        } else if (d.status === 'error') {
          setText(node, 'w-icon', '⚠︎'); setText(node, 'w-temp', '');
          setText(node, 'w-desc', d.error || 'Weer niet beschikbaar'); setText(node, 'w-range', '');
        } else {
          setText(node, 'w-desc', 'Weer ophalen…');
        }
      }
    },

    nowplaying: {
      ticks: true,
      build: function (node, t) {
        var info = el('div', 'np-info');
        info.appendChild(el('div', 'np-app', 'NU SPEELT'));
        info.appendChild(el('div', 'np-title', '…'));
        info.appendChild(el('div', 'np-artist', ''));
        node.appendChild(info);
        var bar = el('div', 'np-bar');
        bar.appendChild(el('div', 'np-fill'));
        node.appendChild(bar);
        node.appendChild(el('div', 'np-time', ''));
        bindPress(info, t, function () { sendWidget(t.id, 'playpause'); });
        // Tikken op de balk = naar die plek springen.
        var seek = function (x) {
          var d = (app.values.widgets || {})[t.id] || {};
          if (!d.duration) { return; }
          var r = bar.getBoundingClientRect();
          sendWidget(t.id, 'seek', Math.max(0, Math.min(1, (x - r.left) / r.width)) * d.duration);
        };
        if (hasTouch) {
          bar.addEventListener('touchend', function (e) { e.preventDefault(); seek(e.changedTouches[0].clientX); }, false);
        } else {
          bar.addEventListener('click', function (e) { seek(e.clientX); }, false);
        }
        if ((t.w || 1) >= 3) {
          var ctrl = el('div', 'np-ctrl');
          var mk = function (label, action) {
            var b = el('span', 'np-btn np-' + action, label);
            bindTap(b, function () { flash(b); sendWidget(t.id, action); });
            ctrl.appendChild(b);
          };
          mk('⏮', 'prev'); mk('⏯', 'playpause'); mk('⏭', 'next');
          node.appendChild(ctrl);
        }
      },
      update: function (node, t, d) {
        if (d.status === 'ok') {
          var playing = d.state === 'playing';
          var pos = d.position + (playing ? (new Date().getTime() - d.at) / 1000 : 0);
          if (d.duration) { pos = Math.min(pos, d.duration); }
          setText(node, 'np-app', (d.appName || '').toUpperCase() + (playing ? ' · SPEELT' : ' · GEPAUZEERD'));
          setText(node, 'np-title', d.title);
          setText(node, 'np-artist', d.artist + (d.album ? ' — ' + d.album : ''));
          q(node, 'np-fill').style.width = (d.duration ? Math.round(pos / d.duration * 1000) / 10 : 0) + '%';
          setText(node, 'np-time', mmss(pos) + ' / ' + mmss(d.duration || 0));
          setCls(node, 'playing', playing);
        } else {
          setText(node, 'np-app', 'NU SPEELT');
          setText(node, 'np-title', d.status === 'error' ? d.error : 'Er speelt niets');
          setText(node, 'np-artist', d.status === 'error' ? '' : 'Muziek of Spotify');
          q(node, 'np-fill').style.width = '0%';
          setText(node, 'np-time', '');
          setCls(node, 'playing', false);
        }
      }
    },

    timer: {
      ticks: true,
      build: function (node, t) {
        node.appendChild(el('div', 't-label', t.label));
        node.appendChild(el('div', 't-time', '--:--'));
        node.appendChild(el('div', 't-sub', ''));
        var bar = el('div', 't-bar');
        bar.appendChild(el('div', 't-fill'));
        node.appendChild(bar);
        // tik = start/pauze, lang = opnieuw, dubbel = +1 minuut
        var opts = { id: t.id, hasLong: true, hasDouble: true };
        bindPress(node, opts, function (g) {
          sendWidget(t.id, g === 'long' ? 'reset' : g === 'double' ? 'add' : 'toggle');
          if (g !== 'tap') { flash(node); }
        });
      },
      update: function (node, t, d) {
        if (!d.duration) { return; }
        var left = d.running ? (d.endsAt - new Date().getTime()) / 1000 : d.remaining;
        left = Math.max(0, left);
        setText(node, 't-time', mmss(left));
        var sub;
        if (d.mode === 'pomodoro') {
          sub = (d.phase === 'rest' ? 'PAUZE' : 'WERK') + ' · RONDE ' + d.round;
        } else {
          sub = d.running ? 'LOOPT' : left <= 0 ? 'KLAAR' : left < d.duration ? 'GEPAUZEERD' : 'TIK = START';
        }
        setText(node, 't-sub', sub + (d.running ? '' : '  ·  LANG = RESET'));
        q(node, 't-fill').style.width = Math.round(left / d.duration * 1000) / 10 + '%';
        setCls(node, 'running', d.running);
        setCls(node, 'rest', d.phase === 'rest');
        setCls(node, 'done', !d.running && left <= 0);
      }
    },

    worldclock: {
      ticks: true,
      build: function (node, t) {
        node.appendChild(el('div', 'wc-head', t.label.toUpperCase()));
        node.appendChild(el('div', 'wc-rows'));
      },
      update: function (node, t, d) {
        var zones = d.zones || [], rows = q(node, 'wc-rows');
        if (rows.childNodes.length !== zones.length) {
          rows.innerHTML = '';
          for (var i = 0; i < zones.length; i++) {
            var r = el('div', 'wc-row');
            r.appendChild(el('span', 'wc-city', zones[i].label));
            r.appendChild(el('span', 'wc-time', ''));
            rows.appendChild(r);
          }
        }
        var now = new Date().getTime();
        for (var j = 0; j < zones.length; j++) {
          var z = zones[j], txt = '?';
          if (typeof z.offset === 'number') {
            var u = new Date(now + z.offset * 1000);
            txt = pad2(u.getUTCHours()) + ':' + pad2(u.getUTCMinutes());
          }
          var cell = rows.childNodes[j].childNodes[1];
          if (cell.textContent !== txt) { cell.textContent = txt; }
        }
      }
    },

    photos: {
      build: function (node, t) {
        node.appendChild(el('div', 'ph-img'));
        node.appendChild(el('div', 'ph-msg', ''));
        node.cpPhoto = { index: -1, url: null, timer: null, loading: false };
        bindPress(node, t, function () { showPhoto(node, t, 1); });
      },
      update: function (node, t, d) {
        var st = node.cpPhoto;
        setText(node, 'ph-msg', d.error || '');
        if (!d.count) { return; }
        if (st.index < 0) { showPhoto(node, t, 1); }
        if (!st.timer) {
          st.timer = setInterval(function () { showPhoto(node, t, 1); }, (d.interval || 10) * 1000);
          photoTimers.push(st.timer);
        }
      }
    },

    stats: {
      build: function (node, t) {
        node.appendChild(el('div', 'st-rows'));
      },
      update: function (node, t, d) {
        var rows = [];
        if (d.cpu !== undefined) { rows.push(['CPU', d.cpu + '%', d.cpu]); }
        if (d.ram) { rows.push(['RAM', bytes(d.ram.used) + ' / ' + bytes(d.ram.total), d.ram.percent]); }
        if (d.net) { rows.push(['NET', '↓ ' + bytes(d.net.down) + '/s  ↑ ' + bytes(d.net.up) + '/s', null]); }
        if (d.battery) { rows.push(['BAT', d.battery.percent + '%' + (d.battery.charging ? ' ⚡' : d.battery.plugged ? ' 🔌' : ''), d.battery.percent]); }
        var acc = d.accessories || [];
        for (var i = 0; i < acc.length; i++) { rows.push([acc[i].name.replace(/^Magic /, '').toUpperCase(), acc[i].percent + '%', acc[i].percent]); }
        if (!rows.length) { rows.push(['', 'Meten…', null]); }

        var box = q(node, 'st-rows');
        box.innerHTML = '';
        for (var j = 0; j < rows.length; j++) {
          var r = el('div', 'st-row');
          r.appendChild(el('span', 'st-key', rows[j][0]));
          r.appendChild(el('span', 'st-val', rows[j][1]));
          if (rows[j][2] !== null) {
            var bar = el('span', 'st-bar'), fill = el('span', 'st-fill');
            fill.style.width = rows[j][2] + '%';
            if (rows[j][0] !== 'BAT' && rows[j][2] > 85) { fill.className += ' hot'; }
            bar.appendChild(fill);
            r.appendChild(bar);
          }
          box.appendChild(r);
        }
      }
    },

    terminal: {
      build: function (node, t) {
        var head = el('div', 'term-head');
        head.appendChild(el('span', 'term-label', '$ ' + t.label));
        head.appendChild(el('span', 'term-status', ''));
        node.appendChild(head);
        node.appendChild(el('pre', 'term-out', ''));
        node.appendChild(el('div', 'term-btn', '▶ START'));
        node.cpArmed = null;
        bindPress(node, t, function () {
          var d = (app.values.widgets || {})[t.id] || {};
          if (d.status === 'running') { sendWidget(t.id, 'stop'); return; }
          if (t.dangerous) {
            // Gevaarlijke commando's pas na een tweede tik binnen 3 seconden.
            if (!node.cpArmed) {
              setCls(node, 'armed', true);
              setText(node, 'term-btn', 'NOG EEN KEER = UITVOEREN');
              node.cpArmed = setTimeout(function () {
                node.cpArmed = null; setCls(node, 'armed', false); setText(node, 'term-btn', '▶ START');
              }, 3000);
              return;
            }
            clearTimeout(node.cpArmed); node.cpArmed = null; setCls(node, 'armed', false);
          }
          flash(node);
          sendWidget(t.id, 'run', t.dangerous ? 1 : null);
        });
      },
      update: function (node, t, d) {
        var labels = { idle: 'KLAAR VOOR START', running: 'BEZIG…', done: 'GELUKT', failed: 'MISLUKT',
                       stopped: 'GESTOPT', timeout: 'TE LANG — GESTOPT' };
        var st = labels[d.status] || '';
        if (d.exit !== undefined && d.status !== 'running') { st += ' (' + d.exit + ')'; }
        setText(node, 'term-status', d.error || st);
        var out = q(node, 'term-out');
        var text = d.output || '';
        if (out.textContent !== text) { out.textContent = text; out.scrollTop = out.scrollHeight; }
        if (!node.cpArmed) { setText(node, 'term-btn', d.status === 'running' ? '■ STOP' : '▶ START'); }
        setCls(node, 'running', d.status === 'running');
        setCls(node, 'failed', d.status === 'failed' || d.status === 'timeout');
      }
    },

    // Home Assistant: sensor, lamp, schakelaar of thermostaat. Tik = aan/uit (niet bij sensoren en thermostaten).
    ha: {
      build: function (node, t) {
        node.appendChild(el('div', 'ha-name', t.label));
        var main = el('div', 'ha-main');
        main.appendChild(el('span', 'ha-value', '…'));
        main.appendChild(el('span', 'ha-unit', ''));
        node.appendChild(main);
        node.appendChild(el('div', 'ha-sub', ''));
        var btns = el('div', 'ha-btns');
        var down = el('div', 'ha-btn', '−'), up = el('div', 'ha-btn', '+');
        btns.appendChild(down); btns.appendChild(up);
        node.appendChild(btns);
        function step(dir) {
          return function (e) { if (e && e.stopPropagation) { e.stopPropagation(); } flash(node); sendWidget(t.id, dir); };
        }
        bindTap(down, step('down'));
        bindTap(up, step('up'));
        bindPress(node, t, function () {
          var d = (app.values.widgets || {})[t.id] || {};
          if (d.status !== 'ok' || !HA_TOGGLE[d.domain]) { return; }
          flash(node);
          sendWidget(t.id, 'toggle');
        });
      },
      update: function (node, t, d) {
        var climate = d.domain === 'climate';
        setCls(node, 'climate', climate);
        setCls(node, 'active', d.status === 'ok' && d.on === true && !climate);
        setCls(node, 'stale', d.status !== 'ok');
        setCls(node, 'tappable', d.status === 'ok' && HA_TOGGLE[d.domain] === 1);
        if (d.status !== 'ok') {
          setText(node, 'ha-value', d.status === 'connecting' ? '…' : '—');
          setText(node, 'ha-unit', '');
          setText(node, 'ha-sub', d.error || (d.status === 'unavailable' ? 'NIET BEREIKBAAR' : ''));
          return;
        }
        setText(node, 'ha-name', (t.label || d.name).toUpperCase());
        if (climate) {
          setText(node, 'ha-value', d.current !== undefined ? fmtNum(d.current) : '—');
          setText(node, 'ha-unit', '°');
          var sub = d.target !== undefined ? 'DOEL ' + fmtNum(d.target) + '°' : '';
          if (d.action) { sub += (sub ? '  ·  ' : '') + (HA_ACTION[d.action] || d.action.toUpperCase()); }
          setText(node, 'ha-sub', sub);
        } else if (HA_TOGGLE[d.domain] && !d.unit) {
          setText(node, 'ha-value', d.on ? 'AAN' : (HA_STATE[d.state] || 'UIT'));
          setText(node, 'ha-unit', '');
          setText(node, 'ha-sub', d.level !== undefined && d.on ? Math.round(d.level * 100) + '%' : d.name.toUpperCase());
        } else {
          var n = parseFloat(d.state);
          setText(node, 'ha-value', isNaN(n) ? (HA_STATE[d.state] || d.state.toUpperCase()) : fmtNum(n));
          setText(node, 'ha-unit', d.unit || '');
          // Naam alleen tonen als die iets toevoegt aan het label van de tegel.
          setText(node, 'ha-sub', d.name.toUpperCase() === (t.label || '').toUpperCase() ? '' : d.name.toUpperCase());
        }
      }
    },

    // MQTT: laatste waarde van een topic.
    mqtt: {
      build: function (node, t) {
        node.appendChild(el('div', 'ha-name', t.label));
        var main = el('div', 'ha-main');
        main.appendChild(el('span', 'ha-value', '…'));
        main.appendChild(el('span', 'ha-unit', ''));
        node.appendChild(main);
        node.appendChild(el('div', 'ha-sub', ''));
      },
      update: function (node, t, d) {
        setCls(node, 'stale', d.status !== 'ok');
        if (d.value === undefined) {
          setText(node, 'ha-value', d.status === 'waiting' || d.status === 'connecting' ? '…' : '—');
          setText(node, 'ha-unit', '');
          setText(node, 'ha-sub', d.error || (d.status === 'waiting' ? 'WACHT OP BERICHT' : ''));
          return;
        }
        var n = parseFloat(d.value);
        var isNum = !isNaN(n) && /^\s*-?[\d.]+\s*$/.test(d.value);
        setText(node, 'ha-value', isNum ? fmtNum(n) : d.value);
        setText(node, 'ha-unit', d.unit || '');
        setText(node, 'ha-sub', d.status === 'stale' ? 'LAATST BEKEND' : (d.topic || '').toUpperCase());
        setCls(node, 'long', !isNum && d.value.length > 8);
      }
    },

    // Plugin-widget: de plugin levert alleen gegevens (titel, waarde, regels, knoppen); de tablet tekent ze zelf.
    plugin: {
      build: function (node, t) {
        var head = el('div', 'pl-head');
        head.appendChild(el('span', 'pl-icon', ''));
        head.appendChild(el('span', 'pl-title', t.label));
        node.appendChild(head);
        var main = el('div', 'ha-main');
        main.appendChild(el('span', 'ha-value', '…'));
        main.appendChild(el('span', 'ha-unit', ''));
        node.appendChild(main);
        node.appendChild(el('div', 'ha-sub', ''));
        var bar = el('div', 'pl-bar');
        bar.appendChild(el('div', 'pl-fill'));
        node.appendChild(bar);
        node.appendChild(el('div', 'pl-lines'));
        node.appendChild(el('div', 'pl-btns'));
        node.cpButtons = '';
      },
      update: function (node, t, d) {
        setCls(node, 'stale', d.status !== 'ok');
        setCls(node, 'active', d.active === true);
        setText(node, 'pl-icon', d.icon || '');
        setText(node, 'pl-title', (d.title || t.label).toUpperCase());
        if (d.status !== 'ok') {
          setText(node, 'ha-value', d.status === 'waiting' ? '…' : '—');
          setText(node, 'ha-unit', '');
          setText(node, 'ha-sub', d.error || '');
          q(node, 'pl-bar').style.display = 'none';
          q(node, 'pl-lines').innerHTML = '';
          q(node, 'pl-btns').innerHTML = ''; node.cpButtons = '';
          return;
        }
        setText(node, 'ha-value', d.value !== undefined ? String(d.value) : '');
        setText(node, 'ha-unit', d.unit || '');
        setText(node, 'ha-sub', d.sub || '');
        setCls(node, 'long', d.value !== undefined && String(d.value).length > 10);
        var bar = q(node, 'pl-bar');
        if (typeof d.progress === 'number') {
          bar.style.display = 'block';
          q(node, 'pl-fill').style.width = Math.round(d.progress * 100) + '%';
        } else { bar.style.display = 'none'; }
        var lines = q(node, 'pl-lines');
        var ls = d.lines || [];
        lines.innerHTML = '';
        for (var i = 0; i < ls.length; i++) {
          var row = el('div', 'st-row');
          row.appendChild(el('span', 'st-key', ls[i].label));
          row.appendChild(el('span', 'st-val', ls[i].value));
          lines.appendChild(row);
        }
        // Knoppen alleen opnieuw opbouwen als ze veranderd zijn (anders gaat een lopende tik verloren).
        var bs = d.buttons || [], sig = '';
        for (var j = 0; j < bs.length; j++) { sig += bs[j].id + '=' + bs[j].label + ';'; }
        if (sig !== node.cpButtons) {
          node.cpButtons = sig;
          var box = q(node, 'pl-btns');
          box.innerHTML = '';
          for (var k = 0; k < bs.length; k++) {
            (function (b) {
              var btn = el('div', 'pl-btn', b.label);
              bindTap(btn, function () { flash(btn); sendWidget(t.id, b.id); });
              box.appendChild(btn);
            })(bs[k]);
          }
        }
      }
    }
  };

  var HA_TOGGLE = { light: 1, 'switch': 1, fan: 1, input_boolean: 1, cover: 1, media_player: 1, scene: 1, script: 1,
                    button: 1, input_button: 1, lock: 1, automation: 1, humidifier: 1, siren: 1 };
  var HA_STATE = { off: 'UIT', on: 'AAN', open: 'OPEN', closed: 'DICHT', opening: 'GAAT OPEN', closing: 'GAAT DICHT',
                   locked: 'OP SLOT', unlocked: 'OPEN', playing: 'SPEELT', paused: 'PAUZE', idle: 'RUST',
                   home: 'THUIS', not_home: 'WEG', unavailable: 'OFFLINE', unknown: '?' };
  var HA_ACTION = { heating: 'VERWARMT', cooling: 'KOELT', idle: 'RUST', off: 'UIT', drying: 'DROOGT', fan: 'VENTILEERT' };

  function fmtNum(n) {
    var r = Math.round(n * 10) / 10;
    return String(r).replace('.', ',');
  }
  WIDGETS.pomodoro = WIDGETS.timer;

  // Foto's worden met het token opgehaald (een <img src> kan geen header meesturen).
  function showPhoto(node, t, step) {
    var st = node.cpPhoto;
    if (st.loading) { return; }
    var d = (app.values.widgets || {})[t.id] || {};
    if (!d.count) { return; }
    st.loading = true;
    var next = (st.index + step + d.count) % d.count;
    var x = new XMLHttpRequest();
    x.open('GET', '/api/photo?tile=' + encodeURIComponent(t.id) + '&i=' + next, true);
    x.responseType = 'blob';
    x.setRequestHeader('X-Cyberpad-Token', app.token);
    x.onreadystatechange = function () {
      if (x.readyState !== 4) { return; }
      st.loading = false;
      if (x.status !== 200 || !window.URL || !URL.createObjectURL) { return; }
      var url = URL.createObjectURL(x.response);
      q(node, 'ph-img').style.backgroundImage = 'url(' + url + ')';
      if (st.url) { URL.revokeObjectURL(st.url); }
      st.url = url;
      st.index = next;
    };
    x.send();
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

    app.clockTimer = setInterval(function () { updateClock(); updateMeetingClock(); updateWidgets(true); }, 1000);
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
