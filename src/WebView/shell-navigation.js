// Injected into the Memories shell page (127.0.0.1 only). Hides Memories' own
// bottom bar in favour of Cloudroll's native one, reports navigation state to
// native code, and lets native tabs click Memories' hidden tab links so its
// own router logic runs unchanged. Nothing changes if Memories' bar isn't found.
(() => {
  if (location.hostname !== '127.0.0.1') return;

  const NATIVE_CLASS = 'cloudroll-native-nav';
  const style = document.createElement('style');
  style.textContent = `
    html.${NATIVE_CLASS} #mobile-nav { display: none !important; }
    /* Kept in the page (its buttons are clicked by the native top bar), just not shown. */
    html.${NATIVE_CLASS} #mobile-header { visibility: hidden !important; }
    /* Let content run under the glass bar... */
    html.${NATIVE_CLASS} #app-content-vue > .router-outlet.has-nav { height: 100% !important; }
    /* ...while scrollers keep their last row reachable above it. */
    html.${NATIVE_CLASS} .recycler,
    html.${NATIVE_CLASS} .grid-recycler {
      padding-bottom: calc(78px + env(safe-area-inset-bottom)) !important;
      box-sizing: border-box;
    }
  `;

  const tabLinks = () => [...document.querySelectorAll('#mobile-nav a.mobile-bottom-bar-item')];

  const post = (state) => {
    window.webkit?.messageHandlers?.cloudroll?.postMessage({ method: 'navState', args: [JSON.stringify(state)] });
  };

  let lastReport = '';
  let scheduled = false;
  // Scrolling down a list shrinks the native bar, like iOS tab bars.
  let collapsed = false;
  let lastPath = location.pathname;
  const report = () => {
    scheduled = false;
    const enabled = !!document.getElementById('mobile-nav');
    if (enabled && !style.isConnected) document.head.appendChild(style);
    document.documentElement.classList.toggle(NATIVE_CLASS, enabled);

    if (location.pathname !== lastPath) {
      lastPath = location.pathname;
      collapsed = false;
    }
    const tabs = enabled
      ? tabLinks().map((a) => ({ href: new URL(a.href).pathname, label: a.textContent.trim() }))
      : [];
    const header = enabled && !!document.getElementById('mobile-header');
    // Some Memories dialogs (e.g. search) don't add a URL fragment, so look for them too.
    const dialog = !!document.querySelector('.modal-mask, .memories-searchbar');
    const json = JSON.stringify({ enabled, tabs, path: location.pathname, hash: location.hash, collapsed, header, dialog });
    if (json === lastReport) return;
    lastReport = json;
    post(JSON.parse(json));
  };
  // DOM churn (e.g. the virtual scroller) is coalesced to one report per frame.
  const scheduleReport = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(report);
  };

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function (...args) {
      const result = original.apply(this, args);
      scheduleReport();
      return result;
    };
  }
  // Scroll events don't bubble, so listen in the capture phase for Memories' scrollers.
  const anchors = new WeakMap();
  document.addEventListener('scroll', (event) => {
    const scroller = event.target;
    if (!(scroller instanceof Element) || !scroller.matches('.recycler, .grid-recycler')) return;
    const y = scroller.scrollTop;
    if (!anchors.has(scroller)) {
      anchors.set(scroller, y);
      return;
    }
    const anchor = anchors.get(scroller);
    if (Math.abs(y - anchor) < 12) return;
    anchors.set(scroller, y);
    const next = y > anchor && y > 60;
    if (next === collapsed) return;
    collapsed = next;
    scheduleReport();
  }, { capture: true, passive: true });

  /** Runs a button of Memories' mobile header ('upload' or 'search'). */
  window.__cloudrollHeader = (action) => {
    const button = document.querySelector(`#mobile-header .${action}-menu`);
    button?.click();
    return !!button;
  };

  window.__cloudrollExpandBar = () => {
    collapsed = false;
    scheduleReport();
  };

  addEventListener('popstate', scheduleReport);
  addEventListener('hashchange', scheduleReport);

  const start = () => {
    new MutationObserver(scheduleReport).observe(document.body, { childList: true, subtree: true });
    report();
  };
  if (document.readyState === 'loading') {
    addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }

  window.__cloudrollSelectTab = (href) => {
    const link = tabLinks().find((a) => new URL(a.href).pathname === href);
    link?.click();
    return !!link;
  };
})();
