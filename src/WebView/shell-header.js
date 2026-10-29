// Injected into the Memories shell page (127.0.0.1 only). Replaces Memories' headers
// (the timeline's mobile header, every view's title row and Explore's title and search
// field) with Cloudroll's native glass header: hides them, describes them to native code
// (title, back button, actions by icon class), clicks their buttons, and opens searches.
(() => {
  if (location.hostname !== '127.0.0.1') return;

  const root = document.documentElement;
  const NATIVE = 'cloudroll-native-header';
  const style = document.createElement('style');
  style.textContent = `
    /* Hidden but kept in place: their buttons are still clicked, and their space stays. */
    html.${NATIVE} #mobile-header,
    html.${NATIVE} .top-matter-container .top-matter,
    html.${NATIVE} .top-matter-container .places-top-matter,
    html.${NATIVE} .top-matter-container .face-top-matter,
    /* Only Explore's own heading: cluster names and section titles are .title too. */
    html.${NATIVE} .explore-outer > div > .title { visibility: hidden !important; }
    /* Search moved to the native header; no blank gap where the field was. */
    html.${NATIVE} .explore-outer > div > .searchbar { display: none !important; }
  `;

  const post = (state) => {
    window.webkit?.messageHandlers?.cloudroll?.postMessage({ method: 'header', args: [JSON.stringify(state)] });
  };

  const iconOf = (el) => [...(el.querySelector('.material-design-icon')?.classList ?? [])].find((c) => c.endsWith('-icon') && c !== 'material-design-icon') ?? '';
  const matter = () => document.querySelector('.top-matter-container .top-matter, .top-matter-container .places-top-matter, .top-matter-container .face-top-matter');

  const describe = () => {
    if (document.getElementById('mobile-header')) {
      return { kind: 'timeline', title: '', back: false, actions: [], more: false };
    }
    const explore = document.querySelector('.explore-outer');
    if (explore) {
      return { kind: 'explore', title: explore.querySelector(':scope > div > .title')?.textContent?.trim() ?? '', back: false, actions: [], more: false };
    }
    const current = matter();
    if (!current) return { kind: 'none', title: '', back: false, actions: [], more: false };
    const crumbs = [...current.querySelectorAll('.breadcrumb li')];
    const title = current.querySelector('.name')?.textContent?.trim()
      || crumbs.at(-1)?.textContent?.trim()
      || document.querySelector('.top-matter-container h1, .top-matter-container .title')?.textContent?.trim()
      || '';
    const back = !!current.querySelector('button:has(.arrow-left-icon)');
    const actions = [...current.querySelectorAll('.right-actions button.action-item--single')]
      .map((b) => ({ icon: iconOf(b), label: b.getAttribute('aria-label') ?? '' }))
      .filter((a) => a.icon);
    const more = !!current.querySelector('.right-actions .action-item__menutoggle');
    return { kind: 'matter', title, back, actions, more };
  };

  let lastReport = '';
  let scheduled = false;
  const report = () => {
    scheduled = false;
    const state = describe();
    if (state.kind !== 'none' && !style.isConnected) document.head.appendChild(style);
    root.classList.toggle(NATIVE, state.kind !== 'none');
    const json = JSON.stringify(state);
    if (json === lastReport) return;
    lastReport = json;
    post(state);
  };
  const scheduleReport = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(report);
  };

  window.__cloudrollHeader = {
    /** A title-row action by icon class, the back button, or the overflow menu. */
    action: (icon) => {
      const current = matter();
      const target = current?.querySelector(`button:has(.${icon})`);
      target?.click();
      return !!target;
    },
    back: () => {
      const current = matter();
      const target = current?.querySelector('button:has(.arrow-left-icon)');
      if (target) {
        target.click();
        return true;
      }
      history.back();
      return true;
    },
    more: () => {
      const toggle = matter()?.querySelector('.right-actions .action-item__menutoggle');
      toggle?.click();
      return !!toggle;
    },
    /** Opens Memories' search results; vue-router follows a popstate without state. */
    search: (query) => {
      const base = location.pathname.replace(/\/apps\/memories\/.*$/, '/apps/memories');
      history.pushState(null, '', `${base}/search?q=${encodeURIComponent(query)}`);
      dispatchEvent(new PopStateEvent('popstate', { state: null }));
      return true;
    },
    /** Memories' own upload (kept for when native upload can't be used). */
  };

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function (...args) {
      const result = original.apply(this, args);
      scheduleReport();
      return result;
    };
  }
  addEventListener('popstate', scheduleReport);
  const start = () => {
    new MutationObserver(scheduleReport).observe(document.body, { childList: true, subtree: true, characterData: true });
    report();
  };
  if (document.readyState === 'loading') {
    addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
