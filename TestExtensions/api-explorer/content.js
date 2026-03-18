// API Explorer — Content Script
// Exercises: chrome.runtime.onMessage

console.log('[API Explorer] Content script injected on', window.location.href);

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'highlight') {
    const body = document.body;
    if (body.style.outline === '4px solid blue') {
      body.style.outline = '';
      sendResponse({ highlighted: false });
    } else {
      body.style.outline = '4px solid blue';
      sendResponse({ highlighted: true });
    }
  }
});
