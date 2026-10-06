.pragma library

// Appearance-only CSS in an isolated world. No messages, credentials, storage,
// requests, application functions or page event handlers are read or changed.
function source(background, foreground, border, fixture) {
    if (![background, foreground, border].every(function(value) { return /^#[0-9a-f]{6}$/i.test(value) })) return ""
    var css = "html,html.light,html.dark,body{"
        + "--main-surface-primary:" + background + ";--main-surface-secondary:" + background + ";"
        + "--main-surface-tertiary:" + background + ";--sidebar-surface-primary:" + background + ";"
        + "--sidebar-surface-secondary:" + background + ";--bg-primary:" + background + ";"
        + "--bg-secondary:" + background + ";--bg-tertiary:" + background + ";"
        + "--bg-elevated-primary:" + background + "!important;--bg-elevated-secondary:" + background + "!important;"
        + "--bg-secondary-surface:" + background + "!important;--composer-surface:" + background + "!important;"
        + "--composer-surface-primary:" + background + "!important;--color-background-composer-primary:" + background + "!important;"
        + "--text-primary:" + foreground + ";--text-secondary:" + foreground + ";"
        + "--text-tertiary:" + foreground + ";--text-quaternary:" + foreground + ";"
        + "--text-placeholder:" + foreground + ";--border-light:" + border + ";"
        + "--border-medium:" + border + ";--border-heavy:" + border + ";"
        + "background-color:" + background + "!important;color:" + foreground + "!important;}"
        + "main,nav,header,form,[data-message-author-role='user'],.bg-token-main-surface-primary,"
        + ".bg-token-main-surface-secondary,.bg-token-sidebar-surface-primary,"
        + ".bg-token-bg-primary,.bg-token-bg-secondary,.bg-token-bg-elevated-primary,"
        + ".bg-token-bg-elevated-secondary,.bg-token-bg-secondary-surface,.bg-surface-primary,"
        + "[data-composer-surface='true']{background-color:" + background + "!important;}"
        + "textarea,[contenteditable='true'],input:not([type='checkbox']):not([type='radio']){"
        + "background-color:" + background + "!important;color:" + foreground + "!important;"
        + "caret-color:" + foreground + "!important;}"
        + "textarea::placeholder,input::placeholder{color:" + foreground + "!important;}";
    return "(() => { 'use strict'; if (!(location.origin === 'https://chatgpt.com'"
        + (fixture ? " || location.protocol === 'data:' || location.href === 'about:blank'" : "")
        + ") || location.pathname.startsWith('/cdn-cgi/')) return;"
        + "let style=document.getElementById('slovn-chatgpt-theme');"
        + "if(style && style.tagName !== 'STYLE') return;"
        + "if(!style){style=document.createElement('style');style.id='slovn-chatgpt-theme';"
        + "document.documentElement.appendChild(style);}style.textContent=" + JSON.stringify(css)
        + ";return !!document.body && getComputedStyle(document.body).backgroundColor === "
        + JSON.stringify("rgb(" + parseInt(background.slice(1,3),16) + ", " + parseInt(background.slice(3,5),16) + ", " + parseInt(background.slice(5,7),16) + ")")
        + "; })();"
}
