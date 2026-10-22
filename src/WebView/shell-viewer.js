// Injected into the Memories shell page (127.0.0.1 only). Cloudroll shows photos in a
// native viewer while Memories' own viewer keeps deciding which photo is current (so
// ordering, lazily loaded days and per-view lists stay right). This script reports the
// current photo, hides Memories' viewer (its dialogs stay visible), keeps its videos
// paused, and drives it: next/previous via the arrow keys PhotoSwipe listens to, and
// actions via their icon classes.
(() => {
  if (location.hostname !== '127.0.0.1') return;

  const root = document.documentElement;
  const NATIVE = 'cloudroll-native-viewer';
  const QUIET = 'cloudroll-quiet';
  const FLAG_VIDEO = 1 << 2;
  const FLAG_FAVORITE = 1 << 3;
  const FLAG_LOCAL = 1 << 6;

  const style = document.createElement('style');
  style.textContent = `
    html.${NATIVE} .memories-viewer { visibility: hidden !important; }
    html.${QUIET} .v-popper__popper, html.${QUIET} [role="menu"], html.${QUIET} .modal-mask { visibility: hidden !important; }
  `;

  const post = (state) => {
    window.webkit?.messageHandlers?.cloudroll?.postMessage({ method: 'viewer', args: [JSON.stringify(state)] });
  };

  const snapshot = () => {
    const viewer = window._m?.viewer;
    const photo = viewer?.isOpen ? viewer.currentPhoto : null;
    if (!photo) return { open: false };
    const flag = photo.flag ?? 0;
    return {
      open: true,
      photo: {
        fileid: photo.fileid,
        auid: photo.auid ?? '',
        etag: photo.etag ?? '',
        basename: photo.basename ?? '',
        dayid: photo.dayid ?? 0,
        w: photo.w ?? 0,
        h: photo.h ?? 0,
        video: !!(flag & FLAG_VIDEO) || !!photo.isvideo,
        favorite: !!(flag & FLAG_FAVORITE),
        local: !!(flag & FLAG_LOCAL) || !!photo.islocal,
      },
    };
  };

  let lastReport = '';
  let scheduled = false;
  const report = () => {
    scheduled = false;
    const state = snapshot();
    if (state.open && !style.isConnected) document.head.appendChild(style);
    root.classList.toggle(NATIVE, state.open);
    if (state.open) pauseHiddenVideos();
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

  /** The native viewer plays videos itself; Memories' hidden player must stay silent. */
  const pauseHiddenVideos = () => {
    for (const video of document.querySelectorAll('.memories-viewer video')) {
      if (!video.paused) video.pause();
    }
  };
  document.addEventListener('play', (e) => {
    if (root.classList.contains(NATIVE) && e.target instanceof HTMLVideoElement && e.target.closest('.memories-viewer')) {
      e.target.pause();
    }
  }, true);

  const nextFrame = () => new Promise((resolve) => requestAnimationFrame(resolve));
  const waitFor = async (find, ms) => {
    const end = performance.now() + ms;
    while (performance.now() < end) {
      const found = find();
      if (found) return found;
      await nextFrame();
    }
    return null;
  };
  const viewer = () => document.querySelector('.memories-viewer');
  const withIcon = (scope, icons) => {
    for (const icon of icons) {
      const found = scope?.querySelector(`button:has(.${icon}), [role="menuitem"]:has(.${icon})`);
      if (found) return found;
    }
    return null;
  };

  /** Clicks a viewer action; actions not in the bottom bar live in the top overflow menu. */
  const run = async (icons, { keepQuiet = false } = {}) => {
    const scope = viewer();
    if (!scope) return false;
    root.classList.add(QUIET);
    try {
      let target = withIcon(scope, icons);
      if (!target) {
        const toggles = scope.querySelectorAll('button[aria-haspopup], .action-item__menutoggle');
        const toggle = toggles[toggles.length - 1];
        if (!toggle) return false;
        toggle.click();
        target = await waitFor(() => withIcon(document.querySelector('[role="menu"]'), icons), 1000);
        if (!target) {
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
          return false;
        }
      }
      target.click();
      return true;
    } finally {
      if (!keepQuiet) {
        await nextFrame();
        root.classList.remove(QUIET);
      }
    }
  };

  /** Same as the selection toolbar: straight to the share sheet with the original. */
  const shareOriginal = async () => {
    try {
      if (!(await run(['share-variant-icon'], { keepQuiet: true }))) return false;
      const original = await waitFor(() => document.querySelector('.modal-mask a:has(.file-icon)'), 5000);
      if (!original) return true;
      original.click();
      await waitFor(() => !document.querySelector('.modal-mask'), 120000);
      return true;
    } finally {
      await nextFrame();
      root.classList.remove(QUIET);
    }
  };

  const step = (key) => {
    document.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));
    return true;
  };

  window.__cloudrollViewer = {
    next: () => step('ArrowRight'),
    previous: () => step('ArrowLeft'),
    close: () => {
      window._m?.viewer?.close();
      return true;
    },
    run: (icons) => run(icons),
    shareOriginal,
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
})();
