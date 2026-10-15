// 侧键开关热点 (Side Key Hotspot, id sidekey): the side key (F1) turns the
// hotspot on or off and the motor pulses once, instead of opening the hotspot
// page.  The key is the screen's own (app.js, its keydown listener), so this
// patches app.js with patch.js, put in before the key lock: its listeners come
// before the screen's, ask GET /mode, and take the key when it is ours.  An
// image update brings an unpatched app.js: the notification poll (manifest
// "notifications") patches it again; the screen restarts once after each
// patch, to load it.  With the app removed there is no /mode and the key
// opens the hotspot page again; POST /unpatch takes the block out.
//
//   GET  /mode            {toggle, dark, vibrate}, for the patched app.js
//   GET  /status          the settings and the patch
//   POST /mode            {"mode": "toggle"|"page"}
//   POST /unpatch         app.js as it came, the screen restarted
//   GET  /notifications   (none: only the patch check, once a minute)

'use strict';

import { readfile, writefile, rename, stat } from 'fs';

const DIR = '/etc/e5-infoscreen/plugins/sidekey';
const APP = '/usr/share/e5-infoscreen/www/app.js';
const CFG = 'e5-plugin-sidekey';
const ANCHOR = '/* ---------- key lock ---------- */';
const BEGIN = '/* BEGIN e5-sidekey';
const END = '/* END e5-sidekey */\n';
const MODES = [ 'toggle', 'page' ];

return function(ctx) {
	function count(s, part) { return length(split(s, part)) - 1; }

	function settings() {
		let c = ctx.uci();
		let mode = c.get(CFG, 'settings', 'mode') ?? 'toggle';
		if (index(MODES, mode) < 0) mode = 'toggle';
		let dark = (c.get(CFG, 'settings', 'dark') ?? '1') != '0';
		let vibrate = int(c.get(CFG, 'settings', 'vibrate') ?? '100');
		if (vibrate != 0 && (vibrate < 20 || vibrate > 1000)) vibrate = 100;
		return { mode, toggle: mode == 'toggle', dark, vibrate };
	}

	// app.js without our block
	function strip(src) {
		let b = index(src, BEGIN), e = index(src, END);
		if (b < 0 || e < b) return null;
		return substr(src, 0, b) + substr(src, e + length(END));
	}

	function restart_screen() {
		// (detached: this request runs in the screen's own API server)
		ctx.run("setsid sh -c 'sleep 2; /etc/init.d/e5-infoscreen restart' >/dev/null 2>&1 &");
	}

	function write_app(src) {
		let tmp = APP + '.sidekey-new';
		if (writefile(tmp, src) == null || !rename(tmp, APP)) {
			ctx.run(`rm -f '${tmp}'`);
			return false;
		}
		return true;
	}

	function patch_state() {
		let src = readfile(APP), want = readfile(`${DIR}/patch.js`);
		if (src == null || want == null) return { patched: false, error: 'missing app.js or patch.js' };
		if (index(src, want) >= 0) return { patched: true, current: true };
		if (index(src, BEGIN) >= 0) return { patched: true, current: false };
		let ok = count(src, ANCHOR) == 1;
		return { patched: false, patchable: ok, error: ok ? null : 'this screen version has no single key lock section' };
	}

	// app.js with this version of patch.js; the screen restarted when it changed
	function ensure_patch() {
		let src = readfile(APP), want = readfile(`${DIR}/patch.js`);
		if (src == null || want == null) return patch_state();
		if (index(src, want) >= 0) return { patched: true, current: true };
		if (index(src, BEGIN) >= 0) {
			src = strip(src);               // an older patch.js: out first
			if (src == null) return { patched: false, error: 'cannot remove the older patch' };
		}
		if (count(src, ANCHOR) != 1)
			return { patched: false, error: 'this screen version has no single key lock section: not patched' };
		let parts = split(src, ANCHOR);
		if (!write_app(parts[0] + want + ANCHOR + parts[1]))
			return { patched: false, error: 'cannot write app.js' };
		ctx.log('app.js patched (side key), the screen restarts');
		restart_screen();
		return { patched: true, current: true, restarting: true };
	}

	function status() {
		return { ...settings(), patch: patch_state() };
	}

	return {
		'GET /mode': function(req) {
			return settings();
		},
		'GET /status': function(req) {
			let p = ensure_patch();
			return { ...settings(), patch: p };
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
			let src = readfile(APP);
			if (src == null || index(src, BEGIN) < 0)
				return status();
			src = strip(src);
			if (src == null || !write_app(src))
				return { status: 500, type: 'application/json', body: '{"error":"cannot restore app.js"}' };
			ctx.log('app.js restored (side key), the screen restarts');
			restart_screen();
			return { ...status(), restarting: true };
		},
		'GET /notifications': function(req) {
			if (!ctx.state_get('checked', 60)) {
				ctx.state_put('checked', { at: time() });
				ensure_patch();
			}
			return { notifications: [] };
		}
	};
};
