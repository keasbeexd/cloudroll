// Injected into the Memories shell page (127.0.0.1 only). Replaces Memories' selection
// bar with Cloudroll's native toolbar: reports selection mode and Memories' own
// "N selected" label, and runs Memories' selection actions by their icon so its own
// logic (and selection) stays in charge. Icon classes come from vue-material-design-icons
// and don't depend on the language.
(() => {
  if (location.hostname !== '127.0.0.1') return;

  const root = document.documentElement;
  const NATIVE = 'cloudroll-native-selection';
  const QUIET = 'cloudroll-quiet';
  const style = document.createElement('style');
  style.textContent = `
    html.${NATIVE} .memories-top-bar { visibility: hidden !important; }
    /* Menus and dialogs opened on the user's behalf stay invisible. */
    html.${QUIET} .v-popper__popper, html.${QUIET} [role="menu"], html.${QUIET} .modal-mask { visibility: hidden !important; }
  `;

  const bar = () => document.querySelector('.memories-top-bar');
  const post = (state) => {
    window.webkit?.messageHandlers?.cloudroll?.postMessage({ method: 'selection', args: [JSON.stringify(state)] });
  };

  let lastReport = '';
  let scheduled = false;
  const report = () => {
    scheduled = false;
    const current = bar();
    if (current && !style.isConnected) document.head.appendChild(style);
    root.classList.toggle(NATIVE, !!current);
    // Only on-screen photos are in the page; that's enough to show the star's state.
    const selected = [...document.querySelectorAll('.p-outer.selected')];
    const allFavorite = selected.length > 0 && selected.every((p) => p.querySelector('.flag.bottom-right .star-icon'));
    const json = JSON.stringify({
      active: !!current,
      label: current?.querySelector('.text')?.textContent?.trim() ?? '',
      allFavorite,
    });
    if (json === lastReport) return;
    lastReport = json;
    post(JSON.parse(json));
  };
  const scheduleReport = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(report);
  };

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
  const withIcon = (scope, icon) => scope?.querySelector(`button:has(.${icon}), [role="menuitem"]:has(.${icon})`);
  const menuToggle = (current) => {
    const toggles = current.querySelectorAll('button[aria-haspopup], .action-item__menutoggle');
    return toggles[toggles.length - 1] ?? null;
  };

  /** Clicks a selection action, opening the overflow menu (invisibly) when needed. */
  const run = async (icon, { keepQuiet = false } = {}) => {
    const current = bar();
    if (!current) return false;
    let target = withIcon(current, icon);
    root.classList.add(QUIET);
    try {
      if (!target) {
        const toggle = menuToggle(current);
        if (!toggle) return false;
        toggle.click();
        target = await waitFor(() => withIcon(document.querySelector('[role="menu"]'), icon), 1000);
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

  /**
   * Share straight to the native share sheet with originals, skipping Memories' choice.
   * Memories' dialog stays hidden until it closes, so only the native "Preparing…" shows
   * while originals (e.g. phone videos) are exported.
   */
  const shareOriginal = async () => {
    try {
      if (!(await run('share-variant-icon', { keepQuiet: true }))) return false;
      // The dialog's list loads on demand, so the option can take a moment to appear.
      const original = await waitFor(
        () => document.querySelector('.modal-mask .list-item:has(.file-icon), .modal-mask a:has(.file-icon), .modal-mask [role="button"]:has(.file-icon)'),
        5000,
      );
      // If Memories' dialog changed, the user picks from it instead.
      if (!original) return true;
      original.click();
      await waitFor(() => !document.querySelector('.modal-mask'), 120000);
      return true;
    } finally {
      await nextFrame();
      root.classList.remove(QUIET);
    }
  };

  const more = () => {
    const toggle = bar() && menuToggle(bar());
    toggle?.click();
    return !!toggle;
  };

  const cancel = () => {
    const close = withIcon(bar(), 'close-icon');
    close?.click();
    return !!close;
  };

  window.__cloudrollSelection = { run, shareOriginal, more, cancel };

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
