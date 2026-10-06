/* On-demand closed-schema DOM diagnostics. No text, labels or URL export. */
(() => {
  'use strict';
  const count = selector => Math.min(16, document.querySelectorAll(selector).length);
  const exists = selector => Boolean(document.querySelector(selector));
  const buttons = [...document.querySelectorAll('button,[role="button"]')];
  const uiLabel = b => b.getAttribute('aria-label') || b.getAttribute('title') || '';
  const named = pattern => buttons.some(b => pattern.test(uiLabel(b)));
  const composer = editors => editors.length === 1 ? editors[0] : null;
  const controls = [...document.querySelectorAll('button,[role="button"],a')];
  const mainNodes = [...document.querySelectorAll('main,[role="main"]')];
  const editors = [...document.querySelectorAll('textarea,[contenteditable="true"]')]
    .filter(e => e.getClientRects().length > 0);
  // Only emptiness metadata is examined. No draft string is returned or stored.
  const hasTextNode = node => {
    if (node.nodeType === Node.TEXT_NODE) return node.length > 0;
    return [...node.childNodes].some(hasTextNode);
  };
  const draft = editors.length === 1
    ? (editors[0].matches('textarea') ? editors[0].value.length > 0 : hasTextNode(editors[0]))
      ? 'PRESENT' : 'EMPTY'
    : 'UNKNOWN';
  const stop = exists('[data-testid="stop-button"]') ||
    named(/^(stop( generating)?|остановить( генерацию)?)$/i);
  const send = exists('[data-testid="send-button"]') ||
    named(/^(send( message| prompt)?|отправить( сообщение| запрос)?)$/i);
  return {
    schema: 1,
    recognized_page: globalThis.__chatgptLiteAdapterV1?.describe().page || 'UNKNOWN',
    nested_mains: mainNodes.length === 2 && mainNodes.some(m => m.contains(mainNodes.find(n => n !== m))),
    editor_in_main: Boolean(composer(editors)?.closest('main,[role="main"]')),
    editor_in_form: Boolean(composer(editors)?.closest('form')),
    submit_count: count('form button[type="submit"]'),
    form_button_count: count('form button'),
    form_named_count: count('form button[aria-label]'),
    form_testid_count: count('form button[data-testid]'),
    voice_testid: exists('[data-testid="composer-speech-button"]'),
    composer_submit_id: exists('#composer-submit-button'),
    model_text: buttons.some(b => b.closest('header,[role="banner"]') &&
      /^ChatGPT(\s|$)/i.test(b.textContent || '')),
    send_prefix: named(/^(send|отправить|отправка)(\s|$)/i),
    voice_named: named(/(voice|голосов)/i),
    menu_count: count('button[aria-haspopup="menu"]'),
    header_menu_count: count('header button[aria-haspopup="menu"],[role="banner"] button[aria-haspopup="menu"]'),
    composer_submit: exists('[data-testid="composer-submit-button"]'),
    model_menu: controls.some(b => b.matches('button[aria-haspopup="menu"]') &&
      /^(chatgpt|model selector|выбор модели)(\s|$)/i.test(b.getAttribute('aria-label') || '')),
    new_chat_link: controls.some(b => /^(new chat|новый чат)$/i.test(b.getAttribute('aria-label') || '')),
    main_count: count('main,[role="main"]'),
    textarea_count: count('textarea'),
    editable_count: count('[contenteditable="true"]'),
    textbox_count: count('[role="textbox"]'),
    form_count: count('form'),
    header_count: count('header,[role="banner"]'),
    nav_count: count('nav,[role="navigation"]'),
    log_count: count('[role="log"]'),
    prompt_id: exists('#prompt-textarea'),
    send_testid: exists('[data-testid="send-button"]'),
    stop_testid: exists('[data-testid="stop-button"]'),
    model_testid: exists('[data-testid="model-switcher-dropdown-button"]'),
    send_named: send,
    new_chat_named: controls.some(b => /^(new chat|новый чат)(\s|$)/i.test(uiLabel(b))),
    model_named: controls.some(b => /^(chatgpt(\s|$)|model( selector)?$|select model$|модель$|выбор модели$)/i.test(uiLabel(b))),
    draft,
    generation: stop ? 'ACTIVE' : send ? 'IDLE_CONTROL' : 'UNKNOWN'
  };
})()
