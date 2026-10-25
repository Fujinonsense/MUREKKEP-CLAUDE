// Shows the page in the reader's language: Turkish on a Turkish device, English otherwise.
// #tr or #en in the address picks one by hand. Without this script both languages stay visible.
(function () {
  var titles = { en: document.body.dataset.titleEn, tr: document.body.dataset.titleTr };

  function choose() {
    var hash = location.hash.slice(1);
    if (hash === "tr" || hash === "en") return hash;
    var device = ((navigator.languages && navigator.languages[0]) || navigator.language || "").toLowerCase();
    return device.indexOf("tr") === 0 ? "tr" : "en";
  }

  function show() {
    var lang = choose();
    document.documentElement.lang = lang;
    document.querySelectorAll("section[lang]").forEach(function (s) { s.hidden = s.lang !== lang; });
    document.querySelectorAll("nav a[href^='#']").forEach(function (a) {
      a.setAttribute("aria-current", a.getAttribute("href") === "#" + lang ? "true" : "false");
    });
    // The other page opens in the same language.
    document.querySelectorAll("a[href$='.html'], a[href*='.html#']").forEach(function (a) {
      a.setAttribute("href", a.getAttribute("href").split("#")[0] + "#" + lang);
    });
    if (titles[lang]) document.title = titles[lang];
    window.scrollTo(0, 0);
  }

  show();
  window.addEventListener("hashchange", show);
})();
