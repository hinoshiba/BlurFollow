(() => {
  const panels = [...document.querySelectorAll('[data-page-language]')];
  function show(language, moveFocus = false) {
    const baseHash = location.hash.replace(/^#en-/, '#');
    panels.forEach(panel => { panel.hidden = panel.dataset.pageLanguage !== language; });
    document.documentElement.lang = language;
    const panel = panels.find(item => item.dataset.pageLanguage === language);
    document.title = panel.dataset.pageTitle;
    const url = new URL(location.href);
    if (language === 'en') url.searchParams.set('lang', 'en');
    else url.searchParams.delete('lang');
    url.hash = baseHash && language === 'en' ? '#en-' + baseHash.slice(1) : baseHash;
    history.replaceState(null, '', url);
    if (moveFocus) panel.querySelector('[data-language-switch]').focus({ preventScroll: true });
    if (url.hash) requestAnimationFrame(() => document.getElementById(url.hash.slice(1))?.scrollIntoView());
  }
  document.querySelectorAll('[data-language-switch]').forEach(button => {
    button.addEventListener('click', () => show(button.dataset.languageSwitch, true));
  });
  function fromURL() {
    show(new URL(location.href).searchParams.get('lang') === 'en' || location.hash.startsWith('#en-') ? 'en' : 'ja');
  }
  window.addEventListener('popstate', fromURL);
  window.addEventListener('hashchange', fromURL);
  fromURL();
})();
