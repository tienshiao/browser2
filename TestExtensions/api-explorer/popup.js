// API Explorer — Popup Script
// Tests both direct API calls and message-passing through the background.

function showResult(id, data, isError) {
  const el = document.getElementById(id);
  el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  el.classList.add('visible');
  el.classList.toggle('error', !!isError);
}

function sendBg(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response);
      }
    });
  });
}

function formatTabs(tabs) {
  return tabs.map(t =>
    `[${t.id}] ${t.active ? '●' : '○'} ${t.title || '(no title)'}\n    ${t.url || ''}`
  ).join('\n');
}

// Query All Tabs
document.getElementById('btn-query-all').addEventListener('click', async () => {
  try {
    const { tabs } = await sendBg({ type: 'queryTabs', queryInfo: {} });
    showResult('res-query-all', formatTabs(tabs));
  } catch (e) {
    showResult('res-query-all', e.message, true);
  }
});

// Active Tab
document.getElementById('btn-active-tab').addEventListener('click', async () => {
  try {
    const { tabs } = await sendBg({ type: 'queryTabs', queryInfo: { active: true, currentWindow: true } });
    showResult('res-active-tab', formatTabs(tabs));
  } catch (e) {
    showResult('res-active-tab', e.message, true);
  }
});

// Create Tab
document.getElementById('btn-create-tab').addEventListener('click', async () => {
  try {
    const url = document.getElementById('input-create-url').value || 'https://example.com';
    const { tab } = await sendBg({ type: 'createTab', url });
    showResult('res-create-tab', `Created tab ${tab.id}: ${tab.url || url}`);
  } catch (e) {
    showResult('res-create-tab', e.message, true);
  }
});

// Close Tab
document.getElementById('btn-close-tab').addEventListener('click', async () => {
  try {
    const tabId = parseInt(document.getElementById('input-close-id').value, 10);
    if (isNaN(tabId)) throw new Error('Enter a valid tab ID');
    await sendBg({ type: 'closeTab', tabId });
    showResult('res-close-tab', `Closed tab ${tabId}`);
  } catch (e) {
    showResult('res-close-tab', e.message, true);
  }
});

// Execute Script
document.getElementById('btn-exec-script').addEventListener('click', async () => {
  try {
    const tabId = parseInt(document.getElementById('input-exec-id').value, 10);
    if (isNaN(tabId)) throw new Error('Enter a valid tab ID');
    const { results } = await sendBg({ type: 'executeScript', tabId });
    showResult('res-exec-script', results);
  } catch (e) {
    showResult('res-exec-script', e.message, true);
  }
});

// Insert CSS
document.getElementById('btn-insert-css').addEventListener('click', async () => {
  try {
    const tabId = parseInt(document.getElementById('input-css-id').value, 10);
    if (isNaN(tabId)) throw new Error('Enter a valid tab ID');
    await sendBg({ type: 'insertCSS', tabId });
    showResult('res-insert-css', `Inserted inject.css into tab ${tabId}`);
  } catch (e) {
    showResult('res-insert-css', e.message, true);
  }
});

// Send to Tab
document.getElementById('btn-send-tab').addEventListener('click', async () => {
  try {
    const tabId = parseInt(document.getElementById('input-send-id').value, 10);
    if (isNaN(tabId)) throw new Error('Enter a valid tab ID');
    const { response } = await sendBg({ type: 'sendToTab', tabId, message: { type: 'highlight' } });
    showResult('res-send-tab', response);
  } catch (e) {
    showResult('res-send-tab', e.message, true);
  }
});

// Event Log — reads storage directly (no message-passing needed)
document.getElementById('btn-refresh-log').addEventListener('click', async () => {
  try {
    const { eventLog } = await chrome.storage.local.get('eventLog');
    if (!eventLog || eventLog.length === 0) {
      showResult('res-event-log', '(no events yet)');
      return;
    }
    const lines = eventLog.slice(-20).reverse().map(entry => {
      const time = new Date(entry.timestamp).toLocaleTimeString();
      const details = entry.url ? ` ${entry.url}` : '';
      return `${time}  ${entry.event}  tab:${entry.tabId}${details}`;
    });
    showResult('res-event-log', lines.join('\n'));
  } catch (e) {
    showResult('res-event-log', e.message, true);
  }
});

// Auto-load the event log on popup open
document.getElementById('btn-refresh-log').click();
