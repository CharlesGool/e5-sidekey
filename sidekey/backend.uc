// 侧键开关热点 (Side Key Hotspot, id sidekey): a tap on the side key (F1)
// opens the hotspot page as before; held, the motor pulses once and the
// hotspot turns on or off.  The key is the screen's own (app.js, its keydown
// listener), so this patches app.js with patch.js, put in before the key lock:
// its listeners come before the screen's, ask GET /mode, and take the key
// when it is ours.  The lock screen (mobile.js) takes every key but power and
// volume with a listener added before app.js's, so index.html gets early.html
// too, before mobile.js: a listener ahead of it that hands the key to app.js's
// block.  An image update brings unpatched files: the notification poll
// (manifest "notifications") patches them again; the screen restarts once
// after each patch, to load it.  With the app removed there is no /mode and
// the key is the screen's own again; POST /unpatch takes the blocks out.
//
//   GET  /mode            {toggle, hold, dark, locked, vibrate}, for the patched app.js
//   GET  /status          the settings and the patch
//   POST /mode            {"mode": "toggle"|"page"}
//   POST /unpatch         app.js and index.html as they came, the screen restarted
//   GET  /notifications   (none: only the patch check, once a minute)

'use strict';

import { readfile, writefile, rename, stat } from 'fs';

const DIR = '/etc/e5-infoscreen/plugins/sidekey';
const WWW = '/usr/share/e5-infoscreen/www';
const CFG = 'e5-plugin-sidekey';
const MODES = [ 'toggle', 'page' ];
// the files patched: a block of ours put in before an anchor
const FILES = [
	{ file: `${WWW}/app.js`, block: 'patch.js', anchor: '/* ---------- key lock ---------- */',
	  begin: '/* BEGIN e5-sidekey', end: '/* END e5-sidekey */\n', need: true },
	// (a screen without mobile.js has no lock screen: nothing to get ahead of)
	{ file: `${WWW}/index.html`, block: 'early.html', anchor: '<script src="mobile.js"></script>',
	  begin: '<script>/* BEGIN e5-sidekey', end: '/* END e5-sidekey */</script>\n', need: false }
];

return function(ctx) {
	function count(s, part) { return length(split(s, part)) - 1; }

	function settings() {
		let c = ctx.uci();
		let mode = c.get(CFG, 'settings', 'mode') ?? 'toggle';
		if (index(MODES, mode) < 0) mode = 'toggle';
		let dark = (c.get(CFG, 'settings', 'dark') ?? '1') != '0';
		let locked = (c.get(CFG, 'settings', 'locked') ?? '1') != '0';
		let vibrate = int(c.get(CFG, 'settings', 'vibrate') ?? '100');
		if (vibrate != 0 && (vibrate < 20 || vibrate > 1000)) vibrate = 100;
		let hold = int(c.get(CFG, 'settings', 'hold') ?? '800');
		if (hold < 300 || hold > 5000) hold = 800;
		return { mode, toggle: mode == 'toggle', hold, dark, locked, vibrate };
	}

	// a file without our block
	function strip(f, src) {
		let b = index(src, f.begin), e = index(src, f.end);
		if (b < 0 || e < b) return null;
		return substr(src, 0, b) + substr(src, e + length(f.end));
	}

	function restart_screen() {
		// (detached: this request runs in the screen's own API server)
		ctx.run("setsid sh -c 'sleep 2; /etc/init.d/e5-infoscreen restart' >/dev/null 2>&1 &");
	}

	function write(path, src) {
		let tmp = path + '.sidekey-new';
		if (writefile(tmp, src) == null || !rename(tmp, path)) {
			ctx.run(`rm -f '${tmp}'`);
			return false;
		}
		return true;
	}

	// one file: {patched, current}, {patched: false, error}, or {absent} (an
	// optional file without its anchor: nothing to patch); with fix, the file
	// patched with this version's block first ({changed} when it was written)
	function file_state(f, fix) {
		let src = readfile(f.file), want = readfile(`${DIR}/${f.block}`);
		if (src == null || want == null) return { patched: false, error: `missing ${f.file} or ${f.block}` };
		if (index(src, want) >= 0) return { patched: true, current: true };
		let old = index(src, f.begin) >= 0;
		if (!fix && old) return { patched: true, current: false };
		if (fix && old) {
			src = strip(f, src);            // an older block: out first
			if (src == null) return { patched: false, error: `${f.file}: cannot remove the older patch` };
		}
		if (count(src, f.anchor) != 1)
			return f.need ? { patched: false, error: `${f.file}: no single place for the patch` } : { absent: true };
		if (!fix) return { patched: false };
		let parts = split(src, f.anchor);
		if (!write(f.file, parts[0] + want + f.anchor + parts[1]))
			return { patched: false, error: `cannot write ${f.file}` };
		return { patched: true, current: true, changed: true };
	}

	// all files, as one state for the page
	function patch(fix) {
		let all = { patched: true, current: true }, changed = false;
		for (let f in FILES) {
			let s = file_state(f, fix);
			if (s.absent) continue;
			if (s.changed) changed = true;
			if (s.error) all = { patched: false, error: s.error };
			else if (!s.patched) { if (!all.error) all.patched = false; }
			else if (!s.current) all.current = false;
		}
		if (changed) {
			ctx.log('app.js / index.html patched (side key), the screen restarts');
			restart_screen();
			all.restarting = true;
		}
		return all;
	}

	function status() {
		return { ...settings(), patch: patch(false) };
	}

	return {
		'GET /mode': function(req) {
			return settings();
		},
		'GET /status': function(req) {
			return { ...settings(), patch: patch(true) };
		},
		'POST /mode': function(req) {
			let mode = req.body?.mode;
			if (index(MODES, mode) < 0)
				return { status: 400, type: 'application/json', body: '{"error":"mode: toggle or page"}' };
			if (!stat(`/etc/config/${CFG}`))
				writefile(`/etc/config/${CFG}`, '');
			let c = ctx.uci();
			if (c.get(CFG, 'settings') == null)
				c.set(CFG, 'settings', 'settings');
			c.set(CFG, 'settings', 'mode', mode);
			c.commit(CFG);
			return status();
		},
		'POST /unpatch': function(req) {
			let changed = false;
			for (let f in FILES) {
				let src = readfile(f.file);
				if (src == null || index(src, f.begin) < 0) continue;
				src = strip(f, src);
				if (src == null || !write(f.file, src))
					return { status: 500, type: 'application/json', body: `{"error":"cannot restore ${f.file}"}` };
				changed = true;
			}
			if (!changed) return status();
			ctx.log('app.js / index.html restored (side key), the screen restarts');
			restart_screen();
			return { ...status(), restarting: true };
		},
		'GET /notifications': function(req) {
			if (!ctx.state_get('checked', 60)) {
				ctx.state_put('checked', { at: time() });
				patch(true);
			}
			return { notifications: [] };
		}
	};
};
