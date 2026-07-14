(function () {
  'use strict';

  const root = document.documentElement;
  const storageKey = 'family-theme';
  const legacyStorageKey = 'notes-theme';
  const themeQuery = window.matchMedia('(prefers-color-scheme: light)');

  function normalize(theme) {
    if (theme === 'mocha') return 'dark';
    return theme === 'light' || theme === 'dark' ? theme : null;
  }

  function storedTheme() {
    try {
      return normalize(localStorage.getItem(storageKey))
        || normalize(localStorage.getItem(legacyStorageKey));
    } catch (error) {
      return null;
    }
  }

  function currentTheme() {
    return normalize(root.getAttribute('data-theme'))
      || (themeQuery.matches ? 'light' : 'dark');
  }

  function updateFamilyLinks(theme) {
    document.querySelectorAll('.site-nav a, .project-nav a').forEach((anchor) => {
      const url = new URL(anchor.href, window.location.href);
      url.searchParams.set('theme', theme);
      anchor.href = url.href;
    });
  }

  function setTheme(theme, options) {
    const normalized = normalize(theme);
    if (!normalized) return;

    root.setAttribute('data-theme', normalized);
    try {
      localStorage.setItem(storageKey, normalized);
      localStorage.setItem(legacyStorageKey, normalized);
    } catch (error) {}

    if (options && options.updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('theme', normalized);
      window.history.replaceState(null, '', url);
    }

    if (document.readyState !== 'loading') updateFamilyLinks(normalized);
    window.dispatchEvent(new CustomEvent('family-theme-change', { detail: { theme: normalized } }));
    window.dispatchEvent(new CustomEvent('notes-theme-change', { detail: { theme: normalized } }));
  }

  const parameterTheme = normalize(new URLSearchParams(window.location.search).get('theme'));
  const initialTheme = parameterTheme || storedTheme();
  if (initialTheme) setTheme(initialTheme);

  document.addEventListener('DOMContentLoaded', () => {
    updateFamilyLinks(currentTheme());
  }, { once: true });

  window.FamilyTheme = {
    currentTheme,
    setTheme,
    storedTheme,
  };
})();
