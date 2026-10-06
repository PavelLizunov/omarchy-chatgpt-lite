/* Fixture-verified structural adapter. No framework, transport or message parsing. */
(() => {
  'use strict';
  const key = '__chatgptLiteAdapterV1';
  if (globalThis[key]) return true;
  const owned = new Set();
  let style = null, observer = null, scheduled = false, enabled = false;
  let current = {page: 'UNKNOWN', reduction: 'DISABLED'};
  const names = {
    send: /^(send( message)?|отправить( сообщение)?)$/i,
    stop: /^(stop( generating)?|остановить( генерацию)?)$/i,
    model: /^(model( selector)?|select model|модель|выбор модели)$/i,
    newChat: /^(new chat|новый чат)$/i,
    login: /^(log in|sign in|войти)$/i,
    security: /^(verify you are human|подтвердите, что вы человек)$/i,
    optional: /^(suggestions|recommendations|promotions|voice controls|auxiliary panel|history|projects|подсказки|рекомендации|реклама|голосовые функции|дополнительная панель|история|проекты)$/i
  };
  // Accessible names are compared locally against closed patterns. Arbitrary
  // labels, DOM text, draft text and URL parameters never enter diagnostics.
  const label = element => element.getAttribute('aria-label') || '';
  const matching = (container, pattern, selector = 'button,[role="button"]') =>
    [...container.querySelectorAll(selector)].find(element => pattern.test(label(element)));
  const restore = () => {
    for (const element of owned) element.removeAttribute('data-chatgpt-lite-hidden');
    owned.clear();
    if (style) style.remove();
    style = null;
  };
  const locate = () => {
    if (document.querySelector('input[type="password"]') || matching(document, names.login))
      return {page: 'AUTHENTICATION'};
    if (document.querySelector('[data-security-verification]') || matching(document, names.security))
      return {page: 'SECURITY_VERIFICATION'};
    const mains = [...document.querySelectorAll('main,[role="main"]')];
    const composers = [...document.querySelectorAll('textarea,[contenteditable="true"][role="textbox"]')]
      .filter(element => element.getClientRects().length > 0);
    if (composers.length !== 1) return {page: 'UNKNOWN'};
    const composer = composers[0];
    const main = composer.closest('main,[role="main"]');
    // Multiple nested semantic mains are acceptable only when every main owns
    // the same composer. A disjoint main remains unknown, never guessed.
    if (!main || !mains.length || mains.some(region => !region.contains(composer)))
      return {page: 'UNKNOWN'};
    const form = composer.closest('form');
    const action = form && (matching(form, names.send) || matching(form, names.stop));
    const model = matching(main, names.model);
    const newChat = matching(main, names.newChat);
    if (!form || !main.contains(form) || !action || !model || !newChat)
      return {page: 'UNKNOWN'};
    const conversations = main.querySelectorAll('[role="log"][aria-live]');
    if (conversations.length > 1) return {page: 'UNKNOWN'};
    const conversation = conversations[0] || null;
    // Empty chat is valid without a conversation. A semantic log is required
    // for a conversation; no body parsing or message counting is needed.
    const page = conversation ? 'CONVERSATION' : 'CHAT_HOME';
    return {page, main, form, composer, model, newChat, conversation};
  };
  const publish = () => {
    const handler = globalThis.webkit?.messageHandlers?.liteState;
    if (handler) handler.postMessage(JSON.stringify(current));
    return {...current};
  };
  const apply = () => {
    scheduled = false;
    restore();
    const regions = locate();
    current = {page: regions.page, reduction: enabled ? 'DEGRADED' : 'DISABLED'};
    if (!enabled || !regions.main) return publish();
    const keep = [regions.form, regions.model, regions.newChat, regions.conversation].filter(Boolean);
    // Only optional direct siblings in the verified main are candidates.
    // Portalled dialogs/menus and unrecognized siblings are always untouched.
    for (const element of regions.main.children) {
      if (keep.some(region => element === region || element.contains(region))) continue;
      if (element.matches('input,textarea,[contenteditable="true"],button,a,[role="button"],[role="dialog"],[role="menu"]') ||
          element.querySelector('[role="dialog"],[role="menu"],input,textarea,[contenteditable="true"],button[type="submit"]') ||
          matching(element, names.send) || matching(element, names.stop) ||
          matching(element, names.model) || matching(element, names.newChat)) continue;
      if (!names.optional.test(label(element))) continue;
      element.setAttribute('data-chatgpt-lite-hidden', 'v1');
      owned.add(element);
    }
    style = document.createElement('style');
    style.dataset.chatgptLiteStyle = 'v1';
    style.textContent = '[data-chatgpt-lite-hidden="v1"] { display: none !important; }';
    document.head.append(style);
    current.reduction = 'ENABLED';
    return publish();
  };
  const relevant = record => {
    if (record.type === 'attributes') {
      return !record.target.closest('[role="log"]') &&
        !record.target.closest('style[data-chatgpt-lite-style]');
    }
    const changed = [...record.addedNodes, ...record.removedNodes];
    return changed.some(node => node.nodeType === Node.ELEMENT_NODE &&
      !node.matches('style[data-chatgpt-lite-style]') &&
      (!record.target.closest('[role="log"]') ||
       node.matches('form,textarea,[role="textbox"],[role="dialog"]')));
  };
  const watch = () => {
    if (observer) observer.disconnect();
    observer = new MutationObserver(records => {
      if (!enabled || scheduled || !records.some(relevant)) return;
      scheduled = true;
      requestAnimationFrame(() => { if (enabled) { apply(); watch(); } else scheduled = false; });
    });
    // Watch the verified main and its direct parent, not the full document.
    // The parent catches route replacement. No characterData observation.
    const found = locate();
    const editors = [...document.querySelectorAll('textarea,[contenteditable="true"][role="textbox"]')]
      .filter(element => element.getClientRects().length > 0);
    const fallback = editors.length === 1 ? editors[0].closest('main,[role="main"]') : null;
    const main = found.main || (found.page === 'UNKNOWN' && fallback &&
      [...document.querySelectorAll('main,[role="main"]')].every(m => m.contains(editors[0])) ? fallback : null);
    if (!main) return;
    observer.observe(main, {childList: true, subtree: true, attributes: true,
      attributeFilter: ['aria-label', 'role', 'contenteditable', 'type']});
    if (main.parentElement) observer.observe(main.parentElement, {childList: true});
  };
  const setEnabled = value => {
    enabled = value === true;
    if (observer) observer.disconnect();
    const result = apply();
    if (enabled) watch();
    return result;
  };
  const describe = () => {
    const r = locate();
    return {schema: 1, page: r.page, composer: Boolean(r.composer),
      action: Boolean(r.form), model: Boolean(r.model), new_chat: Boolean(r.newChat),
      conversation: Boolean(r.conversation)};
  };
  globalThis[key] = Object.freeze({setEnabled, apply, describe, status: () => ({...current})});
  return true;
})()
