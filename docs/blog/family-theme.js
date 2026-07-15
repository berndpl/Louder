(function () {
  'use strict';

  const root = document.documentElement;
  const storageKey = 'family-theme';
  const legacyStorageKey = 'notes-theme';
  const paletteStorageKey = 'family-palette';
  const paletteKeys = new Set([
    'default',
    'red',
    'tomato',
    'orange',
    'amber',
    'yellow',
    'lime',
    'green',
    'mint',
    'teal',
    'cyan',
    'blue',
    'indigo',
    'purple',
    'pink',
  ]);
  const customPalettesEnabled = root.hasAttribute('data-custom-palettes');
  const themeQuery = window.matchMedia('(prefers-color-scheme: light)');

  function normalizeTheme(theme) {
    if (theme === 'mocha') return 'dark';
    return theme === 'light' || theme === 'dark' ? theme : null;
  }

  function normalizeFont(font) {
    if (font === 'jetbrains' || font === 'jetbrainsmono') return 'jetbrains-mono';
    return font === 'inconsolata' || font === 'jetbrains-mono' ? font : null;
  }

  function normalizePalette(palette) {
    return paletteKeys.has(palette) ? palette : null;
  }

  function storedTheme() {
    try {
      return normalizeTheme(localStorage.getItem(storageKey))
        || normalizeTheme(localStorage.getItem(legacyStorageKey));
    } catch (error) {
      return null;
    }
  }

  function storedPalette() {
    if (!customPalettesEnabled) return null;
    try {
      return normalizePalette(localStorage.getItem(paletteStorageKey));
    } catch (error) {
      return null;
    }
  }

  function currentTheme() {
    return normalizeTheme(root.getAttribute('data-theme'))
      || (themeQuery.matches ? 'light' : 'dark');
  }

  function currentFont() {
    return normalizeFont(root.getAttribute('data-font')) || 'inconsolata';
  }

  function currentPalette() {
    if (!customPalettesEnabled) return 'default';
    return normalizePalette(root.getAttribute('data-palette')) || 'default';
  }

  function updateFamilyLinks(theme, font, palette) {
    document.querySelectorAll('a[href]').forEach((anchor) => {
      const url = new URL(anchor.href, window.location.href);
      const isFamilyNavigation = Boolean(anchor.closest('.site-nav, .project-nav'));
      const isSameOrigin = url.origin === window.location.origin;
      if (!isFamilyNavigation && !isSameOrigin) return;
      if (url.protocol !== 'http:' && url.protocol !== 'https:' && url.protocol !== 'file:') return;
      url.searchParams.set('theme', theme);
      url.searchParams.set('font', font);
      const carriesPalette = customPalettesEnabled
        && !anchor.closest('.project-nav')
        && (isSameOrigin || Boolean(anchor.closest('.site-nav')));
      if (carriesPalette) url.searchParams.set('palette', palette);
      else url.searchParams.delete('palette');
      anchor.href = url.href;
    });
  }

  function setTheme(theme, options) {
    const normalized = normalizeTheme(theme);
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

    if (document.readyState !== 'loading') {
      updateFamilyLinks(normalized, currentFont(), currentPalette());
    }
    window.dispatchEvent(new CustomEvent('family-theme-change', { detail: { theme: normalized } }));
    window.dispatchEvent(new CustomEvent('notes-theme-change', { detail: { theme: normalized } }));
  }

  function setFont(font, options) {
    const normalized = normalizeFont(font);
    if (!normalized) return;

    root.setAttribute('data-font', normalized);

    if (options && options.updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('font', normalized);
      window.history.replaceState(null, '', url);
    }

    if (document.readyState !== 'loading') {
      updateFamilyLinks(currentTheme(), normalized, currentPalette());
    }
    window.dispatchEvent(new CustomEvent('family-font-change', { detail: { font: normalized } }));
  }

  function setPalette(palette, options) {
    if (!customPalettesEnabled) return;
    const normalized = normalizePalette(palette);
    if (!normalized) return;

    root.setAttribute('data-palette', normalized);
    try {
      if (normalized === 'default') localStorage.removeItem(paletteStorageKey);
      else localStorage.setItem(paletteStorageKey, normalized);
    } catch (error) {}

    if (options && options.updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('palette', normalized);
      window.history.replaceState(null, '', url);
    }

    if (document.readyState !== 'loading') {
      updateFamilyLinks(currentTheme(), currentFont(), normalized);
    }
    window.dispatchEvent(new CustomEvent('family-palette-change', {
      detail: { palette: normalized },
    }));
  }

  const parameters = new URLSearchParams(window.location.search);
  const parameterTheme = normalizeTheme(parameters.get('theme'));
  const initialTheme = parameterTheme || storedTheme();
  if (initialTheme) setTheme(initialTheme);
  setFont(normalizeFont(parameters.get('font')) || 'inconsolata');
  if (customPalettesEnabled) {
    setPalette(normalizePalette(parameters.get('palette')) || storedPalette() || 'default');
  } else {
    root.setAttribute('data-palette', 'default');
    if (parameters.has('palette')) {
      const url = new URL(window.location.href);
      url.searchParams.delete('palette');
      window.history.replaceState(null, '', url);
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    updateFamilyLinks(currentTheme(), currentFont(), currentPalette());
  }, { once: true });

  window.FamilyTheme = {
    currentTheme,
    setTheme,
    storedTheme,
  };

  window.FamilyFont = {
    currentFont,
    setFont,
  };

  window.FamilyPalette = {
    currentPalette,
    setPalette,
    storedPalette,
    isEnabled: () => customPalettesEnabled,
  };
})();
