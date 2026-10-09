.pragma library
// Original 24-unit outline artwork; no font glyph or external asset dependency.
function source(name, color) {
    var shapes = {
        chat: '<path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-8l-6 3v-3H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/><path d="M7 9h10M7 13h7"/>',
        expand: '<path d="M8 3H3v5M16 3h5v5M21 16v5h-5M3 16v5h5"/>',
        compact: '<path d="M3 8h5V3M21 8h-5V3M16 21v-5h5M8 21v-5H3"/>',
        reload: '<path d="M20 7v5h-5M20 12a8 8 0 1 0-2 5"/>',
        restart: '<path d="M12 3v9M6 5a8 8 0 1 0 12 0"/>',
        close: '<path d="m6 6 12 12M18 6 6 18"/>',
        palette: '<path d="M12 3a9 9 0 1 0 0 18h2a2 2 0 0 0 1-3c-1-2 0-3 2-3h1a3 3 0 0 0 3-3 9 9 0 0 0-9-9Z"/><circle cx="7" cy="10" r="1"/><circle cx="11" cy="7" r="1"/><circle cx="16" cy="8" r="1"/>',
        layout: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 10v10"/>'
    };
    if (!shapes[name] || !/^#[0-9a-f]{6}$/i.test(color)) return "";
    return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="'+color+'" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+shapes[name]+'</svg>');
}
