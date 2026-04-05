#!/usr/bin/env node

const port = process.env.CDP_PORT || '9222';
const targetId = process.env.CDP_TARGET_ID || '';
const urlIncludes = process.env.CDP_TARGET_URL_INCLUDES || '';
const navigationURL = process.env.CDP_NAV_URL || '';
const timeoutMs = Number(process.env.CDP_NAV_TIMEOUT_MS || '20000');

if (!navigationURL) {
  console.error('Set CDP_NAV_URL before running chrome_cdp_navigate.mjs');
  process.exit(64);
}

const base = `http://127.0.0.1:${port}`;

const versionResp = await fetch(`${base}/json/version`);
if (!versionResp.ok) {
  throw new Error(`Failed to fetch ${base}/json/version: ${versionResp.status}`);
}
const version = await versionResp.json();

const targetsResp = await fetch(`${base}/json/list`);
if (!targetsResp.ok) {
  throw new Error(`Failed to fetch ${base}/json/list: ${targetsResp.status}`);
}
const targets = await targetsResp.json();

const pages = targets.filter((target) => target.type === 'page');
let target = null;

if (targetId) {
  target = pages.find((page) => page.id === targetId) || null;
}

if (!target && urlIncludes) {
  target = [...pages].reverse().find((page) => (page.url || '').includes(urlIncludes)) || null;
}

if (!target) {
  target = pages.at(-1) || null;
}

if (!target) {
  throw new Error('No page target found for CDP navigation');
}

class CDPClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Set();
  }

  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((resolve, reject) => {
      this.ws.onopen = () => resolve();
      this.ws.onerror = (error) => reject(error);
    });

    this.ws.onmessage = (event) => {
      const payload = JSON.parse(event.data);
      if (payload.id && this.pending.has(payload.id)) {
        const { resolve, reject } = this.pending.get(payload.id);
        this.pending.delete(payload.id);
        if (payload.error) {
          reject(new Error(payload.error.message || JSON.stringify(payload.error)));
        } else {
          resolve(payload.result);
        }
        return;
      }

      for (const listener of this.listeners) {
        listener(payload);
      }
    };
  }

  send(method, params = {}, sessionId = null) {
    const id = this.nextId++;
    const message = { id, method, params };
    if (sessionId) {
      message.sessionId = sessionId;
    }
    this.ws.send(JSON.stringify(message));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  onEvent(listener) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  waitForEvent(predicate, timeout, description) {
    return new Promise((resolve, reject) => {
      const deadline = setTimeout(() => {
        unsubscribe();
        reject(new Error(`Timed out waiting for ${description}`));
      }, timeout);

      const unsubscribe = this.onEvent((payload) => {
        if (!predicate(payload)) {
          return;
        }
        clearTimeout(deadline);
        unsubscribe();
        resolve(payload);
      });
    });
  }

  close() {
    this.ws?.close();
  }
}

const client = new CDPClient(version.webSocketDebuggerUrl);
await client.connect();

try {
  const { sessionId } = await client.send('Target.attachToTarget', {
    targetId: target.id,
    flatten: true,
  });

  await client.send('Page.enable', {}, sessionId);
  await client.send('Network.enable', {}, sessionId);

  const frameTree = await client.send('Page.getFrameTree', {}, sessionId);
  const rootFrameId = frameTree?.frameTree?.frame?.id;
  if (!rootFrameId) {
    throw new Error('Failed to resolve root frame for CDP navigation');
  }

  const firstDocumentRequestPromise = client.waitForEvent((payload) => {
    if (payload.sessionId !== sessionId || payload.method !== 'Network.requestWillBeSent') {
      return false;
    }

    const params = payload.params || {};
    return params.type === 'Document' && params.frameId === rootFrameId;
  }, timeoutMs, 'the first main-frame document request');

  const loadEventPromise = client
    .waitForEvent(
      (payload) => payload.sessionId === sessionId && payload.method === 'Page.loadEventFired',
      timeoutMs,
      'a page load event'
    )
    .catch(() => null);

  const navigationResult = await client.send('Page.navigate', { url: navigationURL }, sessionId);
  if (navigationResult?.errorText) {
    throw new Error(`Chrome rejected Page.navigate: ${navigationResult.errorText}`);
  }

  const firstDocumentRequest = await firstDocumentRequestPromise;
  const requestedURL = firstDocumentRequest?.params?.request?.url || '';
  if (requestedURL !== navigationURL) {
    throw new Error(`Chrome requested ${requestedURL || '<empty>'} instead of the exact OAuth URL`);
  }

  await loadEventPromise;

  console.log(JSON.stringify({
    targetId: target.id,
    requestedURL,
    matchedExact: requestedURL === navigationURL,
  }, null, 2));
} finally {
  client.close();
}
