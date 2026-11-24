/* Cyberpad layout-editor. Draait op de Mac (eigen venster) en op elke gekoppelde tablet.
 * Bewust ES5, net als de tablet-pagina. Werkt op een kopie van de layout; pas bij Opslaan gaat hij naar de Mac,
 * die controleert, een back-up maakt en alle tablets direct bijwerkt. */
(function () {
  'use strict';

  // Vertalingen: de Nederlandse tekst is de sleutel (shared/i18n/<taal>.json, via /i18n.js).
  var I18N = window.CP_I18N || {};
  function T(s) {
    var out = Object.prototype.hasOwnProperty.call(I18N, s) ? I18N[s] : s;
    for (var i = 1; i < arguments.length; i++) { out = out.split('{' + (i - 1) + '}').join(String(arguments[i])); }
    return out;
  }
  // Namen, labels en voorbeelden in schema.json vertalen (types, groepen en opties blijven zoals ze zijn).
  function translateSchema(o) {
    if (o && typeof o === 'object') {
      for (var k in o) {
        if (!Object.prototype.hasOwnProperty.call(o, k)) { continue; }
        if ((k === 'name' || k === 'label' || k === 'placeholder') && typeof o[k] === 'string') { o[k] = T(o[k]); }
        else { translateSchema(o[k]); }
      }
    }
    return o;
  }

  function translateDom() {
    if (window.CP_LANG) { document.documentElement.lang = window.CP_LANG; }
    document.title = 'Cyberpad — ' + T('Layout bewerken');
    var n = document.querySelectorAll('[data-t],[data-t-title]');
    for (var i = 0; i < n.length; i++) {
      if (n[i].hasAttribute('data-t')) { n[i].textContent = T(n[i].textContent.replace(/^\s+|\s+$/g, '')); }
      if (n[i].hasAttribute('data-t-title')) { n[i].title = T(n[i].title); }
    }
  }

  var LANGS = [['en', 'English'], ['nl', 'Nederlands'], ['es', 'Español']];

  // Taal wisselen: geldt voor heel Cyberpad. Eerst vragen als er nog iets niet is opgeslagen.
  function switchLanguage(code) {
    if (code === (window.CP_LANG || 'en')) { return; }
    if (E.layout && isDirty() && !window.confirm(T('Niet-opgeslagen wijzigingen weggooien?'))) { return; }
    req('POST', '/api/lang', { lang: code }, function (st) {
      if (st === 200) { E.leaving = true; setTimeout(function () { location.reload(); }, 300); }
      else { message(T('Taal wisselen mislukt ({0})', st), true); }
    });
  }

  // Taal gewisseld in het menu op de Mac (alleen in het Mac-venster).
  window.cpLanguageChanged = function () {
    if (E.layout && isDirty()) { message(T('De taal is gewisseld. Sla op en open de editor opnieuw om hem in de nieuwe taal te zien.'), false); return; }
    E.leaving = true;
    location.reload();
  };

  var E = {
    auth: null,          // { mode: 'mac'|'tablet', header, token }
    schema: null,
    catalog: { presets: [], plugins: [], apps: [] },
    layout: null,
    saved: '',           // JSON van de laatst opgeslagen versie
    revision: null,
    page: 0,
    sel: null,           // id van de geselecteerde tegel
    undo: [],
    redo: [],
    problems: [],
    jsonBad: 0,          // aantal JSON-velden met een fout
    themes: [],
    iconTab: null
  };

  var hasTouch = 'ontouchstart' in window;

  // ---------- hulpjes ----------

  function $(id) { return document.getElementById(id); }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) { e.className = cls; }
    if (text !== undefined && text !== null) { e.textContent = text; }
    return e;
  }
  function on(node, ev, fn) { node.addEventListener(ev, fn, false); }
  function tap(node, fn) { on(node, 'click', fn); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function store(k, v) { try { if (v === undefined) { return window.sessionStorage.getItem(k); } window.sessionStorage.setItem(k, v); } catch (e) { return null; } return null; }
  function local(k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } }

  function req(method, path, body, cb) {
    var x = new XMLHttpRequest();
    x.open(method, path, true);
    x.timeout = 15000;
    if (E.auth) { x.setRequestHeader(E.auth.header, E.auth.token); }
    if (body !== null && body !== undefined) { x.setRequestHeader('Content-Type', 'application/json'); }
    x.onreadystatechange = function () {
      if (x.readyState !== 4) { return; }
      var data = null;
      try { data = JSON.parse(x.responseText); } catch (e) { data = null; }
      cb(x.status, data);
    };
    x.send(body !== null && body !== undefined ? JSON.stringify(body) : null);
  }

  var msgTimer = null;
  function message(text, isError, sticky) {
    var m = $('msg');
    m.textContent = text;
    m.className = 'msg' + (isError ? ' err' : '');
    clearTimeout(msgTimer);
    if (!sticky) { msgTimer = setTimeout(function () { m.className = 'msg hidden'; }, isError ? 8000 : 3000); }
  }

  function kindDef(kind) {
    var ks = E.schema.kinds;
    for (var i = 0; i < ks.length; i++) { if (ks[i].kind === (kind || 'button')) { return ks[i]; } }
    return ks[0];
  }
  function actionDef(type) {
    var a = E.schema.actions;
    for (var i = 0; i < a.length; i++) { if (a[i].type === type) { return a[i]; } }
    return null;
  }
  function curPage() { return E.layout.pages[E.page]; }
  // Raster van de huidige pagina (eigen raster, anders dat van de layout).
  function cols() { return curPage().columns || E.layout.columns; }
  function rowsN() { return curPage().rows || E.layout.rows; }
  function findTile(id) {
    var ts = curPage().tiles;
    for (var i = 0; i < ts.length; i++) { if (ts[i].id === id) { return ts[i]; } }
    return null;
  }
  function allTileIds() {
    var out = {};
    for (var p = 0; p < E.layout.pages.length; p++) {
      for (var t = 0; t < E.layout.pages[p].tiles.length; t++) { out[E.layout.pages[p].tiles[t].id] = true; }
    }
    return out;
  }
  function slug(s) {
    return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 24);
  }
  function uniqueTileId(base) {
    var ids = allTileIds(), b = slug(base) || 'tegel', id = b, n = 2;
    while (ids[id]) { id = b + '-' + n; n++; }
    return id;
  }
  function uniquePageId(base) {
    var b = slug(base) || 'pagina', id = b, n = 2, taken = {};
    for (var i = 0; i < E.layout.pages.length; i++) { taken[E.layout.pages[i].id] = true; }
    while (taken[id]) { id = b + '-' + n; n++; }
    return id;
  }

  // ---------- ongedaan maken ----------

  function snapshot() {
    E.undo.push(JSON.stringify(E.layout));
    if (E.undo.length > 60) { E.undo.shift(); }
    E.redo = [];
  }
  function undo() {
    if (!E.undo.length) { return; }
    E.redo.push(JSON.stringify(E.layout));
    E.layout = JSON.parse(E.undo.pop());
    afterChange(true);
  }
  function redoIt() {
    if (!E.redo.length) { return; }
    E.undo.push(JSON.stringify(E.layout));
    E.layout = JSON.parse(E.redo.pop());
    afterChange(true);
  }

  // Na elke wijziging: tekenen, knoppen bijwerken en (even later) laten controleren door de Mac.
  var validateTimer = null;
  function afterChange(full) {
    if (E.page >= E.layout.pages.length) { E.page = E.layout.pages.length - 1; }
    if (E.sel && !findTile(E.sel)) { E.sel = null; }
    drawPages();
    drawGrid();
    if (full) { drawSide(); }
    updateButtons();
    clearTimeout(validateTimer);
    validateTimer = setTimeout(validate, 600);
  }

  function isDirty() { return JSON.stringify(clean(E.layout)) !== E.saved; }

  function updateButtons() {
    $('b-undo').disabled = !E.undo.length;
    $('b-redo').disabled = !E.redo.length;
    var s = $('b-save');
    s.className = 'btn primary' + (isDirty() ? ' dirty' : '');
    s.textContent = isDirty() ? T('OPSLAAN') + ' ●' : T('OPGESLAGEN');
    var p = $('problems');
    var n = E.problems.length + (E.jsonBad ? 1 : 0);
    p.textContent = n ? '⚠ ' + (n === 1 ? T('1 PROBLEEM') : T('{0} PROBLEMEN', n)) : '';
  }

  function validate() {
    req('POST', '/api/editor/validate', { layout: clean(E.layout) }, function (st, data) {
      E.problems = (data && data.errors) || [];
      markOverlaps();
      updateButtons();
    });
  }

  // ---------- opschonen voor opslaan ----------

  function cleanAction(a) {
    if (!a || !a.type) { return undefined; }
    var o = {};
    for (var k in a) {
      if (!a.hasOwnProperty(k)) { continue; }
      var v = a[k];
      if (v === '' || v === null || v === undefined) { continue; }
      if (k === 'steps') {
        var st = [];
        for (var i = 0; i < v.length; i++) { var c = cleanAction(v[i]); if (c) { st.push(c); } }
        if (st.length) { o.steps = st; }
        continue;
      }
      if (typeof v === 'object' && !(v instanceof Array) && !Object.keys(v).length) { continue; }
      o[k] = v;
    }
    return o;
  }
  function clean(l) {
    var out = clone(l);
    for (var p = 0; p < out.pages.length; p++) {
      var pg = out.pages[p];
      if (pg.apps && !pg.apps.length) { delete pg.apps; }
      if (!pg.columns || !pg.rows) { delete pg.columns; delete pg.rows; }
      for (var t = 0; t < pg.tiles.length; t++) {
        var tl = pg.tiles[t];
        var keys = ['action', 'longPress', 'doubleTap', 'offAction'];
        for (var k = 0; k < keys.length; k++) {
          var c = cleanAction(tl[keys[k]]);
          if (c) { tl[keys[k]] = c; } else { delete tl[keys[k]]; }
        }
        if (tl.config) {
          for (var ck in tl.config) {
            if (tl.config.hasOwnProperty(ck) && (tl.config[ck] === '' || tl.config[ck] === null || tl.config[ck] === undefined)) { delete tl.config[ck]; }
          }
          if (!Object.keys(tl.config).length) { delete tl.config; }
        }
        if (!tl.icon) { delete tl.icon; }
        if (!tl.toggle) { delete tl.toggle; }
        if (tl.kind === 'button' || !tl.kind) { delete tl.kind; }
        if (tl.w === 1) { delete tl.w; }
        if (tl.h === 1) { delete tl.h; }
      }
    }
    if (out.profiles && !out.profiles.length) { delete out.profiles; }
    var o = out.themeOverrides;
    if (o) {
      if (o.colors && !Object.keys(o.colors).length) { delete o.colors; }
      if (o.effects && !Object.keys(o.effects).length) { delete o.effects; }
      if (!o.font) { delete o.font; }
      if (o.radius === undefined || o.radius === null) { delete o.radius; }
      if (!Object.keys(o).length) { delete out.themeOverrides; }
    }
    for (var pp = 0; pp < out.pages.length; pp++) {
      for (var tt = 0; tt < out.pages[pp].tiles.length; tt++) { if (!out.pages[pp].tiles[tt].color) { delete out.pages[pp].tiles[tt].color; } }
    }
    return out;
  }

  // ---------- pagina-tabs ----------

  function drawPages() {
    var box = $('pages');
    box.innerHTML = '';
    for (var i = 0; i < E.layout.pages.length; i++) {
      (function (idx) {
        var pg = E.layout.pages[idx];
        var b = el('span', 'ptab' + (idx === E.page ? ' on' : ''), (pg.apps && pg.apps.length ? '◆ ' : '') + pg.name);
        tap(b, function () { E.page = idx; E.sel = null; drawPages(); drawGrid(); drawSide(); });
        box.appendChild(b);
      })(i);
    }
    var add = el('span', 'ptab add', '+ ' + T('PAGINA'));
    tap(add, function () {
      var name = window.prompt(T('Naam van de nieuwe pagina'), T('Nieuw'));
      if (!name) { return; }
      snapshot();
      E.layout.pages.push({ id: uniquePageId(name), name: name, tiles: [] });
      E.page = E.layout.pages.length - 1;
      E.sel = null;
      afterChange(true);
    });
    box.appendChild(add);
  }

  // ---------- raster ----------

  var geo = null; // { cw, ch, gap }

  // ---------- voorbeeld op tablet-formaat ----------
  // Ruimte voor tegels = venster min statusbalk (54) en tabs (70) en marges (2×18), zoals op de tablet.
  var PRESETS = [
    { id: 'ipad97', name: T('iPad 9,7″ (oud)'), sw: 1024, sh: 768, bar: 64 },
    { id: 'ipad102', name: T('iPad 10,2″'), sw: 1080, sh: 810, bar: 74 },
    { id: 'ipad109', name: T('iPad 10,9″ / Air'), sw: 1180, sh: 820, bar: 74 },
    { id: 'ipadmini', name: 'iPad mini', sw: 1133, sh: 744, bar: 74 },
    { id: 'ipadpro11', name: 'iPad Pro 11″', sw: 1194, sh: 834, bar: 74 },
    { id: 'ipadpro13', name: T('iPad Pro 12,9″'), sw: 1366, sh: 1024, bar: 74 }
  ];
  function padBox(vw, vh) {
    var small = vw <= 600;
    return { w: vw - (small ? 20 : 36), h: vh - (small ? 46 : 54) - (small ? 60 : 70), vw: vw, vh: vh };
  }
  function loadPreview() {
    try { E.preview = JSON.parse(window.localStorage.getItem('cyberpad.editor.preview') || 'null'); } catch (e) { E.preview = null; }
  }
  function savePreview() {
    try { window.localStorage.setItem('cyberpad.editor.preview', JSON.stringify(E.preview)); } catch (e) { /* */ }
  }
  // Huidige voorbeeldmaat (of null = vrij, passend in het venster).
  function previewBox() {
    var p = E.preview;
    if (!p || !p.src) { return null; }
    var box = null, name = '';
    if (p.src.indexOf('dev:') === 0) {
      var devs = E.catalog.devices || [];
      for (var i = 0; i < devs.length; i++) {
        if (devs[i].id !== p.src.slice(4)) { continue; }
        var d = devs[i];
        name = d.name;
        box = p.rotate ? padBox(d.vh, d.vw) : { w: d.w, h: d.h, vw: d.vw, vh: d.vh };
      }
    } else {
      for (var j = 0; j < PRESETS.length; j++) {
        var q = PRESETS[j];
        if (q.id !== p.src) { continue; }
        name = q.name;
        var sw = p.rotate ? q.sh : q.sw, sh = p.rotate ? q.sw : q.sh;
        box = padBox(sw, p.full ? sh : sh - q.bar);
      }
    }
    if (box) { box.name = name; }
    return box;
  }

  function drawPreviewBar() {
    var bar = $('preview'), p = E.preview || {};
    bar.innerHTML = '';
    bar.appendChild(el('span', 'pv-label', T('VOORBEELD')));
    var sel = el('select');
    sel.appendChild(optionEl('', T('Vrij (past in dit venster)')));
    var devs = E.catalog.devices || [];
    if (devs.length) {
      var og = el('optgroup'); og.label = T('Zoals je tablet nu is');
      for (var i = 0; i < devs.length; i++) { og.appendChild(optionEl('dev:' + devs[i].id, devs[i].name + ' (' + devs[i].vw + '×' + devs[i].vh + ')')); }
      sel.appendChild(og);
    }
    var og2 = el('optgroup'); og2.label = T('Modellen');
    for (var j = 0; j < PRESETS.length; j++) { og2.appendChild(optionEl(PRESETS[j].id, PRESETS[j].name)); }
    sel.appendChild(og2);
    sel.value = p.src || '';
    on(sel, 'change', function () { E.preview = { src: sel.value, rotate: false, full: false }; savePreview(); drawPreviewBar(); drawGrid(); });
    bar.appendChild(sel);
    if (p.src) {
      var rot = el('label', 'pv-check');
      var rc = el('input'); rc.type = 'checkbox'; rc.checked = !!p.rotate;
      on(rc, 'change', function () { E.preview.rotate = rc.checked; savePreview(); drawPreviewBar(); drawGrid(); });
      rot.appendChild(rc); rot.appendChild(document.createTextNode(' ' + T('gedraaid')));
      bar.appendChild(rot);
      if (p.src.indexOf('dev:') !== 0) {
        var fs = el('label', 'pv-check');
        var fc = el('input'); fc.type = 'checkbox'; fc.checked = !!p.full;
        on(fc, 'change', function () { E.preview.full = fc.checked; savePreview(); drawPreviewBar(); drawGrid(); });
        fs.appendChild(fc); fs.appendChild(document.createTextNode(' ' + T('schermvullend')));
        bar.appendChild(fs);
      }
      bar.appendChild(el('span', 'pv-info', ''));
    }
  }

  function computeGeo() {
    var g = $('grid'), box = previewBox();
    if (!box) {
      g.style.width = ''; g.style.height = ''; g.style.marginLeft = ''; g.style.webkitTransform = g.style.transform = '';
      $('canvas').className = 'canvas';
      var gap0 = g.clientWidth < 700 || cols() >= 8 ? 6 : 12;
      geo = { cw: (g.clientWidth - gap0 * (cols() - 1)) / cols(), ch: (g.clientHeight - gap0 * (rowsN() - 1)) / rowsN(), gap: gap0, s: 1 };
      return;
    }
    // Raster op ware grootte (CSS-pixels van de tablet) tekenen en als geheel verkleinen.
    var cv = $('canvas'), availW = cv.clientWidth - 36, availH = cv.clientHeight - 36;
    var sc = Math.min(availW / box.w, availH / box.h, 1.5);
    var gap = box.vw < 600 || cols() >= 8 ? 8 : 14;
    g.style.width = box.w + 'px';
    g.style.height = box.h + 'px';
    g.style.webkitTransformOrigin = g.style.transformOrigin = '0 0';
    g.style.webkitTransform = g.style.transform = 'scale(' + sc + ')';
    g.style.marginLeft = Math.max(0, (availW - box.w * sc) / 2) + 'px';
    cv.className = 'canvas device';
    geo = { cw: (box.w - gap * (cols() - 1)) / cols(), ch: (box.h - gap * (rowsN() - 1)) / rowsN(), gap: gap, s: sc };
    var info = document.querySelector('#preview .pv-info');
    if (info) {
      info.textContent = box.name + ' · ' + T('tegelruimte {0}', Math.round(box.w) + '×' + Math.round(box.h)) +
        ' · ' + T('1 vak = {0}', Math.round(geo.cw) + '×' + Math.round(geo.ch) + ' pt');
    }
  }
  function place(node, x, y, w, h) {
    node.style.left = (x * (geo.cw + geo.gap)) + 'px';
    node.style.top = (y * (geo.ch + geo.gap)) + 'px';
    node.style.width = (w * geo.cw + (w - 1) * geo.gap) + 'px';
    node.style.height = (h * geo.ch + (h - 1) * geo.gap) + 'px';
  }

  function occupied(page, exceptId) {
    var occ = {};
    for (var i = 0; i < page.tiles.length; i++) {
      var t = page.tiles[i];
      if (t.id === exceptId) { continue; }
      for (var dy = 0; dy < (t.h || 1); dy++) { for (var dx = 0; dx < (t.w || 1); dx++) { occ[(t.y + dy) + ':' + (t.x + dx)] = true; } }
    }
    return occ;
  }
  function fits(page, id, x, y, w, h) {
    var L = E.layout;
    if (x < 0 || y < 0 || w < 1 || h < 1 || x + w > cols() || y + h > rowsN()) { return false; }
    var occ = occupied(page, id);
    for (var dy = 0; dy < h; dy++) { for (var dx = 0; dx < w; dx++) { if (occ[(y + dy) + ':' + (x + dx)]) { return false; } } }
    return true;
  }

  // App-iconen en eigen afbeeldingen ophalen met de editor-toegang (een <img src> kan geen header meesturen).
  var ICONS = {};
  function loadIcon(src, apply, size) {
    var key = src + (size ? '@' + size : '');
    var c = ICONS[key];
    if (c && c.url) { apply(c.url); return; }
    if (!c) {
      c = ICONS[key] = { url: null, wait: [] };
      var x = new XMLHttpRequest();
      x.open('GET', '/api/icon?src=' + encodeURIComponent(src) + (size ? '&size=' + size : ''), true);
      x.responseType = 'blob';
      x.setRequestHeader(E.auth.header, E.auth.token);
      x.onreadystatechange = function () {
        if (x.readyState !== 4) { return; }
        if (x.status === 200) { c.url = URL.createObjectURL(x.response); }
        for (var i = 0; i < c.wait.length; i++) { if (c.url) { c.wait[i](c.url); } }
        c.wait = [];
        if (!c.url) { delete ICONS[key]; }
      };
      x.send();
    }
    c.wait.push(apply);
  }
  function isImgIcon(i) { return /^(app|img):/.test(i || ''); }

  function tileGlyph(t) {
    var k = t.kind || 'button';
    var glyphs = { slider: '▭', dial: '◎', touchpad: '▦', clock: '🕒', agenda: '📅', weather: '⛅', nowplaying: '♪',
                   timer: '⏱', pomodoro: '🍅', worldclock: '🌍', photos: '🖼', stats: '📊', terminal: '>_', ha: '🏠',
                   mqtt: '📡', plugin: '🧩' };
    return t.icon || glyphs[k] || '';
  }

  function drawGrid() {
    var g = $('grid'), L = E.layout, page = curPage();
    g.innerHTML = '';
    computeGeo();
    g.className = 'grid' + (cols() >= 8 && geo.s === 1 && !previewBox() ? ' dense' : '');
    var occ = occupied(page, null);
    for (var y = 0; y < rowsN(); y++) {
      for (var x = 0; x < cols(); x++) {
        if (occ[y + ':' + x]) { continue; }
        (function (sx, sy) {
          var s = el('div', 'slot');
          place(s, sx, sy, 1, 1);
          tap(s, function () { showPalette({ x: sx, y: sy }); });
          g.appendChild(s);
        })(x, y);
      }
    }
    for (var i = 0; i < page.tiles.length; i++) { g.appendChild(tileNode(page.tiles[i])); }
    markOverlaps();
  }

  function tileNode(t) {
    var n = el('div', 'etile' + (t.id === E.sel ? ' sel' : ''));
    n.setAttribute('data-id', t.id);
    place(n, t.x, t.y, t.w || 1, t.h || 1);
    // In het voorbeeld: kleine tegels net als op de tablet kleinere letters.
    if (previewBox()) {
      var pw = (t.w || 1) * geo.cw + ((t.w || 1) - 1) * geo.gap, ph = (t.h || 1) * geo.ch + ((t.h || 1) - 1) * geo.gap;
      if (pw < 130 || ph < 110) { n.className += ' tiny'; }
    }
    n.appendChild(el('span', 'kd', (t.kind && t.kind !== 'button') ? kindDef(t.kind).name : ''));
    var marks = (t.longPress ? '◷' : '') + (t.doubleTap ? '⁑' : '') + (t.toggle ? '⏻' : '');
    if (marks) { n.appendChild(el('span', 'gs', marks)); }
    if (t.color) { var cs = el('span', 'cstrip'); cs.style.background = t.color; n.appendChild(cs); n.style.borderColor = t.color; }
    if (isImgIcon(t.icon)) {
      var im = el('div', 'ici');
      loadIcon(t.icon, function (u) { im.style.backgroundImage = 'url(' + u + ')'; });
      n.appendChild(im);
    } else {
      var gl = tileGlyph(t);
      if (gl) { n.appendChild(el('div', 'ic', gl)); }
    }
    n.appendChild(el('div', 'lb', t.label));
    var rz = el('div', 'rz');
    n.appendChild(rz);
    bindDrag(n, t, rz);
    return n;
  }

  // Tegels die buiten het raster vallen of overlappen rood maken (bijv. na kleiner maken van het raster).
  function markOverlaps() {
    var page = curPage(), L = E.layout, seen = {}, bad = {};
    for (var i = 0; i < page.tiles.length; i++) {
      var t = page.tiles[i], w = t.w || 1, h = t.h || 1;
      if (t.x < 0 || t.y < 0 || t.x + w > cols() || t.y + h > rowsN()) { bad[t.id] = true; }
      for (var dy = 0; dy < h; dy++) {
        for (var dx = 0; dx < w; dx++) {
          var k = (t.y + dy) + ':' + (t.x + dx);
          if (seen[k]) { bad[t.id] = true; bad[seen[k]] = true; } else { seen[k] = t.id; }
        }
      }
    }
    var nodes = $('grid').querySelectorAll('.etile');
    for (var j = 0; j < nodes.length; j++) {
      var id = nodes[j].getAttribute('data-id');
      nodes[j].className = nodes[j].className.replace(/\s*\bbad\b/g, '') + (bad[id] ? ' bad' : '');
    }
  }

  // Slepen = verplaatsen; het hoekje rechtsonder = groter/kleiner. Muis en aanraking.
  function bindDrag(node, t, handle) {
    var start = null, mode = null, moved = false, cand = null;

    function point(e) {
      var p = e.touches ? (e.touches[0] || e.changedTouches[0]) : e;
      return { x: p.clientX, y: p.clientY };
    }
    function cellAt(px, py) {
      var r = $('grid').getBoundingClientRect(), sc = geo.s || 1;
      return { x: Math.floor(((px - r.left) / sc + geo.gap / 2) / (geo.cw + geo.gap)), y: Math.floor(((py - r.top) / sc + geo.gap / 2) / (geo.ch + geo.gap)) };
    }
    function down(e) {
      if (e.button !== undefined && e.button !== 0 && !e.touches) { return; }
      var p = point(e);
      mode = (e.target === handle) ? 'resize' : 'move';
      var c = cellAt(p.x, p.y);
      start = { px: p.x, py: p.y, offX: c.x - t.x, offY: c.y - t.y };
      moved = false;
      cand = null;
      if (hasTouch) { e.preventDefault(); }
      document.addEventListener(hasTouch ? 'touchmove' : 'mousemove', move, false);
      document.addEventListener(hasTouch ? 'touchend' : 'mouseup', up, false);
    }
    function move(e) {
      if (!start) { return; }
      e.preventDefault();
      var p = point(e);
      if (!moved && Math.abs(p.x - start.px) + Math.abs(p.y - start.py) < 6) { return; }
      moved = true;
      node.className = node.className.replace(/\s*\bdragging\b/g, '') + ' dragging';
      var c = cellAt(p.x, p.y), w = t.w || 1, h = t.h || 1;
      if (mode === 'move') {
        cand = { x: Math.max(0, Math.min(cols() - w, c.x - start.offX)), y: Math.max(0, Math.min(rowsN() - h, c.y - start.offY)), w: w, h: h };
      } else {
        cand = { x: t.x, y: t.y, w: Math.max(1, c.x - t.x + 1), h: Math.max(1, c.y - t.y + 1) };
      }
      place(node, cand.x, cand.y, cand.w, cand.h);
      var ok = fits(curPage(), t.id, cand.x, cand.y, cand.w, cand.h);
      node.className = node.className.replace(/\s*\bbad\b/g, '') + (ok ? '' : ' bad');
    }
    function up() {
      document.removeEventListener(hasTouch ? 'touchmove' : 'mousemove', move, false);
      document.removeEventListener(hasTouch ? 'touchend' : 'mouseup', up, false);
      if (!start) { return; }
      start = null;
      if (!moved) { E.sel = t.id; drawGrid(); drawSide(); return; }
      if (cand && fits(curPage(), t.id, cand.x, cand.y, cand.w, cand.h) &&
          (cand.x !== t.x || cand.y !== t.y || cand.w !== (t.w || 1) || cand.h !== (t.h || 1))) {
        snapshot();
        t.x = cand.x; t.y = cand.y; t.w = cand.w; t.h = cand.h;
        E.sel = t.id;
        afterChange(true);
      } else {
        drawGrid();
      }
    }
    on(node, hasTouch ? 'touchstart' : 'mousedown', down);
  }

  // ---------- velden ----------

  // Eén invoerveld volgens het schema. `get`/`set` lezen en schrijven de waarde; `rerender` tekent het paneel opnieuw.
  function field(f, get, set, ctx) {
    var row = el('div', 'row');
    var lab = el('label', null, f.label + (f.required ? ' *' : ''));
    var input, v = get();
    function changed(val) { set(val); afterChange(false); }

    switch (f.type) {
      case 'bool':
        lab = el('label');
        input = el('input', 'check');
        input.type = 'checkbox';
        input.checked = v === true;
        on(input, 'change', function () { snapshot(); changed(input.checked ? true : undefined); });
        lab.appendChild(input);
        lab.appendChild(document.createTextNode(f.label));
        row.appendChild(lab);
        return row;
      case 'select':
        input = el('select');
        for (var i = 0; i < f.options.length; i++) {
          var o = el('option', null, f.options[i] || T('— standaard —'));
          o.value = f.options[i];
          input.appendChild(o);
        }
        input.value = v || '';
        on(input, 'change', function () { snapshot(); changed(input.value || undefined); });
        break;
      case 'app':
        input = el('select');
        input.appendChild(optionEl('', T('— kies een app —')));
        var found = !v;
        for (var a = 0; a < E.catalog.apps.length; a++) {
          var ap = E.catalog.apps[a];
          input.appendChild(optionEl(ap.id, ap.name));
          if (ap.id === v || ap.name === v) { found = true; }
        }
        if (!found) { input.appendChild(optionEl(v, v)); }
        input.value = v || '';
        on(input, 'change', function () { snapshot(); changed(input.value || undefined); });
        break;
      case 'preset':
        input = el('select');
        input.appendChild(optionEl('', T('— kies een sneltoets —')));
        var groups = {}, order = [];
        for (var p = 0; p < E.catalog.presets.length; p++) {
          var pr = E.catalog.presets[p];
          if (!groups[pr.app]) { groups[pr.app] = el('optgroup'); groups[pr.app].label = pr.app; order.push(pr.app); }
          groups[pr.app].appendChild(optionEl(pr.id, pr.name + '  (' + pr.keys + ')'));
        }
        for (var g = 0; g < order.length; g++) { input.appendChild(groups[order[g]]); }
        input.value = v || '';
        on(input, 'change', function () { snapshot(); changed(input.value || undefined); });
        break;
      case 'plugin':
        input = el('select');
        input.appendChild(optionEl('', T('— kies een plugin —')));
        for (var q = 0; q < E.catalog.plugins.length; q++) {
          var pl = E.catalog.plugins[q];
          input.appendChild(optionEl(pl.id, pl.icon + ' ' + pl.name + (pl.enabled ? '' : ' (' + T('staat uit') + ')')));
        }
        input.value = v || '';
        on(input, 'change', function () { snapshot(); changed(input.value || undefined); if (ctx && ctx.rerender) { ctx.rerender(); } });
        break;
      case 'pluginAction':
      case 'pluginWidget':
        input = el('select');
        input.appendChild(optionEl('', T('— kies —')));
        var plug = null, pid = ctx && ctx.pluginId ? ctx.pluginId() : null;
        for (var r = 0; r < E.catalog.plugins.length; r++) { if (E.catalog.plugins[r].id === pid) { plug = E.catalog.plugins[r]; } }
        var list = plug ? (f.type === 'pluginAction' ? plug.actions : plug.widgets) : [];
        for (var s = 0; s < list.length; s++) { input.appendChild(optionEl(list[s].id, list[s].name)); }
        input.value = v || '';
        on(input, 'change', function () { snapshot(); changed(input.value || undefined); });
        break;
      case 'json':
        input = el('textarea');
        input.placeholder = f.placeholder || '';
        input.value = v === undefined ? '' : JSON.stringify(v, null, 1);
        var wasBad = false;
        on(input, 'focus', snapshot);
        on(input, 'input', function () {
          var txt = input.value.replace(/^\s+|\s+$/g, ''), ok = true, val;
          if (txt === '') { val = undefined; } else { try { val = JSON.parse(txt); } catch (e) { ok = false; } }
          if (ok && val !== undefined && (typeof val !== 'object' || val instanceof Array)) { ok = false; }
          input.className = ok ? '' : 'bad';
          if (ok !== !wasBad) { E.jsonBad += ok ? -1 : 1; wasBad = !ok; }
          if (ok) { changed(val); } else { updateButtons(); }
        });
        break;
      case 'zones':
        row.appendChild(lab);
        row.appendChild(zonesField(v, function (val) { snapshot(); changed(val); }));
        return row;
      case 'list':
        input = el('input');
        input.type = 'text';
        input.placeholder = f.placeholder || '';
        input.value = v ? v.join(', ') : '';
        on(input, 'focus', snapshot);
        on(input, 'input', function () {
          var parts = input.value.split(','), out = [];
          for (var i2 = 0; i2 < parts.length; i2++) { var x2 = parts[i2].replace(/^\s+|\s+$/g, ''); if (x2) { out.push(x2); } }
          changed(out.length ? out : undefined);
        });
        break;
      case 'number':
        input = el('input');
        input.type = 'number';
        input.step = 'any';
        input.placeholder = f.placeholder || '';
        input.value = v === undefined ? '' : String(v);
        on(input, 'focus', snapshot);
        on(input, 'input', function () {
          var n = parseFloat(input.value);
          changed(input.value === '' || isNaN(n) ? undefined : n);
        });
        break;
      case 'textarea':
        input = el('textarea');
        input.placeholder = f.placeholder || '';
        input.value = v || '';
        on(input, 'focus', snapshot);
        on(input, 'input', function () { changed(input.value || undefined); });
        break;
      default:
        input = el('input');
        input.type = 'text';
        input.placeholder = f.placeholder || '';
        input.value = v === undefined ? '' : String(v);
        input.setAttribute('autocapitalize', 'off');
        input.setAttribute('autocorrect', 'off');
        on(input, 'focus', snapshot);
        on(input, 'input', function () { changed(input.value || undefined); });
    }
    row.appendChild(lab);
    row.appendChild(input);
    return row;
  }

  function optionEl(value, text) { var o = el('option', null, text); o.value = value; return o; }

  // ---------- tijdzones (wereldklok) ----------

  var ZONE_REGIONS = { Europe: T('Europa'), America: T('Amerika'), Asia: T('Azië'), Africa: T('Afrika'), Australia: T('Australië'),
    Pacific: T('Stille Oceaan'), Atlantic: T('Atlantische Oceaan'), Indian: T('Indische Oceaan'), Antarctica: T('Antarctica'), Other: T('Overig') };
  var ZONE_ORDER = ['Europe', 'America', 'Asia', 'Africa', 'Australia', 'Pacific', 'Atlantic', 'Indian', 'Antarctica', 'Other'];
  var MAX_ZONES = 4; // zoveel toont de tablet

  function utcLabel(sec) {
    if (typeof sec !== 'number') { return ''; }
    var a = Math.abs(sec), h = Math.floor(a / 3600), m = Math.round((a % 3600) / 60);
    return 'UTC' + (sec < 0 ? '−' : '+') + h + (m ? ':' + (m < 10 ? '0' : '') + m : '');
  }

  // Keuzemenu met alle tijdzones, gegroepeerd per werelddeel: "Amsterdam (UTC+1)".
  function zoneSelect(value) {
    var sel = el('select'), zones = E.catalog.timeZones || [], groups = {}, known = false;
    for (var i = 0; i < zones.length; i++) {
      var z = zones[i];
      if (!groups[z.region]) { groups[z.region] = el('optgroup'); groups[z.region].label = ZONE_REGIONS[z.region] || z.region; }
      groups[z.region].appendChild(optionEl(z.id, z.name + ' (' + utcLabel(z.offset) + ')'));
      if (z.id === value) { known = true; }
    }
    if (value && !known) { sel.appendChild(optionEl(value, value + ' (' + T('onbekend') + ')')); }
    for (var j = 0; j < ZONE_ORDER.length; j++) { if (groups[ZONE_ORDER[j]]) { sel.appendChild(groups[ZONE_ORDER[j]]); } }
    for (var r in groups) { if (groups.hasOwnProperty(r) && ZONE_ORDER.indexOf(r) < 0) { sel.appendChild(groups[r]); } }
    sel.value = value || '';
    return sel;
  }

  // Lijst met een keuzemenu per tijdzone, een ✕ om te verwijderen en + TIJDZONE om er een toe te voegen.
  // Een zelf getypte plaatsnaam ("New York") omzetten naar de echte tijdzone ("America/New_York").
  function knownZone(v) {
    var zones = E.catalog.timeZones || [], want = String(v || '').replace(/^\s+|\s+$/g, '').toLowerCase();
    for (var i = 0; i < zones.length; i++) { if (zones[i].id === v) { return v; } }
    for (var j = 0; j < zones.length; j++) {
      var city = zones[j].id.split('/').pop().replace(/_/g, ' ').toLowerCase();
      if (city === want) { return zones[j].id; }
    }
    return v;
  }

  function zonesField(v, changed) {
    var box = el('div', 'zones'), cur = (v || []).slice();
    for (var c = 0; c < cur.length; c++) { cur[c] = knownZone(cur[c]); }
    function emit() { changed(cur.length ? cur.slice() : undefined); }
    function draw() {
      box.innerHTML = '';
      for (var i = 0; i < cur.length; i++) {
        (function (idx) {
          var r = el('div', 'zone-row'), sel = zoneSelect(cur[idx]), rm = el('span', 'link zone-rm', '✕');
          rm.title = T('Verwijderen');
          on(sel, 'change', function () { cur[idx] = sel.value; emit(); });
          tap(rm, function () { cur.splice(idx, 1); emit(); draw(); });
          r.appendChild(sel);
          r.appendChild(rm);
          box.appendChild(r);
        })(i);
      }
      if (!cur.length) { box.appendChild(el('div', 'hint', T('Nog geen tijdzones gekozen: de klok toont New York en Tokio.'))); }
      if (cur.length < MAX_ZONES) {
        var add = el('button', 'btn small', '+ ' + T('TIJDZONE'));
        tap(add, function () {
          var pick = ['Europe/London', 'America/New_York', 'Asia/Tokyo', 'Australia/Sydney', 'America/Los_Angeles', 'Asia/Dubai', 'UTC'];
          var z = 'UTC';
          for (var k = 0; k < pick.length; k++) { if (cur.indexOf(pick[k]) < 0) { z = pick[k]; break; } }
          cur.push(z); emit(); draw();
        });
        box.appendChild(add);
      }
    }
    draw();
    return box;
  }

  // ---------- acties ----------

  // Welke actietypes passen in dit vak? (schuif: alleen schuifacties; draaiknop: schuifacties, scrollen en gewone acties)
  function allowedActions(kind, slot, inMacro) {
    var out = [], a = E.schema.actions, plat = E.catalog.platform || 'macos';
    for (var i = 0; i < a.length; i++) {
      var d = a[i];
      if (d.platforms && d.platforms.indexOf(plat) < 0) { continue; }
      if (d.macroOnly && !inMacro) { continue; }
      if (inMacro) { if (d.slider || d.dialOnly || d.type === 'macro') { continue; } out.push(d); continue; }
      if (kind === 'slider') { if (d.slider) { out.push(d); } continue; }
      if (kind === 'dial') {
        if (slot === 'offAction' && (d.slider || d.dialOnly)) { continue; }
        out.push(d); continue;
      }
      if (d.slider || d.dialOnly) { continue; }
      out.push(d);
    }
    return out;
  }

  // Bewerker voor één actie. `get()` geeft de actie (of undefined), `set(a)` vervangt hem.
  function actionEditor(title, kind, slot, get, set, inMacro, optional, rerender) {
    var box = el('div', 'act');
    var head = el('div', 'act-head', title);
    box.appendChild(head);
    var a = get();
    var sel = el('select');
    if (optional) { sel.appendChild(optionEl('', T('— geen —'))); }
    var defs = allowedActions(kind, slot, inMacro), groups = {}, order = [];
    for (var i = 0; i < defs.length; i++) {
      var g = defs[i].group;
      if (!groups[g]) { groups[g] = el('optgroup'); groups[g].label = T(g); order.push(g); }
      groups[g].appendChild(optionEl(defs[i].type, defs[i].name));
    }
    for (var j = 0; j < order.length; j++) { sel.appendChild(groups[order[j]]); }
    if (a && a.type && !actionDef(a.type)) { sel.appendChild(optionEl(a.type, a.type + ' (' + T('onbekend') + ')')); }
    sel.value = a ? a.type : '';
    var r = el('div', 'row');
    r.appendChild(sel);
    box.appendChild(r);
    on(sel, 'change', function () {
      snapshot();
      set(sel.value ? { type: sel.value } : undefined);
      afterChange(false);
      rerender();
    });

    var d = a ? actionDef(a.type) : null;
    var fields = (d && d.fields) || [];
    for (var k = 0; k < fields.length; k++) {
      (function (f) {
        if (f.type === 'steps') { box.appendChild(stepsEditor(a, rerender)); return; }
        box.appendChild(field(f, function () { return get()[f.key]; }, function (v) { var cur = get(); cur[f.key] = v; },
          { rerender: rerender, pluginId: function () { return get().plugin; } }));
      })(fields[k]);
    }
    return box;
  }

  function stepsEditor(a, rerender) {
    var wrap = el('div', 'steps');
    wrap.appendChild(el('span', 'lbl', T('Stappen')));
    if (!a.steps) { a.steps = []; }
    for (var i = 0; i < a.steps.length; i++) {
      (function (idx) {
        var ed = actionEditor(T('Stap {0}', idx + 1), 'button', 'action', function () { return a.steps[idx]; },
          function (v) { a.steps[idx] = v || { type: 'delay', ms: 300 }; }, true, false, rerender);
        var tools = el('span', 'step-tools');
        var upB = el('span', null, '↑'), dnB = el('span', null, '↓'), rm = el('span', null, '✕');
        tap(upB, function () { if (idx > 0) { snapshot(); var x = a.steps.splice(idx, 1)[0]; a.steps.splice(idx - 1, 0, x); afterChange(false); rerender(); } });
        tap(dnB, function () { if (idx < a.steps.length - 1) { snapshot(); var x = a.steps.splice(idx, 1)[0]; a.steps.splice(idx + 1, 0, x); afterChange(false); rerender(); } });
        tap(rm, function () { snapshot(); a.steps.splice(idx, 1); afterChange(false); rerender(); });
        tools.appendChild(upB); tools.appendChild(dnB); tools.appendChild(rm);
        ed.firstChild.appendChild(tools);
        wrap.appendChild(ed);
      })(i);
    }
    var add = el('button', 'btn small', '+ ' + T('STAP'));
    tap(add, function () { snapshot(); a.steps.push({ type: 'keys.press' }); afterChange(false); rerender(); });
    var addDelay = el('button', 'btn small', '+ ' + T('PAUZE'));
    tap(addDelay, function () { snapshot(); a.steps.push({ type: 'delay', ms: 300 }); afterChange(false); rerender(); });
    wrap.appendChild(add);
    wrap.appendChild(addDelay);
    return wrap;
  }

  // ---------- zijpaneel ----------

  function drawSide() {
    var side = $('side');
    side.innerHTML = '';
    var t = E.sel ? findTile(E.sel) : null;
    if (t) { drawTilePanel(side, t); } else { drawPagePanel(side); }
  }

  function drawTilePanel(side, t) {
    var rerender = function () { drawSide(); drawGrid(); };
    var kd = kindDef(t.kind);

    var top = el('div', 'sec');
    top.appendChild(el('div', 'sec-title', '// ' + T('TEGEL')));
    var tools = el('div', 'row');
    var dup = el('button', 'btn small', T('DUPLICEREN'));
    tap(dup, function () { duplicateTile(t); });
    var del = el('button', 'btn small danger', T('VERWIJDEREN'));
    tap(del, function () { snapshot(); var ts = curPage().tiles; ts.splice(ts.indexOf(t), 1); E.sel = null; afterChange(true); });
    var desel = el('button', 'btn small', T('KLAAR'));
    tap(desel, function () { E.sel = null; drawGrid(); drawSide(); });
    tools.appendChild(dup); tools.appendChild(del); tools.appendChild(desel);
    top.appendChild(tools);

    top.appendChild(field({ key: 'label', label: T('Label'), type: 'text' }, function () { return t.label; }, function (v) { t.label = v || ''; drawGridSoon(); }));
    top.appendChild(iconPicker(t));
    top.appendChild(colorField(T('Kleur van de tegel'), function () { return t.color; }, function (v) { t.color = v; drawGridSoon(); }));

    var kinds = [];
    for (var k = 0; k < E.schema.kinds.length; k++) { kinds.push(E.schema.kinds[k].kind); }
    var kindRow = el('div', 'row');
    kindRow.appendChild(el('label', null, T('Soort')));
    var ksel = el('select');
    for (var j = 0; j < E.schema.kinds.length; j++) { ksel.appendChild(optionEl(E.schema.kinds[j].kind, E.schema.kinds[j].name)); }
    ksel.value = t.kind || 'button';
    on(ksel, 'change', function () { snapshot(); changeKind(t, ksel.value); afterChange(true); });
    kindRow.appendChild(ksel);
    top.appendChild(kindRow);

    var size = el('div', 'pair');
    size.appendChild(field({ key: 'w', label: T('Breedte'), type: 'number' }, function () { return t.w || 1; }, function (v) { resizeTile(t, v, t.h || 1); }));
    size.appendChild(field({ key: 'h', label: T('Hoogte'), type: 'number' }, function () { return t.h || 1; }, function (v) { resizeTile(t, t.w || 1, v); }));
    top.appendChild(size);
    top.appendChild(el('div', 'hint', 'Id: ' + t.id + ' · ' + T('sleep de tegel om te verplaatsen, het roze hoekje om te vergroten.')));
    side.appendChild(top);

    // Instellingen per soort
    var cfg = (kd.config || []).concat(kd.kind === 'button' ? (E.schema.buttonConfig || []) : []);
    if (cfg.length) {
      var cs = el('div', 'sec');
      cs.appendChild(el('div', 'sec-title', '// ' + T('INSTELLINGEN')));
      for (var c = 0; c < cfg.length; c++) {
        (function (f) {
          cs.appendChild(field(f, function () { return t.config ? t.config[f.key] : undefined; },
            function (v) { if (!t.config) { t.config = {}; } t.config[f.key] = v; },
            { rerender: rerender, pluginId: function () { return t.config ? t.config.plugin : null; } }));
        })(cfg[c]);
      }
      side.appendChild(cs);
    }

    // Acties
    var slots = kd.actions || [];
    if (slots.length) {
      var as = el('div', 'sec');
      as.appendChild(el('div', 'sec-title', '// ' + T('ACTIES')));
      var titles = kd.dial ? { action: T('Met de klok mee'), offAction: T('Tegen de klok in (niet bij volume/niveau)') }
        : { action: kd.kind === 'slider' ? T('Schuif bedient') : T('Tik'), longPress: T('Lang indrukken'), doubleTap: T('Dubbeltikken') };
      for (var s = 0; s < slots.length; s++) {
        (function (slot) {
          as.appendChild(actionEditor(titles[slot], kd.kind, slot, function () { return t[slot]; },
            function (v) { t[slot] = v; }, false, slot !== 'action', rerender));
        })(slots[s]);
      }
      if (kd.toggle) {
        as.appendChild(field({ key: 'toggle', label: T('Aan/uit-knop (Cyberpad onthoudt de stand)'), type: 'bool' },
          function () { return t.toggle; }, function (v) { t.toggle = v; drawSide(); }));
        if (t.toggle) {
          as.appendChild(actionEditor(T('Bij uitzetten (leeg = zelfde als tik)'), kd.kind, 'offAction', function () { return t.offAction; },
            function (v) { t.offAction = v; }, false, true, rerender));
        }
      }
      side.appendChild(as);
    }
  }

  // Icoon kiezen: emoji, app-icoon van de computer of een eigen afbeelding.
  function iconPicker(t) {
    var row = el('div', 'row');
    row.appendChild(el('label', null, T('Icoon')));
    var tab = E.iconTab || (/^app:/.test(t.icon || '') ? 'app' : /^img:/.test(t.icon || '') ? 'img' : 'emoji');
    var head = el('div', 'icon-tabs');
    var prev = el('span', 'icon-prev', isImgIcon(t.icon) ? '' : (t.icon || ''));
    if (isImgIcon(t.icon)) { loadIcon(t.icon, function (u) { prev.style.backgroundImage = 'url(' + u + ')'; }); }
    head.appendChild(prev);
    var tabs = [['emoji', 'EMOJI'], ['app', T('APP-ICOON')], ['img', T('AFBEELDING')]];
    for (var i = 0; i < tabs.length; i++) {
      (function (tb) {
        var b = el('span', tb[0] === tab ? 'on' : '', tb[1]);
        tap(b, function () { E.iconTab = tb[0]; drawSide(); });
        head.appendChild(b);
      })(tabs[i]);
    }
    var clear = el('span', '', T('GEEN'));
    tap(clear, function () { snapshot(); delete t.icon; afterChange(false); drawSide(); });
    head.appendChild(clear);
    row.appendChild(head);

    if (tab === 'emoji') {
      var inp = el('input');
      inp.type = 'text';
      inp.value = isImgIcon(t.icon) ? '' : (t.icon || '');
      inp.placeholder = T('emoji of tekst');
      on(inp, 'focus', snapshot);
      on(inp, 'input', function () { t.icon = inp.value || undefined; prev.textContent = inp.value; afterChange(false); });
      row.appendChild(inp);
      var emo = el('div', 'emoji');
      var list = (E.schema.emoji || '').match(/(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\uD800-\uDFFF])️?/g) || [];
      for (var j = 0; j < list.length; j++) {
        (function (ch) {
          var sp = el('span', null, ch);
          tap(sp, function () { snapshot(); t.icon = ch; afterChange(false); drawSide(); });
          emo.appendChild(sp);
        })(list[j]);
      }
      row.appendChild(emo);
    } else if (tab === 'app') {
      var sel = el('select');
      sel.appendChild(optionEl('', T('— kies een app —')));
      for (var a = 0; a < E.catalog.apps.length; a++) { sel.appendChild(optionEl('app:' + E.catalog.apps[a].id, E.catalog.apps[a].name)); }
      sel.value = /^app:/.test(t.icon || '') ? t.icon : '';
      on(sel, 'change', function () { if (!sel.value) { return; } snapshot(); t.icon = sel.value; afterChange(false); drawSide(); });
      row.appendChild(sel);
      row.appendChild(el('div', 'hint', T('Het icoon van een app op deze computer. Handig bij "App openen".')));
    } else {
      var up = el('button', 'btn small', T('AFBEELDING KIEZEN…'));
      tap(up, function () { E.iconTarget = t; $('f-icon').click(); });
      row.appendChild(up);
      row.appendChild(el('div', 'hint', T('PNG, JPEG of HEIC tot 700 KB. Wordt verkleind tot 256 px en op de computer bewaard.')));
    }
    return row;
  }

  function uploadIcon(file) {
    var t = E.iconTarget;
    if (!t || !file) { return; }
    if (file.size > 700 * 1024) { message(T('Afbeelding te groot (max. 700 KB).'), true); return; }
    var r = new FileReader();
    r.onload = function () {
      req('POST', '/api/editor/icon', { data: r.result }, function (st, d) {
        if (st === 200 && d && d.icon) { snapshot(); t.icon = d.icon; afterChange(false); drawSide(); }
        else { message((d && d.error) || T('Uploaden mislukt ({0})', st), true); }
      });
    };
    r.readAsDataURL(file);
  }

  // Kleurveld: kleurkiezer (waar de browser die heeft) plus tekstveld #rrggbb.
  function colorField(label, get, set, noClear) {
    var row = el('div', 'row');
    row.appendChild(el('label', null, label));
    var v = get() || '';
    var pick = el('input');
    try { pick.type = 'color'; } catch (e) { pick.type = 'text'; }
    pick.value = v || '#000000';
    var txt = el('input');
    txt.type = 'text';
    txt.value = v;
    txt.placeholder = noClear ? '#rrggbb' : T('geen');
    txt.style.width = '100px';
    txt.style.display = 'inline-block';
    txt.style.marginLeft = '6px';
    function apply(val) {
      var ok = val === '' ? !noClear : /^#[0-9a-fA-F]{6}$/.test(val);
      txt.className = ok ? '' : 'bad';
      if (ok) { set(val === '' ? undefined : val.toLowerCase()); afterChange(false); }
    }
    on(pick, 'focus', snapshot);
    on(txt, 'focus', snapshot);
    on(pick, 'input', function () { txt.value = pick.value; apply(pick.value); });
    on(pick, 'change', function () { txt.value = pick.value; apply(pick.value); });
    on(txt, 'input', function () { if (/^#[0-9a-fA-F]{6}$/.test(txt.value)) { pick.value = txt.value; } apply(txt.value); });
    if (pick.type === 'color') { row.appendChild(pick); }
    row.appendChild(txt);
    if (!noClear && v) {
      var cl = el('span', 'link', '  ' + T('WISSEN'));
      tap(cl, function () { snapshot(); set(undefined); afterChange(false); drawSide(); });
      row.appendChild(cl);
    }
    return row;
  }

  // ---------- thema-bouwer ----------

  var FONTS = [
    ['', T('— lettertype van het thema —')],
    ['Menlo, "SF Mono", Consolas, "Courier New", monospace', T('Mono (Menlo)')],
    ['"Courier New", Courier, monospace', T('Typemachine (Courier)')],
    ['"Avenir Next Condensed", "DIN Condensed", "Arial Narrow", sans-serif', T('Smal (Avenir Condensed)')],
    ['Futura, "Avenir Next", "Century Gothic", sans-serif', T('Geometrisch (Futura)')],
    ['-apple-system, "Helvetica Neue", "Segoe UI", Arial, sans-serif', T('Systeem (Helvetica)')],
    ['"American Typewriter", "Courier New", serif', 'American Typewriter'],
    ['Copperplate, "Copperplate Gothic Light", serif', 'Copperplate'],
    ['"Chalkboard SE", "Comic Sans MS", sans-serif', T('Krijtbord')]
  ];
  var COLOR_LABELS = { bg: T('Achtergrond'), bg2: T('Achtergrond 2'), text: T('Tekst'), accent: T('Accent'), accent2: T('Accent 2 (aan)'),
    accent2Text: T('Tekst op accent 2'), danger: T('Waarschuwing'), dangerText: T('Tekst waarschuwing'), ok: T('Goed'), okText: T('Tekst goed'),
    panel: T('Paneel (widgets)'), panelBorder: T('Rand paneel'), button: T('Knop'), buttonText: T('Tekst op knop'), buttonBorder: T('Rand knop'),
    buttonActive: T('Knop aan'), buttonActiveText: T('Tekst op knop aan') };
  // Deze mag een thema weglaten; dan volgen ze vanzelf uit accent en tekst ("automatisch").
  var OPTIONAL_COLORS = { panel: 1, panelBorder: 1, button: 1, buttonText: 1, buttonBorder: 1, buttonActive: 1, buttonActiveText: 1 };
  var EFFECT_LABELS = { scanlines: T('Scanlijnen'), glow: T('Gloed'), grid: T('Raster op achtergrond'), corner: T('Schuine hoek'), glitch: T('Glitch'), upper: T('HOOFDLETTERS'), bold: T('Vet') };

  function baseTheme() {
    for (var i = 0; i < E.themes.length; i++) { if (E.themes[i].id === E.layout.theme) { return E.themes[i]; } }
    return E.themes[0];
  }
  function resolved() {
    var b = baseTheme(), o = E.layout.themeOverrides || {}, t = clone(b), k;
    for (k in (o.colors || {})) { if (o.colors.hasOwnProperty(k)) { t.colors[k] = o.colors[k]; } }
    if (o.font) { t.font = o.font; }
    if (o.radius !== undefined) { t.radius = o.radius; }
    for (k in (o.effects || {})) { if (o.effects.hasOwnProperty(k)) { t.effects[k] = o.effects[k]; } }
    return t;
  }
  function overrides() { if (!E.layout.themeOverrides) { E.layout.themeOverrides = {}; } return E.layout.themeOverrides; }
  function hasOverrides() {
    var o = E.layout.themeOverrides;
    if (!o) { return false; }
    return !!(o.font || o.radius !== undefined || (o.colors && Object.keys(o.colors).length) || (o.effects && Object.keys(o.effects).length));
  }
  function hexA(hex, a) {
    var v = parseInt(hex.slice(1), 16);
    return 'rgba(' + ((v >> 16) & 255) + ',' + ((v >> 8) & 255) + ',' + (v & 255) + ',' + a + ')';
  }

  function showTheme() {
    $('modal-title').textContent = '// ' + T('THEMA');
    var body = $('modal-body');
    body.innerHTML = '';
    if (!E.themes.length) { body.appendChild(el('p', 'hint', T('Geen thema\'s gevonden.'))); $('modal').className = 'modal'; return; }
    var cards = el('div', 'themes');
    for (var i = 0; i < E.themes.length; i++) {
      (function (th) {
        var c = el('div', 'tcard' + (th.id === baseTheme().id ? ' on' : ''));
        c.style.background = th.colors.bg;
        c.style.color = th.colors.text;
        c.style.fontFamily = th.font;
        c.style.borderRadius = th.radius + 'px';
        var nm = el('div', 'tname', T(th.name));
        nm.style.color = th.colors.accent;
        c.appendChild(nm);
        var ds = el('div', 'tdesc', T(th.description || ''));
        ds.style.color = hexA(th.colors.text, 0.7);
        c.appendChild(ds);
        var keys = ['button', 'accent', 'accent2', 'text', 'danger'];
        for (var k = 0; k < keys.length; k++) {
          if (!th.colors[keys[k]]) { continue; }
          var sw = el('span', 'sw'); sw.style.background = th.colors[keys[k]]; c.appendChild(sw);
        }
        tap(c, function () {
          if (th.id === E.layout.theme) { return; }
          if (hasOverrides() && !window.confirm(T('Eigen aanpassingen op het huidige thema wissen?'))) { return; }
          snapshot();
          E.layout.theme = th.id;
          delete E.layout.themeOverrides;
          afterChange(false);
          showTheme();
        });
        cards.appendChild(c);
      })(E.themes[i]);
    }
    body.appendChild(cards);

    // Voorbeeld met de huidige (aangepaste) kleuren.
    var t = resolved();
    var pv = el('div', 'preview');
    pv.style.background = t.colors.bg;
    pv.style.fontFamily = t.font;
    var samples = [[T('KNOP'), 'b'], [T('KNOP AAN'), 'ba'], [T('PANEEL'), 'n'], ['⚠ ' + T('FOUT'), 'd']];
    for (var s2 = 0; s2 < samples.length; s2++) {
      var kind = samples[s2][1];
      var pt = el('div', 'pt', t.effects.upper ? samples[s2][0] : samples[s2][0].charAt(0) + samples[s2][0].slice(1).toLowerCase());
      pt.style.width = '110px';
      var c = t.colors;
      var col = kind === 'd' ? c.danger : kind === 'ba' ? c.accent2 : c.accent;
      if (kind === 'b') {
        pt.style.background = c.button || hexA(c.accent, 0.04);
        pt.style.borderColor = c.buttonBorder || hexA(c.accent, 0.45);
        pt.style.color = c.buttonText || hexA(c.text, 0.75);
      } else if (kind === 'ba') {
        pt.style.background = c.buttonActive || hexA(c.accent2, 0.12);
        pt.style.borderColor = c.accent2;
        pt.style.color = c.buttonActiveText || c.accent2Text;
      } else if (kind === 'n') {
        pt.style.background = c.panel || hexA(c.accent, 0.04);
        pt.style.borderColor = c.panelBorder || hexA(c.accent, 0.45);
        pt.style.color = c.text;
      } else {
        pt.style.borderColor = col;
        pt.style.color = c.dangerText;
        pt.style.background = hexA(col, 0.12);
      }
      if (t.effects.bold) { pt.style.fontWeight = 'bold'; }
      pt.style.borderRadius = t.radius + 'px';
      if (t.effects.glow) { pt.style.boxShadow = '0 0 14px ' + hexA(col, 0.35); }
      pv.appendChild(pt);
    }
    body.appendChild(el('div', 'sec-title', '// ' + T('VOORBEELD')));
    body.appendChild(pv);

    body.appendChild(el('div', 'sec-title', '// ' + T('AANPASSEN (BLIJFT BIJ DEZE LAYOUT)')));
    var cols = el('div', 'colors');
    for (var ck in COLOR_LABELS) {
      if (!COLOR_LABELS.hasOwnProperty(ck)) { continue; }
      (function (key) {
        cols.appendChild(colorField(COLOR_LABELS[key], function () { return resolved().colors[key]; }, function (v) {
          var o = overrides();
          if (!o.colors) { o.colors = {}; }
          if (v && v !== baseTheme().colors[key]) { o.colors[key] = v; } else { delete o.colors[key]; }
          clearTimeout(E.themeTimer);
          E.themeTimer = setTimeout(showTheme, 600);
        }, !OPTIONAL_COLORS[key]));
      })(ck);
    }
    body.appendChild(cols);

    var fr = el('div', 'row');
    fr.appendChild(el('label', null, T('Lettertype')));
    var fsel = el('select');
    var curFont = (E.layout.themeOverrides || {}).font || '';
    var found = false;
    for (var f = 0; f < FONTS.length; f++) { fsel.appendChild(optionEl(FONTS[f][0], FONTS[f][1])); if (FONTS[f][0] === curFont) { found = true; } }
    if (!found) { fsel.appendChild(optionEl(curFont, curFont)); }
    fsel.value = curFont;
    on(fsel, 'change', function () { snapshot(); var o = overrides(); if (fsel.value) { o.font = fsel.value; } else { delete o.font; } afterChange(false); showTheme(); });
    fr.appendChild(fsel);
    body.appendChild(fr);

    body.appendChild(field({ key: 'radius', label: T('Afronding (0–30 px)'), type: 'number', placeholder: String(baseTheme().radius) },
      function () { return (E.layout.themeOverrides || {}).radius; },
      function (v) { var o = overrides(); if (v === undefined || isNaN(v)) { delete o.radius; } else { o.radius = Math.max(0, Math.min(30, v)); } }));

    var fx = el('div', 'row');
    fx.appendChild(el('span', 'lbl', T('Effecten')));
    var chips = el('div', 'chips');
    for (var ek in EFFECT_LABELS) {
      if (!EFFECT_LABELS.hasOwnProperty(ek)) { continue; }
      (function (key) {
        var onE = !!t.effects[key];
        var ch = el('span', onE ? 'on' : '', EFFECT_LABELS[key]);
        tap(ch, function () {
          snapshot();
          var o = overrides();
          if (!o.effects) { o.effects = {}; }
          var want = !onE;
          if (want === !!baseTheme().effects[key]) { delete o.effects[key]; } else { o.effects[key] = want; }
          afterChange(false); showTheme();
        });
        chips.appendChild(ch);
      })(ek);
    }
    fx.appendChild(chips);
    body.appendChild(fx);

    var reset = el('button', 'btn small', T('TERUG NAAR HET THEMA ZELF'));
    tap(reset, function () { snapshot(); delete E.layout.themeOverrides; afterChange(false); showTheme(); });
    body.appendChild(reset);
    body.appendChild(el('p', 'hint', T('Na Opslaan krijgen alle tablets het nieuwe uiterlijk. Je aanpassingen gaan mee in een geëxporteerd .cyberpad-bestand. Lettertypen zijn standaardlettertypen van iPad, Mac en Windows; ontbreekt er een, dan gebruikt de tablet de volgende uit de lijst.')));
    $('modal').className = 'modal';
  }

  // ---------- toevoegen: lijst met alle mogelijkheden ----------

  var ACTION_ICON = {
    'media.playPause': '⏯', 'media.next': '⏭', 'media.previous': '⏮',
    'audio.volumeUp': '🔊', 'audio.volumeDown': '🔉', 'audio.mute': '🔇', 'audio.micMute': '🎙',
    'url.open': '🌐', 'keys.press': '⌨️', 'text.type': '✍️', 'preset': '🎛', 'shortcut.run': '⚡️', 'macro': '🧩',
    'system.darkMode': '🌗', 'system.keepAwake': '☕️', 'system.lock': '🔒', 'system.displayOff': '🌑',
    'system.screenshot': '📸', 'system.screenshotArea': '✂️', 'ha.toggle': '💡', 'ha.service': '🏠',
    'mqtt.publish': '📡', 'webhook.call': '🪝', 'plugin': '🧩'
  };
  var KIND_ICON = { weather: '⛅', nowplaying: '🎵', timer: '⏱', pomodoro: '🍅', worldclock: '🌍', photos: '🖼', stats: '📊',
    terminal: '>_', ha: '🏠', mqtt: '📡', plugin: '🧩', clock: '🕒', agenda: '📅', touchpad: '▦', dial: '◎', slider: '▭' };
  // Grootte in een standaardraster (5×3); op een compacte pagina wordt dat vanzelf meer vakken.
  var KIND_SIZE = { weather: [2, 1], nowplaying: [3, 1], timer: [1, 1], pomodoro: [1, 1], worldclock: [1, 1], photos: [2, 1],
    stats: [2, 1], terminal: [3, 1], ha: [1, 1], mqtt: [1, 1], plugin: [2, 1], clock: [2, 1], agenda: [2, 1],
    touchpad: [3, 3], dial: [1, 1], slider: [3, 1] };
  var KIND_CONFIG = { weather: { city: 'Amsterdam' }, timer: { seconds: 300 }, pomodoro: { work: 25, rest: 5 },
    worldclock: { zones: ['America/New_York', 'Asia/Tokyo'] }, photos: { seconds: 10 }, agenda: { count: 3 },
    touchpad: { speed: 1.5, natural: true }, terminal: { command: 'ping -c 5 1.1.1.1', timeout: 30 } };
  var PALETTE_GROUPS = ['Alles', 'Apps', 'Opdrachten', 'Media en geluid', 'Widgets', 'Bediening', 'Systeem',
    'Toetsen en tekst', 'Sneltoetsen', 'Smart home', 'Plugins'];

  // Alles wat je kunt toevoegen. `make()` geeft een tegel zonder id/positie; `todo` = nog in te vullen.
  function paletteItems() {
    var items = [], i, d;
    function add(group, name, sub, icon, make, todo) { items.push({ group: group, name: name, sub: sub || '', icon: icon, make: make, todo: todo }); }
    function button(label, icon, action) { return function () { return { label: label, icon: icon, action: action }; }; }

    add('Basis', T('Lege knop'), T('zelf een actie kiezen'), '➕', function () { return { label: T('Nieuw') }; }, T('actie'));

    // Veelgebruikte apps van Apple bovenaan, met hun naam in de taal van Cyberpad (zoeken op "agenda" werkt dus ook
    // als macOS de app "Calendar" noemt).
    var FAVORITE_APPS = [['com.apple.iCal', T('Agenda')], ['com.apple.reminders', T('Herinneringen')], ['com.apple.Notes', T('Notities')]];
    var favIds = {};
    for (i = 0; i < FAVORITE_APPS.length; i++) {
      (function (id, name) {
        var ap = null;
        for (var k = 0; k < E.catalog.apps.length; k++) { if (E.catalog.apps[k].id === id) { ap = E.catalog.apps[k]; } }
        if (!ap && (E.catalog.platform || 'macos') !== 'macos') { return; }
        favIds[id] = true;
        var sub = T('app openen') + (ap && ap.name !== name ? ' · ' + ap.name : '');
        add('Apps', name, sub, 'app:' + id, button(name, 'app:' + id, { type: 'app.open', app: id }));
      })(FAVORITE_APPS[i][0], FAVORITE_APPS[i][1]);
    }
    for (i = 0; i < E.catalog.apps.length; i++) {
      (function (ap) {
        if (favIds[ap.id]) { return; }
        add('Apps', ap.name, T('app openen'), 'app:' + ap.id, button(ap.name, 'app:' + ap.id, { type: 'app.open', app: ap.id }));
      })(E.catalog.apps[i]);
    }

    var sc = E.catalog.shortcuts || [];
    for (i = 0; i < sc.length; i++) {
      (function (name) { add('Opdrachten', name, T('opdracht uitvoeren'), '⚡️', button(name, '⚡️', { type: 'shortcut.run', shortcut: name })); })(sc[i]);
    }
    if ((E.catalog.platform || 'macos') === 'macos') {
      add('Opdrachten', T('Andere opdracht…'), sc.length ? T('naam zelf invullen') : T('nog geen opdrachten gevonden in de Opdrachten-app'), '⚡️',
        button(T('Opdracht'), '⚡️', { type: 'shortcut.run' }), T('naam van de opdracht'));
    }

    for (i = 0; i < E.schema.actions.length; i++) {
      d = E.schema.actions[i];
      if (d.macroOnly || d.dialOnly || (d.platforms && d.platforms.indexOf(E.catalog.platform || 'macos') < 0)) { continue; }
      (function (d) {
        var icon = ACTION_ICON[d.type] || '•';
        if (d.slider) {
          if (d.type === 'ha.level') { return; }
          add('Media en geluid', d.name.replace(/\s*\([^)]*\)$/, '') + ' — ' + T('schuif'), T('schuifbalk'), '▭', function () {
            return { label: d.name.replace(/ \(schuif\/draaiknop\)/, ''), kind: 'slider', action: { type: d.type } };
          });
          return;
        }
        var group = { Media: 'Media en geluid', Geluid: 'Media en geluid', Systeem: 'Systeem', Toetsen: 'Toetsen en tekst',
          'Apps en links': 'Toetsen en tekst', Automatisering: 'Toetsen en tekst', 'Smart home': 'Smart home' }[d.group];
        if (!group || d.type === 'app.open' || d.type === 'shortcut.run' || d.type === 'preset' || d.type === 'plugin') { return; }
        var needs = (d.fields || []).filter(function (f) { return f.required; }).map(function (f) { return f.label.toLowerCase(); }).join(', ');
        add(group, d.name, needs ? T('invullen: {0}', needs) : T(d.group).toLowerCase(), icon,
          function () { return { label: d.name.replace(/ aan\/uit$/, ''), icon: icon, action: { type: d.type } }; }, needs || null);
      })(d);
    }

    for (i = 0; i < E.catalog.presets.length; i++) {
      (function (p) {
        add('Sneltoetsen', p.app + ': ' + p.name, p.keys, '🎛', button(p.name, '🎛', { type: 'preset', preset: p.id }));
      })(E.catalog.presets[i]);
    }

    for (i = 0; i < E.schema.kinds.length; i++) {
      (function (k) {
        if (['button', 'slider', 'dial', 'touchpad', 'ha', 'mqtt', 'plugin'].indexOf(k.kind) >= 0) { return; }
        add('Widgets', k.name, T('widget'), KIND_ICON[k.kind] || '▣', function () {
          return { label: k.name, kind: k.kind, config: KIND_CONFIG[k.kind] ? clone(KIND_CONFIG[k.kind]) : undefined };
        }, k.kind === 'terminal' ? T('commando') : null);
      })(E.schema.kinds[i]);
    }

    add('Bediening', T('Aanraakpad'), T('tablet als trackpad'), '▦', function () { return { label: T('Aanraakpad'), kind: 'touchpad', config: clone(KIND_CONFIG.touchpad) }; });
    add('Bediening', T('Volumeknop'), T('draaiknop'), '◎', function () { return { label: T('Volume'), kind: 'dial', action: { type: 'audio.volume' } }; });
    add('Bediening', T('Scrollknop'), T('draaiknop'), '◎', function () { return { label: T('Scrollen'), kind: 'dial', action: { type: 'pointer.scroll' } }; });
    add('Bediening', T('Bureaubladen wisselen'), T('draaiknop'), '◎', function () {
      return { label: T('Bureaubladen'), kind: 'dial', action: { type: 'keys.press', keys: 'ctrl+right' }, offAction: { type: 'keys.press', keys: 'ctrl+left' } };
    });
    add('Bediening', T('Volumeschuif'), T('schuifbalk'), '▭', function () { return { label: T('Volume'), kind: 'slider', action: { type: 'audio.volume' } }; });

    add('Smart home', T('Home Assistant-schuif'), T('helderheid, rolluik, volume…'), '▭', function () {
      return { label: T('Helderheid'), kind: 'slider', action: { type: 'ha.level' } };
    }, T('entiteit'));
    add('Smart home', T('Home Assistant-waarde'), T('sensor, lamp of thermostaat tonen'), '🏠', function () {
      return { label: T('Sensor'), kind: 'ha', config: {} };
    }, T('entiteit'));
    add('Smart home', T('MQTT-waarde'), T('laatste bericht van een topic'), '📡', function () { return { label: 'MQTT', kind: 'mqtt', config: {} }; }, 'topic');

    for (i = 0; i < E.catalog.plugins.length; i++) {
      (function (pl) {
        var j;
        for (j = 0; j < pl.actions.length; j++) {
          (function (a) {
            add('Plugins', pl.name + ': ' + a.name, pl.enabled ? T('plugin-actie') : T('plugin staat uit'), pl.icon,
              button(a.name, pl.icon, { type: 'plugin', plugin: pl.id, action: a.id }));
          })(pl.actions[j]);
        }
        for (j = 0; j < pl.widgets.length; j++) {
          (function (w) {
            add('Plugins', pl.name + ': ' + w.name, pl.enabled ? T('plugin-widget') : T('plugin staat uit'), pl.icon, function () {
              return { label: w.name, kind: 'plugin', config: { plugin: pl.id, widget: w.id } };
            });
          })(pl.widgets[j]);
        }
      })(E.catalog.plugins[i]);
    }
    return items;
  }

  // Maat van een nieuwe tegel op de huidige pagina (compact = meer vakken).
  function sizeFor(tile) {
    var base = KIND_SIZE[tile.kind || 'button'] || [1, 1];
    var fx = cols() / E.layout.columns, fy = rowsN() / E.layout.rows;
    var w = Math.max(1, Math.min(cols(), Math.round(base[0] * fx))), h = Math.max(1, Math.min(rowsN(), Math.round(base[1] * fy)));
    return [w, h];
  }

  // Plek zoeken: eerst het aangetikte vak (eventueel iets naar links/boven geschoven), dan de eerste vrije plek;
  // past het nergens, dan zo groot als nog kan.
  function findSpot(w, h, target) {
    var page = curPage(), x, y;
    if (target) {
      for (y = target.y; y >= Math.max(0, target.y - h + 1); y--) {
        for (x = target.x; x >= Math.max(0, target.x - w + 1); x--) { if (fits(page, null, x, y, w, h)) { return { x: x, y: y, w: w, h: h }; } }
      }
    }
    for (y = 0; y <= rowsN() - h; y++) { for (x = 0; x <= cols() - w; x++) { if (fits(page, null, x, y, w, h)) { return { x: x, y: y, w: w, h: h }; } } }
    if (w > 1 || h > 1) { return findSpot(Math.max(1, w - 1), Math.max(1, h - (w > 1 ? 0 : 1)), target); }
    return null;
  }

  function placeItem(item, target) {
    var t = item.make(), sz = sizeFor(t);
    var spot = findSpot(sz[0], sz[1], target);
    if (!spot) { message(T('Geen ruimte meer op deze pagina. Maak de pagina compact of kies een andere pagina.'), true); return; }
    snapshot();
    t.id = uniqueTileId(t.label);
    t.x = spot.x; t.y = spot.y;
    if (spot.w > 1) { t.w = spot.w; }
    if (spot.h > 1) { t.h = spot.h; }
    curPage().tiles.push(t);
    E.sel = t.id;
    $('modal').className = 'modal hidden';
    afterChange(true);
    message(item.todo ? T('Toegevoegd. Vul rechts nog in: {0}.', item.todo) : T('Toegevoegd: {0}.', t.label), false);
  }

  function showPalette(target) {
    $('modal-title').textContent = '// ' + T('TOEVOEGEN') + (target ? ' · ' + T('VAK {0}', (target.x + 1) + ',' + (target.y + 1)) : '');
    var body = $('modal-body');
    body.innerHTML = '';
    var all = paletteItems();
    var search = el('input', 'pal-search');
    search.type = 'text';
    search.placeholder = T('Zoek: app, actie, widget, sneltoets…');
    search.setAttribute('autocapitalize', 'off');
    search.setAttribute('autocorrect', 'off');
    body.appendChild(search);
    var chips = el('div', 'chips pal-groups');
    body.appendChild(chips);
    var list = el('div', 'pal-list');
    body.appendChild(list);
    var group = E.palGroup || 'Alles';

    function counts() {
      var c = {};
      for (var i = 0; i < all.length; i++) { c[all[i].group] = (c[all[i].group] || 0) + 1; }
      return c;
    }
    var cnt = counts();
    function drawChips() {
      chips.innerHTML = '';
      for (var i = 0; i < PALETTE_GROUPS.length; i++) {
        (function (g) {
          if (g !== 'Alles' && !cnt[g]) { return; }
          var c = el('span', g === group ? 'on' : '', T(g) + (g === 'Alles' ? '' : ' ' + cnt[g]));
          tap(c, function () { group = E.palGroup = g; drawChips(); drawList(); });
          chips.appendChild(c);
        })(PALETTE_GROUPS[i]);
      }
    }
    function drawList() {
      list.innerHTML = '';
      var words = search.value.toLowerCase().split(/\s+/).filter(function (w) { return w; });
      var shown = 0;
      for (var i = 0; i < all.length && shown < 250; i++) {
        var it = all[i];
        if (group !== 'Alles' && it.group !== group && it.group !== 'Basis') { continue; }
        var hay = (it.name + ' ' + it.sub + ' ' + T(it.group)).toLowerCase(), ok = true;
        for (var w = 0; w < words.length; w++) { if (hay.indexOf(words[w]) < 0) { ok = false; break; } }
        if (!ok) { continue; }
        shown++;
        (function (it) {
          var row = el('div', 'pitem');
          var ic = el('span', 'pi-icon', isImgIcon(it.icon) ? '' : it.icon);
          if (isImgIcon(it.icon)) { loadIcon(it.icon, function (u) { ic.style.backgroundImage = 'url(' + u + ')'; }, 64); }
          row.appendChild(ic);
          var tx = el('span', 'pi-text');
          tx.appendChild(el('span', 'pi-name', it.name));
          tx.appendChild(el('span', 'pi-sub', (group === 'Alles' ? T(it.group) + ' · ' : '') + it.sub));
          row.appendChild(tx);
          tap(row, function () { placeItem(it, target); });
          list.appendChild(row);
        })(it);
      }
      if (!shown) { list.appendChild(el('p', 'hint', T('Niets gevonden.'))); }
    }
    on(search, 'input', drawList);
    drawChips();
    drawList();
    $('modal').className = 'modal';
    if (!hasTouch) { setTimeout(function () { search.focus(); }, 50); }
  }

  var drawSoon = null;
  function drawGridSoon() { clearTimeout(drawSoon); drawSoon = setTimeout(drawGrid, 150); }

  function changeKind(t, kind) {
    var kd = kindDef(kind);
    t.kind = kind;
    t.config = undefined;
    var keep = kd.actions || [];
    var slots = ['action', 'longPress', 'doubleTap', 'offAction'];
    for (var i = 0; i < slots.length; i++) { if (keep.indexOf(slots[i]) < 0 && !(kd.toggle && slots[i] === 'offAction')) { delete t[slots[i]]; } }
    if (!kd.toggle) { delete t.toggle; }
    // Schuif/draaiknop: alleen een passende actie houden.
    if (t.action) {
      var d = actionDef(t.action.type);
      var ok = kind === 'slider' ? d && d.slider : kind === 'dial' ? true : !(d && (d.slider || d.dialOnly));
      if (!ok) { delete t.action; }
    }
    if (kind === 'slider' && !t.action) { t.action = { type: 'audio.volume' }; }
    if (kind === 'dial' && !t.action) { t.action = { type: 'audio.volume' }; }
    var minW = kd.minW || 1, minH = kd.minH || 1;
    if ((t.w || 1) < minW || (t.h || 1) < minH) {
      var w = Math.max(t.w || 1, minW), h = Math.max(t.h || 1, minH);
      if (fits(curPage(), t.id, t.x, t.y, w, h)) { t.w = w; t.h = h; }
    }
  }

  function resizeTile(t, w, h) {
    w = Math.max(1, Math.round(w || 1)); h = Math.max(1, Math.round(h || 1));
    if (fits(curPage(), t.id, t.x, t.y, w, h)) { t.w = w; t.h = h; drawGrid(); }
    else { message(T('Past niet: er staat iets in de weg of het valt buiten het raster.'), true); }
  }

  function duplicateTile(t) {
    var page = curPage(), L = E.layout, w = t.w || 1, h = t.h || 1;
    for (var y = 0; y <= rowsN() - h; y++) {
      for (var x = 0; x <= cols() - w; x++) {
        if (fits(page, null, x, y, w, h)) {
          snapshot();
          var c = clone(t);
          c.id = uniqueTileId(t.label);
          c.x = x; c.y = y;
          page.tiles.push(c);
          E.sel = c.id;
          afterChange(true);
          return;
        }
      }
    }
    message(T('Geen vrije plek op deze pagina voor een kopie.'), true);
  }

  function drawPagePanel(side) {
    var pg = curPage(), L = E.layout;
    var sec = el('div', 'sec');
    sec.appendChild(el('div', 'sec-title', '// ' + T('PAGINA')));
    sec.appendChild(field({ key: 'name', label: T('Naam'), type: 'text' }, function () { return pg.name; }, function (v) { pg.name = v || ''; drawPages(); }));
    sec.appendChild(field({ key: 'apps', label: T('Contextpagina voor apps'), type: 'list', placeholder: 'com.adobe.Photoshop, Final Cut Pro' },
      function () { return pg.apps; }, function (v) { pg.apps = v; drawPages(); }));
    sec.appendChild(el('div', 'hint', T('Komt een van deze apps vooraan op de computer, dan springt de tablet naar deze pagina. Bundle-id of app-naam.')));
    var tools = el('div', 'row');
    var left = el('button', 'btn small', '← ' + T('NAAR LINKS')), right = el('button', 'btn small', T('NAAR RECHTS') + ' →'), del = el('button', 'btn small danger', T('PAGINA VERWIJDEREN'));
    tap(left, function () { movePage(-1); });
    tap(right, function () { movePage(1); });
    tap(del, function () {
      if (L.pages.length < 2) { message(T('De laatste pagina kan niet weg.'), true); return; }
      if (!window.confirm(T('Pagina "{0}" met {1} tegels verwijderen?', pg.name, pg.tiles.length))) { return; }
      snapshot();
      L.pages.splice(E.page, 1);
      var prof = L.profiles || [];
      for (var i = 0; i < prof.length; i++) { prof[i].pages = prof[i].pages.filter(function (id) { return id !== pg.id; }); }
      E.page = Math.max(0, E.page - 1);
      afterChange(true);
    });
    tools.appendChild(left); tools.appendChild(right); tools.appendChild(del);
    sec.appendChild(tools);
    side.appendChild(sec);

    // Raster van deze pagina: standaard, compact (2× zoveel vakken = halve tegels) of eigen maat.
    var pgr = el('div', 'sec');
    pgr.appendChild(el('div', 'sec-title', '// ' + T('RASTER VAN DEZE PAGINA')));
    var modeRow = el('div', 'row');
    var msel = el('select');
    var std = L.columns + '×' + L.rows;
    msel.appendChild(optionEl('std', T('Standaard ({0}, zoals de layout)', std)));
    msel.appendChild(optionEl('compact', T('Compact ({0}: tegels half zo groot)', Math.min(12, L.columns * 2) + '×' + Math.min(8, L.rows * 2))));
    msel.appendChild(optionEl('own', T('Eigen maat')));
    var mode = !pg.columns ? 'std' : (pg.columns === Math.min(12, L.columns * 2) && pg.rows === Math.min(8, L.rows * 2) ? 'compact' : 'own');
    msel.value = mode;
    on(msel, 'change', function () {
      snapshot();
      if (msel.value === 'std') { delete pg.columns; delete pg.rows; }
      else if (msel.value === 'compact') { scalePage(pg, Math.min(12, L.columns * 2), Math.min(8, L.rows * 2)); }
      else { pg.columns = pg.columns || L.columns; pg.rows = pg.rows || L.rows; }
      afterChange(true);
    });
    modeRow.appendChild(msel);
    pgr.appendChild(modeRow);
    if (mode === 'own') {
      var own = el('div', 'pair');
      own.appendChild(field({ key: 'pcols', label: T('Kolommen (1–12)'), type: 'number' }, function () { return pg.columns; },
        function (v) { if (v >= 1 && v <= 12) { pg.columns = Math.round(v); drawGrid(); } }));
      own.appendChild(field({ key: 'prows', label: T('Rijen (1–8)'), type: 'number' }, function () { return pg.rows; },
        function (v) { if (v >= 1 && v <= 8) { pg.rows = Math.round(v); drawGrid(); } }));
      pgr.appendChild(own);
    }
    pgr.appendChild(el('div', 'hint', T('Compact: kies dit om meer, kleinere tegels op één pagina te zetten. Bestaande tegels worden mee vergroot, zodat ze even groot blijven.')));
    side.appendChild(pgr);

    var g = el('div', 'sec');
    g.appendChild(el('div', 'sec-title', '// ' + T('STANDAARDRASTER (ALLE ANDERE PAGINA\'S)')));
    var pair = el('div', 'pair');
    pair.appendChild(field({ key: 'columns', label: T('Kolommen (1–12)'), type: 'number' }, function () { return L.columns; },
      function (v) { if (v >= 1 && v <= 12) { L.columns = Math.round(v); drawGrid(); } }));
    pair.appendChild(field({ key: 'rows', label: T('Rijen (1–8)'), type: 'number' }, function () { return L.rows; },
      function (v) { if (v >= 1 && v <= 8) { L.rows = Math.round(v); drawGrid(); } }));
    g.appendChild(pair);
    g.appendChild(el('div', 'hint', T('Tik op een leeg vak (+) of op + TOEVOEGEN om iets toe te voegen. Tegels die na het verkleinen buiten het raster vallen, worden rood.')));
    side.appendChild(g);

    if (E.problems.length) {
      var ps = el('div', 'sec');
      ps.appendChild(el('div', 'sec-title', '// ' + T('PROBLEMEN')));
      for (var i = 0; i < E.problems.length; i++) { ps.appendChild(el('div', 'hint', '⚠ ' + E.problems[i])); }
      side.appendChild(ps);
    }
  }

  // Pagina naar een ander raster: posities en maten mee schalen, zodat alles even groot blijft.
  function scalePage(pg, c, r) {
    var oc = pg.columns || E.layout.columns, or = pg.rows || E.layout.rows;
    var fx = c / oc, fy = r / or;
    for (var i = 0; i < pg.tiles.length; i++) {
      var t = pg.tiles[i];
      t.x = Math.round(t.x * fx); t.y = Math.round(t.y * fy);
      t.w = Math.max(1, Math.round((t.w || 1) * fx)); t.h = Math.max(1, Math.round((t.h || 1) * fy));
    }
    pg.columns = c; pg.rows = r;
  }

  function movePage(dir) {
    var L = E.layout, i = E.page, j = i + dir;
    if (j < 0 || j >= L.pages.length) { return; }
    snapshot();
    var p = L.pages.splice(i, 1)[0];
    L.pages.splice(j, 0, p);
    E.page = j;
    afterChange(true);
  }

  // ---------- profielen ----------

  var DAYNAMES = T('MA DI WO DO VR ZA ZO').split(' ');

  function showProfiles() {
    $('modal-title').textContent = '// ' + T('PROFIELEN');
    var body = $('modal-body');
    body.innerHTML = '';
    var L = E.layout;
    if (!L.profiles) { L.profiles = []; }
    body.appendChild(el('p', 'hint', T('Een profiel bepaalt welke pagina\'s een tablet ziet. Het eerste profiel waarvan een tijdregel past, geldt; anders het standaardprofiel. Per tablet kun je in de menubalk ook een vast profiel kiezen. Zonder profielen ziet elke tablet alle pagina\'s.')));
    for (var i = 0; i < L.profiles.length; i++) { body.appendChild(profileBox(L.profiles[i], i)); }
    var add = el('button', 'btn', '+ ' + T('PROFIEL'));
    tap(add, function () {
      var name = window.prompt(T('Naam van het profiel'), T('Nieuw profiel'));
      if (!name) { return; }
      snapshot();
      var ids = {}, b = slug(name) || 'profiel', id = b, n = 2;
      for (var k = 0; k < L.profiles.length; k++) { ids[L.profiles[k].id] = true; }
      while (ids[id]) { id = b + '-' + n; n++; }
      var pages = [];
      for (var p = 0; p < L.pages.length; p++) { pages.push(L.pages[p].id); }
      L.profiles.push({ id: id, name: name, pages: pages });
      afterChange(false);
      showProfiles();
    });
    body.appendChild(add);
    $('modal').className = 'modal';
  }

  function profileBox(pr, idx) {
    var L = E.layout, box = el('div', 'prof');
    box.appendChild(field({ key: 'name', label: T('Naam'), type: 'text' }, function () { return pr.name; }, function (v) { pr.name = v || ''; }));
    var chips = el('div', 'row');
    chips.appendChild(el('span', 'lbl', T('Pagina\'s (volgorde zoals in de editor)')));
    var cw = el('div', 'chips');
    for (var i = 0; i < L.pages.length; i++) {
      (function (pg) {
        var onp = pr.pages.indexOf(pg.id) >= 0;
        var c = el('span', onp ? 'on' : '', pg.name);
        tap(c, function () {
          snapshot();
          if (onp) { pr.pages = pr.pages.filter(function (x) { return x !== pg.id; }); }
          else {
            var order = [];
            for (var j = 0; j < L.pages.length; j++) { var id = L.pages[j].id; if (id === pg.id || pr.pages.indexOf(id) >= 0) { order.push(id); } }
            pr.pages = order;
          }
          afterChange(false); showProfiles();
        });
        cw.appendChild(c);
      })(L.pages[i]);
    }
    chips.appendChild(cw);
    box.appendChild(chips);
    box.appendChild(field({ key: 'default', label: T('Standaardprofiel (als geen tijdregel past)'), type: 'bool' }, function () { return pr['default']; }, function (v) {
      for (var k = 0; k < L.profiles.length; k++) { delete L.profiles[k]['default']; }
      if (v) { pr['default'] = true; }
      showProfiles();
    }));

    var rules = pr.when || [];
    for (var r = 0; r < rules.length; r++) {
      (function (rule, ri) {
        var rb = el('div', 'rule');
        var days = el('div', 'chips');
        for (var d = 1; d <= 7; d++) {
          (function (day) {
            var onD = rule.days ? rule.days.indexOf(day) >= 0 : false;
            var c = el('span', onD ? 'on' : '', DAYNAMES[day - 1]);
            tap(c, function () {
              snapshot();
              var ds = rule.days ? rule.days.slice() : [];
              if (onD) { ds = ds.filter(function (x) { return x !== day; }); } else { ds.push(day); ds.sort(); }
              rule.days = ds.length ? ds : undefined;
              afterChange(false); showProfiles();
            });
            days.appendChild(c);
          })(d);
        }
        rb.appendChild(days);
        rb.appendChild(el('div', 'hint', rule.days ? '' : T('Geen dag gekozen = elke dag.')));
        var tp = el('div', 'pair');
        tp.appendChild(field({ key: 'from', label: T('Van (UU:MM)'), type: 'text', placeholder: '08:00' }, function () { return rule.from; }, function (v) { rule.from = v; }));
        tp.appendChild(field({ key: 'to', label: T('Tot (UU:MM)'), type: 'text', placeholder: '18:00' }, function () { return rule.to; }, function (v) { rule.to = v; }));
        rb.appendChild(tp);
        var rm = el('span', 'link', T('REGEL VERWIJDEREN'));
        tap(rm, function () { snapshot(); pr.when.splice(ri, 1); if (!pr.when.length) { delete pr.when; } afterChange(false); showProfiles(); });
        rb.appendChild(rm);
        box.appendChild(rb);
      })(rules[r], r);
    }
    var tools = el('div', 'row');
    var addRule = el('button', 'btn small', '+ ' + T('TIJDREGEL'));
    tap(addRule, function () { snapshot(); if (!pr.when) { pr.when = []; } pr.when.push({ days: [1, 2, 3, 4, 5], from: '08:00', to: '18:00' }); afterChange(false); showProfiles(); });
    var del = el('button', 'btn small danger', T('PROFIEL VERWIJDEREN'));
    tap(del, function () { if (!window.confirm(T('Profiel "{0}" verwijderen?', pr.name))) { return; } snapshot(); L.profiles.splice(idx, 1); afterChange(false); showProfiles(); });
    tools.appendChild(addRule); tools.appendChild(del);
    box.appendChild(tools);
    box.appendChild(el('div', 'hint', 'Id: ' + pr.id + ' · ' + T('Focus-automatisering') + ': cyberpad://profile/' + pr.id));
    return box;
  }

  // ---------- opslaan, exporteren, importeren ----------

  function save() {
    if (E.jsonBad) { message(T('Er staat nog een fout in een JSON-veld (rood omrand).'), true); return; }
    var data = clean(E.layout);
    $('b-save').disabled = true;
    req('PUT', '/api/editor/layout', { layout: data, baseRevision: E.revision }, function (st, res) {
      $('b-save').disabled = false;
      if (st === 200 && res && res.ok) {
        E.revision = res.revision;
        E.saved = JSON.stringify(data);
        E.problems = [];
        updateButtons();
        message(T('Opgeslagen. Alle tablets zijn bijgewerkt.'), false);
      } else if (st === 409) {
        message(T('De layout is intussen elders gewijzigd (bijv. in een ander venster of in layout.json).\nExporteer je werk eventueel eerst, en laad dan opnieuw.'), true, true);
      } else if (st === 403) {
        message(T('Niet opgeslagen: deze tablet is niet meer gekoppeld. Exporteer je werk eventueel en koppel opnieuw.'), true, true);
      } else {
        E.problems = (res && res.errors) || [T('Opslaan mislukt ({0})', st)];
        updateButtons();
        drawSide();
        message(T('Niet opgeslagen:') + '\n• ' + E.problems.join('\n• '), true, true);
      }
    });
  }

  function exportLayout() {
    var text = JSON.stringify({ format: 'cyberpad-layout', version: 1, exported: new Date().toISOString(), layout: clean(E.layout) }, null, 2);
    var name = 'cyberpad-' + new Date().toISOString().slice(0, 10) + '.cyberpad';
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cyberpad) {
      window.webkit.messageHandlers.cyberpad.postMessage({ type: 'export', data: text, name: name });
      return;
    }
    try {
      var blob = new Blob([text], { type: 'application/json' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = name;
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.parentNode.removeChild(a); }, 1000);
    } catch (e) {
      message(T('Exporteren lukt niet in deze browser.'), true);
    }
  }

  function importFile(file) {
    var r = new FileReader();
    r.onload = function () {
      var obj;
      try { obj = JSON.parse(r.result); } catch (e) { message(T('Dit is geen geldig .cyberpad-bestand.'), true); return; }
      var l = obj && obj.format === 'cyberpad-layout' ? obj.layout : obj;
      if (!l || !l.pages || !l.columns || !l.rows) { message(T('Dit bestand bevat geen Cyberpad-layout.'), true); return; }
      if (!window.confirm(T('Huidige layout vervangen door "{0}"? Pas na Opslaan geldt hij; tot dan kun je terug met ↶.', file.name))) { return; }
      snapshot();
      E.layout = l;
      if (!E.layout.pages.length) { E.layout.pages = [{ id: 'main', name: 'Main', tiles: [] }]; }
      E.page = 0; E.sel = null;
      afterChange(true);
      message(T('Geïmporteerd. Controleer en klik Opslaan.'), false);
    };
    r.readAsText(file);
  }

  // ---------- starten en toegang ----------

  function loadAll() {
    var left = 4, failed = null;
    function done() {
      left--;
      if (left) { return; }
      if (failed) { gate(failed); return; }
      $('gate').className = 'gate hidden';
      E.saved = JSON.stringify(clean(E.layout));
      loadPreview();
      drawPreviewBar();
      drawPages(); drawGrid(); drawSide(); updateButtons(); validate();
    }
    var x = new XMLHttpRequest();
    x.open('GET', 'schema.json', true);
    x.onreadystatechange = function () {
      if (x.readyState !== 4) { return; }
      try { E.schema = translateSchema(JSON.parse(x.responseText)); } catch (e) { failed = T('Schema ontbreekt.'); }
      done();
    };
    x.send();
    req('GET', '/api/editor/catalog', null, function (st, d) { if (st === 200 && d) { E.catalog = d; } done(); });
    req('GET', '/api/editor/themes', null, function (st, d) { if (st === 200 && d && d.length) { E.themes = d; } done(); });
    req('GET', '/api/editor/layout', null, function (st, d) {
      if (st === 200 && d && d.layout) { E.layout = d.layout; E.revision = d.revision; }
      else if (st === 403) { failed = 'permission'; }
      else { failed = T('Kan de layout niet laden ({0}).', st); }
      done();
    });
  }

  function gate(reason) {
    $('gate').className = 'gate';
    var txt = $('gate-text');
    $('gate-btn').className = 'btn primary hidden';
    if (reason !== 'permission') { txt.textContent = reason; return; }
    txt.textContent = E.auth.mode === 'mac'
      ? T('Deze editor is verlopen. Sluit het venster en open hem opnieuw via de menubalk.')
      : T('Deze tablet is niet (meer) gekoppeld. Ga terug naar de knoppen en koppel opnieuw.');
  }

  function init() {
    translateDom();
    var m = /[#&]mac=([0-9a-f]{64})/.exec(location.hash);
    if (m) {
      store('cyberpad.editor', m[1]);
      if (window.history && history.replaceState) { history.replaceState(null, '', location.pathname); }
    }
    var macToken = store('cyberpad.editor');
    if (macToken) {
      E.auth = { mode: 'mac', header: 'X-Cyberpad-Editor', token: macToken };
    } else {
      var t = local('cyberpad.token');
      if (!t) { gate(T('Deze tablet is nog niet gekoppeld. Ga terug naar de knoppen en koppel eerst.')); return; }
      E.auth = { mode: 'tablet', header: 'X-Cyberpad-Token', token: t };
      $('b-close').className = 'btn close';
    }

    var ml = $('more-lang');
    for (var li = 0; li < LANGS.length; li++) {
      (function (lg) {
        var it = el('span', 'more-item' + (lg[0] === (window.CP_LANG || 'en') ? ' on' : ''), '🌐 ' + lg[1]);
        tap(it, function () { $('more-menu').className = 'more-menu hidden'; switchLanguage(lg[0]); });
        ml.appendChild(it);
      })(LANGS[li]);
    }
    tap($('b-undo'), undo);
    tap($('b-redo'), redoIt);
    tap($('b-save'), save);
    tap($('b-profiles'), showProfiles);
    tap($('b-theme'), showTheme);
    tap($('b-add'), function () { showPalette(null); });
    on($('f-icon'), 'change', function () { var f = $('f-icon').files[0]; if (f) { uploadIcon(f); } $('f-icon').value = ''; });
    function closeMore() { $('more-menu').className = 'more-menu hidden'; }
    tap($('b-more'), function (e) {
      if (e && e.stopPropagation) { e.stopPropagation(); }
      $('more-menu').className = /hidden/.test($('more-menu').className) ? 'more-menu' : 'more-menu hidden';
    });
    on(document, 'click', function (e) { if (!$('more-menu').contains(e.target) && e.target !== $('b-more')) { closeMore(); } });
    tap($('b-export'), function () { closeMore(); exportLayout(); });
    tap($('b-import'), function () { closeMore(); $('f-import').click(); });
    on($('f-import'), 'change', function () { var f = $('f-import').files[0]; if (f) { importFile(f); } $('f-import').value = ''; });
    tap($('modal-close'), function () { $('modal').className = 'modal hidden'; drawPages(); drawGrid(); drawSide(); });
    tap($('problems'), function () { E.sel = null; drawGrid(); drawSide(); });
    tap($('msg'), function () { $('msg').className = 'msg hidden'; });
    tap($('b-close'), function () {
      if (E.layout && isDirty() && !window.confirm(T('Niet-opgeslagen wijzigingen weggooien?'))) { return; }
      E.leaving = true;
      location.href = '/';
    });
    on(window, 'resize', function () { if (E.layout) { drawGrid(); } });
    on(window, 'beforeunload', function (e) { if (E.layout && !E.leaving && isDirty()) { e.returnValue = T('Niet opgeslagen'); return e.returnValue; } });
    on(document, 'keydown', function (e) {
      var meta = e.metaKey || e.ctrlKey, tag = (e.target.tagName || '').toLowerCase();
      if (meta && e.key === 's') { e.preventDefault(); save(); }
      else if (meta && e.key === 'z' && tag !== 'input' && tag !== 'textarea') { e.preventDefault(); if (e.shiftKey) { redoIt(); } else { undo(); } }
      else if ((e.key === 'Backspace' || e.key === 'Delete') && E.sel && tag !== 'input' && tag !== 'textarea' && tag !== 'select') {
        e.preventDefault(); snapshot(); var ts = curPage().tiles; ts.splice(ts.indexOf(findTile(E.sel)), 1); E.sel = null; afterChange(true);
      } else if (e.key === 'Escape') { E.sel = null; drawGrid(); drawSide(); $('modal').className = 'modal hidden'; }
    });
    loadAll();
  }

  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', init, false); } else { init(); }
})();
