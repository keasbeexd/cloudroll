// Injected into the Memories shell page (127.0.0.1 only). Reports console errors and
// warnings, uncaught errors and failed requests to native diagnostics, which the user
// can share from the tab bar (long press). Query strings are dropped from URLs.
(() => {
  if (location.hostname !== '127.0.0.1') return;

  const send = (level, message) => {
    window.webkit?.messageHandlers?.cloudroll?.postMessage({ method: 'log', args: [level, String(message).slice(0, 500)] });
  };
  const describe = (value) => {
    if (value instanceof Error) return `${value.name}: ${value.message}`;
    if (typeof value === 'object') {
      try { return JSON.stringify(value); } catch { return String(value); }
    }
    return String(value);
  };
  const pathOf = (url) => {
    try { return new URL(url, location.href).pathname; } catch { return String(url); }
  };

  for (const level of ['error', 'warn']) {
    const original = console[level];
    console[level] = function (...args) {
      send(level, args.map(describe).join(' '));
      return original.apply(this, args);
    };
  }
  addEventListener('error', (e) => send('error', `${e.message} (${pathOf(e.filename)}:${e.lineno})`));
  addEventListener('unhandledrejection', (e) => send('error', `Unhandled rejection: ${describe(e.reason)}`));

  const originalFetch = window.fetch;
  window.fetch = async function (input, init) {
    const method = (init?.method || input?.method || 'GET').toUpperCase();
    const path = pathOf(input?.url ?? input);
    try {
      const response = await originalFetch.call(this, input, init);
      if (!response.ok) send('request', `${method} ${path} -> ${response.status}`);
      return response;
    } catch (error) {
      send('request', `${method} ${path} -> ${describe(error)}`);
      throw error;
    }
  };

  const open = XMLHttpRequest.prototype.open;
  const sendXHR = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__cloudroll = `${String(method).toUpperCase()} ${pathOf(url)}`;
    return open.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function (...args) {
    this.addEventListener('loadend', () => {
      if (this.status === 0) send('request', `${this.__cloudroll} -> network error`);
      else if (this.status >= 400) send('request', `${this.__cloudroll} -> ${this.status}`);
    });
    return sendXHR.apply(this, args);
  };
})();
