// API Explorer — Content Script
// Exercises: chrome.runtime.onMessage, documentId

console.log('[API Explorer] Content script injected on', window.location.href);
console.log('[API Explorer] documentId:', window.__detourDocumentId);

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
  if (message.type === 'getDocumentId') {
    sendResponse({ documentId: window.__detourDocumentId });
  }
  if (message.type === 'docIdTest') {
    sendResponse({ received: true, documentId: window.__detourDocumentId });
  }
});
