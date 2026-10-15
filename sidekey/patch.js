/* BEGIN e5-sidekey (the sidekey app, /etc/e5-infoscreen/plugins/sidekey) */
// The side key (F1), as the sidekey app's GET /mode says ({toggle, hold,
// dark, vibrate}): a tap opens the hotspot page as before; held for `hold` ms
// the motor pulses once and the hotspot turns on or off (the release then does
// nothing more).  With "page", the key lock on, or the app removed (no /mode)
// the key is the screen's own again.  Like the power menu (power-menu.js):
// capturing keydown/keyup listeners on the window -- index.html's, added
// before mobile.js's lock screen ones -- and on each plugin frame's window
// (T551MPower.attach).
let sidekeyMode = null, sidekeyAt = -Infinity, sidekeyHeld = null, sidekeyPass = false;
function sidekeyFetch() {
	sidekeyAt = performance.now();
	fetch('/api/plugins/sidekey/mode', { cache: 'no-store' })
		.then((r) => r.ok ? r.json() : null)
		.then((m) => { sidekeyMode = m; }, () => { sidekeyMode = null; });
}
sidekeyFetch();
function sidekeyCancel() { if (sidekeyHeld) clearTimeout(sidekeyHeld.timer); sidekeyHeld = null; }
// held long enough: the hotspot on or off
function sidekeyToggle(m) {
	if (blank && !m.dark) {                       // only wakes the screen
		setBlank(false);
		return;
	}
	if (!last || !last.wifi) return;              // no status yet
	const on = !(wifiPending ?? last.wifi.enabled);
	wifiPending = on;
	if (m.vibrate > 0) post('vibrate', { ms: m.vibrate });
	if (!blank) {
		resetIdle();
		toast(on ? t('turning_on') : t('turning_off'));
	}
	renderHotspot(last);
	post('wifi', { on }).then((r) => {
		if (!r?.ok) {
			wifiPending = null;
			toast(`${t('failed')}${r?.error ? ': ' + errorText(r.error, lang) : ''}`);
		}
		setTimeout(poll, 1500);
	});
}
// a tap: what the key did before -- the screen's own keydown listener, given
// the key again; from a plugin frame (where it did nothing but wake the
// screen) the app is closed for the hotspot page
function sidekeyTap(fromFrame) {
	if (!fromFrame) {
		sidekeyPass = true;
		try { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'F1', code: 'F1', bubbles: true, cancelable: true })); }
		finally { sidekeyPass = false; }
		return;
	}
	if (blank) {
		setBlank(false);
		toApp({ e5: 'blank', on: false });
		toIme({ e5: 'blank', on: false });
		return;
	}
	resetIdle();
	if (imeOpen) return;                          // typing: left alone
	if (appOpen) closeApp();
	showPage(P.hotspot);
}
function sidekeyKey(e, fromFrame) {
	if (sidekeyPass || !(e.key == 'F1' || e.keyCode == 112)) return;
	if (e.type == 'keydown') {
		if (sidekeyHeld) {
			if (e.repeat) {                       // held down: its repeats
				e.preventDefault();
				e.stopImmediatePropagation();
				return;
			}
			sidekeyCancel();                      // a new press: the last keyup was lost
		}
		if (performance.now() - sidekeyAt > 5000) sidekeyFetch();   // (this press uses the last answer)
		const m = sidekeyMode;
		if (!m || !m.toggle || locked || e.repeat) return;   // the screen's own handling
		e.preventDefault();
		e.stopImmediatePropagation();
		const press = sidekeyHeld = { fired: false, timer: null };
		press.timer = setTimeout(() => {
			if (sidekeyHeld !== press) return;
			press.fired = true;
			sidekeyToggle(m);
		}, m.hold || 800);
		return;
	}
	if (!sidekeyHeld) return;                     // keyup of a key we did not take
	e.preventDefault();
	e.stopImmediatePropagation();
	const fired = sidekeyHeld.fired;
	sidekeyCancel();
	if (!fired) sidekeyTap(fromFrame);
}
function sidekeyAttach(win, fromFrame) {
	const doc = win?.document;
	if (!doc || doc.__e5Sidekey) return;
	doc.__e5Sidekey = true;
	win.addEventListener('keydown', (e) => sidekeyKey(e, fromFrame), true);
	win.addEventListener('keyup', (e) => sidekeyKey(e, fromFrame), true);
}
// the main window: through index.html's early listener (before mobile.js's
// lock screen) when it is there, else listeners of our own
window.e5Sidekey = (e) => sidekeyKey(e, false);
if (!window.e5SidekeyEarly) sidekeyAttach(window, false);
{
	const attach = T551MPower.attach;
	T551MPower.attach = (win) => { attach(win); sidekeyAttach(win, true); };
}
window.addEventListener('blur', () => { if (sidekeyHeld && !sidekeyHeld.fired) sidekeyCancel(); });
document.addEventListener('visibilitychange', () => { if (document.hidden) sidekeyCancel(); });
/* END e5-sidekey */
