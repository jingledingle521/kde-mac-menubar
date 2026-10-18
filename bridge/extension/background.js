// Mac Menu Bridge: carries out top-bar menu commands for the KDE "Browser
// Menus" widget. Connects to the local vivaldi-menu-bridge helper and answers
// queries (history, bookmarks, tabs) so menus can list real items.
importScripts("config.js");

const ZOOM_STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5];
let ws = null;

function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
        return;
    }
    try {
        ws = new WebSocket(`ws://127.0.0.1:${self.BRIDGE.port}`);
    } catch (e) {
        ws = null;
        return;
    }
    ws.onopen = () => ws.send(JSON.stringify({ type: "hello", token: self.BRIDGE.token }));
    ws.onmessage = event => handle(JSON.parse(event.data)).catch(() => {});
    ws.onclose = () => {
        ws = null;
        setTimeout(connect, 3000);
    };
    ws.onerror = () => {};
}

function reply(id, data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "result", id, data }));
    }
}

async function currentWindow() {
    return chrome.windows.getLastFocused({ windowTypes: ["normal"] });
}

async function activeTab() {
    const win = await currentWindow();
    const [tab] = await chrome.tabs.query({ active: true, windowId: win.id });
    return tab;
}

async function stepZoom(direction) {
    const tab = await activeTab();
    const zoom = await chrome.tabs.getZoom(tab.id);
    let next = 1;
    if (direction > 0) {
        next = ZOOM_STEPS.find(z => z > zoom + 0.001) ?? ZOOM_STEPS[ZOOM_STEPS.length - 1];
    } else if (direction < 0) {
        next = [...ZOOM_STEPS].reverse().find(z => z < zoom - 0.001) ?? ZOOM_STEPS[0];
    }
    await chrome.tabs.setZoom(tab.id, next);
}

async function cycleTab(offset) {
    const win = await currentWindow();
    const tabs = await chrome.tabs.query({ windowId: win.id });
    const i = tabs.findIndex(t => t.active);
    const next = tabs[(i + offset + tabs.length) % tabs.length];
    await chrome.tabs.update(next.id, { active: true });
}

const COMMANDS = {
    newTab: async () => chrome.tabs.create({ windowId: (await currentWindow()).id }),
    newWindow: () => chrome.windows.create({ focused: true }),
    newPrivateWindow: () => chrome.windows.create({ incognito: true, focused: true }),
    closeTab: async () => chrome.tabs.remove((await activeTab()).id),
    closeWindow: async () => chrome.windows.remove((await currentWindow()).id),
    reopenClosed: () => chrome.sessions.restore(),
    restoreSession: args => chrome.sessions.restore(args.sessionId),
    reload: async () => chrome.tabs.reload((await activeTab()).id),
    hardReload: async () => chrome.tabs.reload((await activeTab()).id, { bypassCache: true }),
    back: async () => chrome.tabs.goBack((await activeTab()).id),
    forward: async () => chrome.tabs.goForward((await activeTab()).id),
    zoomIn: () => stepZoom(1),
    zoomOut: () => stepZoom(-1),
    zoomReset: () => stepZoom(0),
    duplicateTab: async () => chrome.tabs.duplicate((await activeTab()).id),
    togglePin: async () => {
        const tab = await activeTab();
        return chrome.tabs.update(tab.id, { pinned: !tab.pinned });
    },
    toggleMute: async () => {
        const tab = await activeTab();
        return chrome.tabs.update(tab.id, { muted: !tab.mutedInfo.muted });
    },
    nextTab: () => cycleTab(1),
    previousTab: () => cycleTab(-1),
    activateTab: async args => {
        await chrome.tabs.update(args.tabId, { active: true });
        const tab = await chrome.tabs.get(args.tabId);
        await chrome.windows.update(tab.windowId, { focused: true });
    },
    openUrl: async args => chrome.tabs.create({ url: args.url, windowId: (await currentWindow()).id }),
};

function trimBookmarks(node, depth) {
    if (node.url) {
        return { title: node.title || node.url, url: node.url };
    }
    return {
        title: node.title,
        children: depth > 0 ? (node.children || []).slice(0, 80).map(child => trimBookmarks(child, depth - 1)) : [],
    };
}

const QUERIES = {
    history: async () => {
        const items = await chrome.history.search({ text: "", maxResults: 40, startTime: Date.now() - 14 * 864e5 });
        return items
            .filter(item => item.url && !item.url.startsWith("chrome") && !item.url.startsWith("vivaldi"))
            .slice(0, 15)
            .map(item => ({ title: item.title || item.url, url: item.url }));
    },
    recentlyClosed: async () => {
        const sessions = await chrome.sessions.getRecentlyClosed({ maxResults: 8 });
        return sessions.map(s => s.tab
            ? { sessionId: s.tab.sessionId, title: s.tab.title || s.tab.url }
            : { sessionId: s.window.sessionId, title: `Window (${s.window.tabs.length} tabs)` });
    },
    bookmarks: async () => {
        const [root] = await chrome.bookmarks.getTree();
        return (root.children || []).map(folder => trimBookmarks(folder, 5));
    },
    tabs: async () => {
        const win = await currentWindow();
        const tabs = await chrome.tabs.query({ windowId: win.id });
        return tabs.map(t => ({ id: t.id, title: t.title || t.url, active: t.active, pinned: t.pinned, audible: t.audible }));
    },
};

async function handle(msg) {
    if (msg.type === "ping") {
        ws.send(JSON.stringify({ type: "pong" }));
    } else if (msg.type === "cmd" && COMMANDS[msg.name]) {
        await COMMANDS[msg.name](msg.args || {});
    } else if (msg.type === "query") {
        let data = null;
        try {
            data = QUERIES[msg.what] ? await QUERIES[msg.what]() : null;
        } finally {
            reply(msg.id, data);
        }
    }
}

// The service worker can be suspended; the alarm wakes it to reconnect.
chrome.alarms.create("reconnect", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
