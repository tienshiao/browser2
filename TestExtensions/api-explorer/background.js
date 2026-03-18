// API Explorer — Background Service Worker
// Exercises: chrome.tabs, chrome.webNavigation, chrome.webRequest, chrome.storage, chrome.scripting

const MAX_LOG_ENTRIES = 50;

async function appendLog(entry) {
  const { eventLog = [] } = await chrome.storage.local.get('eventLog');
  eventLog.push({ ...entry, timestamp: Date.now() });
  if (eventLog.length > MAX_LOG_ENTRIES) {
    eventLog.splice(0, eventLog.length - MAX_LOG_ENTRIES);
  }
  await chrome.storage.local.set({ eventLog });
}

// --- Tab events ---

chrome.tabs.onCreated.addListener((tab) => {
  console.log('[API Explorer] tabs.onCreated', tab.id, tab.url);
  appendLog({ event: 'tabs.onCreated', tabId: tab.id, url: tab.url });
});

chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  console.log('[API Explorer] tabs.onRemoved', tabId);
  appendLog({ event: 'tabs.onRemoved', tabId });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  console.log('[API Explorer] tabs.onUpdated', tabId, changeInfo);
  appendLog({ event: 'tabs.onUpdated', tabId, changeInfo });
});

chrome.tabs.onActivated.addListener((activeInfo) => {
  console.log('[API Explorer] tabs.onActivated', activeInfo.tabId);
  appendLog({ event: 'tabs.onActivated', tabId: activeInfo.tabId });
});

// --- WebNavigation events ---

chrome.webNavigation.onCommitted.addListener((details) => {
  console.log('[API Explorer] webNavigation.onCommitted', details.tabId, details.url);
  appendLog({ event: 'webNavigation.onCommitted', tabId: details.tabId, url: details.url });
});

chrome.webNavigation.onCompleted.addListener((details) => {
  console.log('[API Explorer] webNavigation.onCompleted', details.tabId, details.url);
  appendLog({ event: 'webNavigation.onCompleted', tabId: details.tabId, url: details.url });
});

// --- WebRequest (stub verification — should log a warning but not crash) ---

try {
  chrome.webRequest.onBeforeRequest.addListener(
    (details) => {
      // Intentionally empty — just verifying the stub doesn't throw
    },
    { urls: ['<all_urls>'] }
  );
  console.log('[API Explorer] webRequest.onBeforeRequest listener registered (stub)');
} catch (e) {
  console.warn('[API Explorer] webRequest.onBeforeRequest registration failed:', e);
}

// --- Message handling from popup ---

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message).then(sendResponse);
  return true; // keep channel open for async response
});

async function handleMessage(message) {
  switch (message.type) {
    case 'getLog': {
      const { eventLog = [] } = await chrome.storage.local.get('eventLog');
      return { log: eventLog };
    }

    case 'queryTabs': {
      const tabs = await chrome.tabs.query(message.queryInfo || {});
      return { tabs };
    }

    case 'createTab': {
      const tab = await chrome.tabs.create({ url: message.url || 'about:blank' });
      return { tab };
    }

    case 'closeTab': {
      await chrome.tabs.remove(message.tabId);
      return { success: true };
    }

    case 'executeScript': {
      if (message.code) {
        const results = await chrome.scripting.executeScript({
          target: { tabId: message.tabId },
          func: new Function(message.code),
        });
        return { results };
      } else {
        const results = await chrome.scripting.executeScript({
          target: { tabId: message.tabId },
          files: ['inject.js'],
        });
        return { results };
      }
    }

    case 'insertCSS': {
      await chrome.scripting.insertCSS({
        target: { tabId: message.tabId },
        files: ['inject.css'],
      });
      return { success: true };
    }

    case 'sendToTab': {
      const response = await chrome.tabs.sendMessage(message.tabId, message.message || { type: 'highlight' });
      return { response };
    }

    default:
      return { error: 'Unknown message type: ' + message.type };
  }
}
