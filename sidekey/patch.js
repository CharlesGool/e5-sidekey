/* BEGIN e5-sidekey (the sidekey app, /etc/e5-infoscreen/plugins/sidekey) */
// The side key (F1) turns the hotspot on or off and the motor pulses once, as
// the sidekey app's GET /mode says ({toggle, dark, vibrate}); with "page", or
// with the app removed (no /mode), it opens the hotspot page as before.
// Capturing listeners added before the screen's own keydown and message
// listeners: they run first, and take the key from them when it is ours.
let sidekeyMode = null, sidekeyAt = -Infinity, sidekeyLast = -Infinity;
function sidekeyFetch() {
	sidekeyAt = performance.now();
	fetch('/api/plugins/sidekey/mode', { cache: 'no-store' })
		.then((r) => r.ok ? r.json() : null)
		.then((m) => { sidekeyMode = m; }, () => { sidekeyMode = null; });
}
sidekeyFetch();
function sidekeyIs(key, code) { return key == 'F1' || code == 112; }
// true: the key is ours, the caller drops it; false: the screen's own handling
function sidekeyPress(repeat) {
	const now = performance.now();
	if (now - sidekeyAt > 5000) sidekeyFetch();   // (this press uses the last answer)
	const m = sidekeyMode;
	if (!m || !m.toggle) return false;            // the hotspot page, as before
	if (locked) return false;                     // the key lock: no key does anything
	if (blank && !m.dark) return false;           // only wakes the screen
	if (repeat) return true;                      // held down: one press
	if (now - sidekeyLast < 1500) return true;    // a second press too soon: dropped
	if (!last || !last.wifi) return false;        // no status yet: the hotspot page
	sidekeyLast = now;
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
	return true;
}
document.addEventListener('keydown', (e) => {
	if (!sidekeyIs(e.key, e.keyCode)) return;
	if (sidekeyPress(!!e.repeat)) {
		e.preventDefault();
		e.stopImmediatePropagation();
	}
}, true);
// the same key, passed on by an open plugin frame (sdk/e5.js)
window.addEventListener('message', (e) => {
	const m = e.data;
	if (!m || typeof m != 'object' || m.e5 !== 'key' || !sidekeyIs(m.key, m.keyCode)) return;
	const fromIme = imeOpen && e.source === $('ime-frame').contentWindow;
	const fromApp = appOpen && e.source === $('app-frame').contentWindow;
	if (!fromIme && !fromApp) return;
	if (sidekeyPress(!!m.repeat)) e.stopImmediatePropagation();
}, true);
/* END e5-sidekey */
