(function () {
  'use strict';

  const root = document.documentElement;
  const themeButtons = Array.from(document.querySelectorAll('.theme-toggle'));
  const accentPickers = Array.from(document.querySelectorAll('.accent-picker'));
  const familyTheme = window.FamilyTheme;
  const lightQuery = window.matchMedia('(prefers-color-scheme: light)');
  const lightIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="7"/></svg>';
  const darkIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a7 7 0 0 1 0 14z"/></svg>';
  const accents = [
    { key: 'default', label: 'Project default' },
    { key: 'mauve', label: 'Mauve', light: ['#8839ef', '#6d4aff'], dark: ['#cba6f7', '#ddb6f2'] },
    { key: 'blue', label: 'Blue', light: ['#1e66f5', '#5b6dff'], dark: ['#89b4fa', '#b4befe'] },
    { key: 'teal', label: 'Teal', light: ['#179299', '#04a5e5'], dark: ['#94e2d5', '#89dceb'] },
    { key: 'green', label: 'Green', light: ['#40a02b', '#179299'], dark: ['#a6e3a1', '#94e2d5'] },
    { key: 'peach', label: 'Peach', light: ['#fe640b', '#df8e1d'], dark: ['#fab387', '#f9e2af'] },
    { key: 'rose', label: 'Rose', light: ['#d20f39', '#e64553'], dark: ['#f38ba8', '#eb6f92'] },
  ];
  let selectedAccent = 'default';

  if (themeButtons.length === 0 && accentPickers.length === 0) return;

  function currentTheme() {
    return familyTheme ? familyTheme.currentTheme() : (lightQuery.matches ? 'light' : 'dark');
  }

  function defaultAccent() {
    const inlineAccent = root.style.getPropertyValue('--theme-accent');
    const inlineLink = root.style.getPropertyValue('--theme-link');
    const inlineHover = root.style.getPropertyValue('--theme-hover');
    root.style.removeProperty('--theme-accent');
    root.style.removeProperty('--theme-link');
    root.style.removeProperty('--theme-hover');
    const accent = getComputedStyle(root).getPropertyValue('--theme-accent').trim();
    if (inlineAccent) root.style.setProperty('--theme-accent', inlineAccent);
    if (inlineLink) root.style.setProperty('--theme-link', inlineLink);
    if (inlineHover) root.style.setProperty('--theme-hover', inlineHover);
    return accent;
  }

  function accentColors(option) {
    if (option.key === 'default') return [defaultAccent(), ''];
    return option[currentTheme()];
  }

  function applyAccent() {
    const option = accents.find((accent) => accent.key === selectedAccent);
    if (!option || option.key === 'default') {
      root.style.removeProperty('--theme-accent');
      root.style.removeProperty('--theme-link');
      root.style.removeProperty('--theme-hover');
      return;
    }
    const [accent, hover] = accentColors(option);
    root.style.setProperty('--theme-accent', accent);
    root.style.setProperty('--theme-link', accent);
    root.style.setProperty('--theme-hover', hover);
  }

  function renderThemeButtons() {
    const theme = currentTheme();
    const label = theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme';
    const icon = theme === 'light' ? lightIcon : darkIcon;
    themeButtons.forEach((button) => {
      button.innerHTML = icon;
      button.setAttribute('aria-label', label);
      button.setAttribute('title', label);
    });
  }

  function renderAccentOptions(picker) {
    const palette = picker.querySelector('.accent-palette');
    if (!palette) return;
    palette.querySelectorAll('.accent-option').forEach((button) => {
      const option = accents.find((accent) => accent.key === button.dataset.accent);
      if (!option) return;
      button.style.setProperty('--accent-swatch', accentColors(option)[0]);
      button.setAttribute('aria-checked', String(option.key === selectedAccent));
    });
  }

  function setPaletteOpen(picker, open, moveFocus) {
    const toggle = picker.querySelector('.accent-toggle');
    const palette = picker.querySelector('.accent-palette');
    if (!toggle || !palette) return;
    palette.hidden = !open;
    toggle.setAttribute('aria-expanded', String(open));
    if (open && moveFocus) {
      palette.querySelector('[aria-checked="true"]')?.focus();
    }
  }

  function buildAccentPicker(picker, index) {
    const toggle = picker.querySelector('.accent-toggle');
    const palette = picker.querySelector('.accent-palette');
    if (!toggle || !palette) return;
    const paletteId = `accent-palette-${index + 1}`;
    palette.id = paletteId;
    toggle.setAttribute('aria-controls', paletteId);
    palette.innerHTML = accents.map((option) => (
      `<button class="accent-option" type="button" role="menuitemradio" data-accent="${option.key}" aria-label="${option.label}" aria-checked="${option.key === selectedAccent}"></button>`
    )).join('');
    renderAccentOptions(picker);

    toggle.addEventListener('click', () => {
      const open = palette.hidden;
      accentPickers.forEach((other) => setPaletteOpen(other, false, false));
      setPaletteOpen(picker, open, open);
    });

    palette.addEventListener('click', (event) => {
      const button = event.target.closest('.accent-option');
      if (!button) return;
      selectedAccent = button.dataset.accent;
      applyAccent();
      accentPickers.forEach(renderAccentOptions);
      setPaletteOpen(picker, false, false);
      toggle.focus();
    });

    palette.addEventListener('keydown', (event) => {
      const options = Array.from(palette.querySelectorAll('.accent-option'));
      const currentIndex = options.indexOf(document.activeElement);
      let nextIndex = currentIndex;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') nextIndex = (currentIndex + 1) % options.length;
      else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') nextIndex = (currentIndex - 1 + options.length) % options.length;
      else if (event.key === 'Home') nextIndex = 0;
      else if (event.key === 'End') nextIndex = options.length - 1;
      else if (event.key === 'Escape') {
        event.preventDefault();
        setPaletteOpen(picker, false, false);
        toggle.focus();
        return;
      } else return;
      event.preventDefault();
      options[nextIndex].focus();
    });
  }

  themeButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const nextTheme = currentTheme() === 'dark' ? 'light' : 'dark';
      if (familyTheme) familyTheme.setTheme(nextTheme, { updateUrl: true });
      applyAccent();
      renderThemeButtons();
      accentPickers.forEach(renderAccentOptions);
    });
  });

  accentPickers.forEach(buildAccentPicker);
  renderThemeButtons();

  document.addEventListener('click', (event) => {
    accentPickers.forEach((picker) => {
      if (!picker.contains(event.target)) setPaletteOpen(picker, false, false);
    });
  });

  function handleThemeChange() {
    applyAccent();
    renderThemeButtons();
    accentPickers.forEach(renderAccentOptions);
  }

  lightQuery.addEventListener('change', handleThemeChange);
  window.addEventListener('family-theme-change', handleThemeChange);
})();
