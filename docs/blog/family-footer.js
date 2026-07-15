(function () {
  'use strict';

  const root = document.documentElement;
  const themeButtons = Array.from(document.querySelectorAll('.theme-toggle'));
  const fontButtons = Array.from(document.querySelectorAll('.font-toggle'));
  const accentPickers = Array.from(document.querySelectorAll('.accent-picker'));
  const familyTheme = window.FamilyTheme;
  const familyFont = window.FamilyFont;
  const familyPalette = window.FamilyPalette;
  const lightQuery = window.matchMedia('(prefers-color-scheme: light)');
  const lightIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="7"/></svg>';
  const darkIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a7 7 0 0 1 0 14z"/></svg>';
  const scale = (values) => values.split('|');
  const accents = [
    { key: 'default', label: 'Project default' },
    {
      key: 'red',
      label: 'Red',
      light: scale('oklch(0.99 0.007 17)|oklch(0.982 0.013 17)|oklch(0.965 0.036 17)|oklch(0.946 0.051 17)|oklch(0.924 0.067 17)|oklch(0.895 0.083 17)|oklch(0.856 0.101 17)|oklch(0.802 0.124 17)|oklch(0.647 0.176 17)|oklch(0.61 0.186 17)|oklch(0.49 0.155 17)|oklch(0.367 0.102 17)'),
      dark: scale('oklch(0.195 0.03 17)|oklch(0.227 0.041 17)|oklch(0.295 0.082 17)|oklch(0.348 0.111 17)|oklch(0.394 0.133 17)|oklch(0.445 0.151 17)|oklch(0.513 0.168 17)|oklch(0.599 0.184 17)|oklch(0.647 0.176 17)|oklch(0.699 0.166 17)|oklch(0.863 0.102 17)|oklch(0.927 0.062 17)'),
    },
    {
      key: 'tomato',
      label: 'Tomato',
      light: scale('oklch(0.99 0.008 25)|oklch(0.982 0.015 25)|oklch(0.966 0.038 25)|oklch(0.948 0.057 25)|oklch(0.926 0.076 25)|oklch(0.898 0.096 25)|oklch(0.859 0.118 25)|oklch(0.803 0.145 25)|oklch(0.657 0.183 25)|oklch(0.615 0.189 25)|oklch(0.497 0.152 25)|oklch(0.372 0.1 25)'),
      dark: scale('oklch(0.191 0.029 25)|oklch(0.222 0.04 25)|oklch(0.287 0.076 25)|oklch(0.338 0.106 25)|oklch(0.384 0.13 25)|oklch(0.435 0.151 25)|oklch(0.503 0.172 25)|oklch(0.591 0.192 25)|oklch(0.657 0.183 25)|oklch(0.712 0.172 25)|oklch(0.866 0.107 25)|oklch(0.933 0.063 25)'),
    },
    {
      key: 'orange',
      label: 'Orange',
      light: scale('oklch(0.991 0.009 55)|oklch(0.983 0.017 55)|oklch(0.967 0.042 55)|oklch(0.95 0.063 55)|oklch(0.928 0.084 55)|oklch(0.9 0.105 55)|oklch(0.861 0.128 55)|oklch(0.804 0.156 55)|oklch(0.67 0.185 55)|oklch(0.626 0.187 55)|oklch(0.505 0.15 55)|oklch(0.377 0.099 55)'),
      dark: scale('oklch(0.188 0.028 55)|oklch(0.22 0.039 55)|oklch(0.284 0.074 55)|oklch(0.335 0.103 55)|oklch(0.381 0.127 55)|oklch(0.432 0.148 55)|oklch(0.5 0.169 55)|oklch(0.588 0.189 55)|oklch(0.67 0.185 55)|oklch(0.725 0.175 55)|oklch(0.869 0.108 55)|oklch(0.935 0.063 55)'),
    },
    {
      key: 'amber',
      label: 'Amber',
      light: scale('oklch(0.991 0.011 75)|oklch(0.985 0.022 75)|oklch(0.973 0.052 75)|oklch(0.961 0.078 75)|oklch(0.944 0.103 75)|oklch(0.921 0.128 75)|oklch(0.887 0.154 75)|oklch(0.837 0.184 75)|oklch(0.733 0.194 75)|oklch(0.676 0.184 75)|oklch(0.534 0.141 75)|oklch(0.389 0.091 75)'),
      dark: scale('oklch(0.193 0.027 75)|oklch(0.224 0.038 75)|oklch(0.288 0.072 75)|oklch(0.338 0.1 75)|oklch(0.383 0.123 75)|oklch(0.433 0.144 75)|oklch(0.501 0.166 75)|oklch(0.592 0.188 75)|oklch(0.733 0.194 75)|oklch(0.788 0.177 75)|oklch(0.894 0.11 75)|oklch(0.945 0.064 75)'),
    },
    {
      key: 'yellow',
      label: 'Yellow',
      light: scale('oklch(0.991 0.01 91)|oklch(0.985 0.021 91)|oklch(0.972 0.049 91)|oklch(0.96 0.074 91)|oklch(0.943 0.098 91)|oklch(0.92 0.122 91)|oklch(0.886 0.147 91)|oklch(0.835 0.176 91)|oklch(0.725 0.187 91)|oklch(0.667 0.177 91)|oklch(0.527 0.136 91)|oklch(0.385 0.088 91)'),
      dark: scale('oklch(0.192 0.026 91)|oklch(0.223 0.037 91)|oklch(0.286 0.07 91)|oklch(0.336 0.097 91)|oklch(0.381 0.119 91)|oklch(0.431 0.14 91)|oklch(0.498 0.161 91)|oklch(0.588 0.183 91)|oklch(0.725 0.187 91)|oklch(0.78 0.171 91)|oklch(0.892 0.108 91)|oklch(0.943 0.063 91)'),
    },
    {
      key: 'lime',
      label: 'Lime',
      light: scale('oklch(0.99 0.012 120)|oklch(0.981 0.024 120)|oklch(0.965 0.055 120)|oklch(0.947 0.082 120)|oklch(0.925 0.108 120)|oklch(0.897 0.134 120)|oklch(0.859 0.162 120)|oklch(0.805 0.193 120)|oklch(0.703 0.205 120)|oklch(0.651 0.195 120)|oklch(0.512 0.149 120)|oklch(0.373 0.096 120)'),
      dark: scale('oklch(0.185 0.031 120)|oklch(0.216 0.043 120)|oklch(0.28 0.08 120)|oklch(0.331 0.111 120)|oklch(0.377 0.137 120)|oklch(0.428 0.161 120)|oklch(0.496 0.184 120)|oklch(0.585 0.205 120)|oklch(0.703 0.205 120)|oklch(0.761 0.186 120)|oklch(0.875 0.117 120)|oklch(0.933 0.068 120)'),
    },
    {
      key: 'green',
      label: 'Green',
      light: scale('oklch(0.989 0.01 145)|oklch(0.978 0.018 145)|oklch(0.956 0.042 145)|oklch(0.931 0.062 145)|oklch(0.902 0.082 145)|oklch(0.868 0.102 145)|oklch(0.823 0.125 145)|oklch(0.762 0.153 145)|oklch(0.623 0.178 145)|oklch(0.579 0.179 145)|oklch(0.464 0.143 145)|oklch(0.348 0.095 145)'),
      dark: scale('oklch(0.178 0.029 145)|oklch(0.209 0.041 145)|oklch(0.272 0.076 145)|oklch(0.322 0.103 145)|oklch(0.367 0.125 145)|oklch(0.417 0.145 145)|oklch(0.484 0.164 145)|oklch(0.571 0.181 145)|oklch(0.623 0.178 145)|oklch(0.676 0.167 145)|oklch(0.843 0.107 145)|oklch(0.919 0.063 145)'),
    },
    {
      key: 'mint',
      label: 'Mint',
      light: scale('oklch(0.989 0.012 165)|oklch(0.977 0.021 165)|oklch(0.953 0.048 165)|oklch(0.926 0.071 165)|oklch(0.895 0.094 165)|oklch(0.859 0.117 165)|oklch(0.811 0.143 165)|oklch(0.747 0.175 165)|oklch(0.609 0.192 165)|oklch(0.565 0.192 165)|oklch(0.454 0.154 165)|oklch(0.341 0.102 165)'),
      dark: scale('oklch(0.175 0.032 165)|oklch(0.206 0.045 165)|oklch(0.269 0.083 165)|oklch(0.318 0.113 165)|oklch(0.363 0.138 165)|oklch(0.413 0.161 165)|oklch(0.48 0.183 165)|oklch(0.566 0.202 165)|oklch(0.609 0.192 165)|oklch(0.662 0.178 165)|oklch(0.831 0.115 165)|oklch(0.912 0.068 165)'),
    },
    {
      key: 'teal',
      label: 'Teal',
      light: scale('oklch(0.989 0.011 180)|oklch(0.977 0.019 180)|oklch(0.954 0.044 180)|oklch(0.928 0.065 180)|oklch(0.898 0.086 180)|oklch(0.863 0.107 180)|oklch(0.817 0.131 180)|oklch(0.755 0.16 180)|oklch(0.618 0.182 180)|oklch(0.574 0.182 180)|oklch(0.461 0.146 180)|oklch(0.346 0.097 180)'),
      dark: scale('oklch(0.176 0.03 180)|oklch(0.207 0.042 180)|oklch(0.27 0.078 180)|oklch(0.319 0.106 180)|oklch(0.364 0.129 180)|oklch(0.414 0.15 180)|oklch(0.481 0.17 180)|oklch(0.567 0.187 180)|oklch(0.618 0.182 180)|oklch(0.671 0.17 180)|oklch(0.839 0.109 180)|oklch(0.916 0.064 180)'),
    },
    {
      key: 'cyan',
      label: 'Cyan',
      light: scale('oklch(0.989 0.01 210)|oklch(0.978 0.018 210)|oklch(0.956 0.042 210)|oklch(0.931 0.062 210)|oklch(0.902 0.082 210)|oklch(0.868 0.102 210)|oklch(0.823 0.125 210)|oklch(0.762 0.153 210)|oklch(0.623 0.178 210)|oklch(0.579 0.179 210)|oklch(0.464 0.143 210)|oklch(0.348 0.095 210)'),
      dark: scale('oklch(0.178 0.029 210)|oklch(0.209 0.041 210)|oklch(0.272 0.076 210)|oklch(0.322 0.103 210)|oklch(0.367 0.125 210)|oklch(0.417 0.145 210)|oklch(0.484 0.164 210)|oklch(0.571 0.181 210)|oklch(0.623 0.178 210)|oklch(0.676 0.167 210)|oklch(0.843 0.107 210)|oklch(0.919 0.063 210)'),
    },
    {
      key: 'blue',
      label: 'Blue',
      light: scale('oklch(0.989 0.008 252)|oklch(0.978 0.014 252)|oklch(0.958 0.035 252)|oklch(0.936 0.053 252)|oklch(0.912 0.071 252)|oklch(0.88 0.09 252)|oklch(0.836 0.112 252)|oklch(0.772 0.142 252)|oklch(0.629 0.187 252)|oklch(0.587 0.193 252)|oklch(0.471 0.155 252)|oklch(0.353 0.103 252)'),
      dark: scale('oklch(0.181 0.028 252)|oklch(0.212 0.039 252)|oklch(0.277 0.077 252)|oklch(0.328 0.107 252)|oklch(0.374 0.131 252)|oklch(0.425 0.152 252)|oklch(0.493 0.172 252)|oklch(0.579 0.191 252)|oklch(0.629 0.187 252)|oklch(0.682 0.176 252)|oklch(0.849 0.107 252)|oklch(0.921 0.063 252)'),
    },
    {
      key: 'indigo',
      label: 'Indigo',
      light: scale('oklch(0.99 0.008 275)|oklch(0.979 0.014 275)|oklch(0.96 0.034 275)|oklch(0.939 0.051 275)|oklch(0.914 0.069 275)|oklch(0.883 0.088 275)|oklch(0.84 0.11 275)|oklch(0.776 0.139 275)|oklch(0.632 0.185 275)|oklch(0.59 0.191 275)|oklch(0.474 0.154 275)|oklch(0.355 0.102 275)'),
      dark: scale('oklch(0.182 0.027 275)|oklch(0.213 0.038 275)|oklch(0.278 0.075 275)|oklch(0.329 0.104 275)|oklch(0.375 0.128 275)|oklch(0.426 0.149 275)|oklch(0.494 0.17 275)|oklch(0.58 0.19 275)|oklch(0.632 0.185 275)|oklch(0.685 0.173 275)|oklch(0.85 0.107 275)|oklch(0.922 0.063 275)'),
    },
    {
      key: 'purple',
      label: 'Purple',
      light: scale('oklch(0.991 0.009 295)|oklch(0.982 0.015 295)|oklch(0.963 0.036 295)|oklch(0.942 0.054 295)|oklch(0.917 0.072 295)|oklch(0.886 0.091 295)|oklch(0.843 0.113 295)|oklch(0.78 0.141 295)|oklch(0.637 0.185 295)|oklch(0.594 0.191 295)|oklch(0.478 0.154 295)|oklch(0.358 0.102 295)'),
      dark: scale('oklch(0.183 0.027 295)|oklch(0.214 0.038 295)|oklch(0.279 0.075 295)|oklch(0.33 0.105 295)|oklch(0.376 0.129 295)|oklch(0.427 0.151 295)|oklch(0.495 0.172 295)|oklch(0.581 0.192 295)|oklch(0.637 0.185 295)|oklch(0.69 0.174 295)|oklch(0.853 0.107 295)|oklch(0.924 0.063 295)'),
    },
    {
      key: 'pink',
      label: 'Pink',
      light: scale('oklch(0.99 0.009 343)|oklch(0.981 0.016 343)|oklch(0.963 0.038 343)|oklch(0.943 0.057 343)|oklch(0.919 0.076 343)|oklch(0.889 0.095 343)|oklch(0.847 0.117 343)|oklch(0.785 0.144 343)|oklch(0.641 0.185 343)|oklch(0.599 0.191 343)|oklch(0.483 0.154 343)|oklch(0.361 0.102 343)'),
      dark: scale('oklch(0.186 0.027 343)|oklch(0.217 0.038 343)|oklch(0.282 0.074 343)|oklch(0.333 0.103 343)|oklch(0.379 0.127 343)|oklch(0.43 0.148 343)|oklch(0.498 0.169 343)|oklch(0.584 0.189 343)|oklch(0.641 0.185 343)|oklch(0.694 0.174 343)|oklch(0.857 0.107 343)|oklch(0.927 0.063 343)'),
    },
  ];
  const paletteProperties = [
    '--theme-base',
    '--theme-mantle',
    '--theme-surface0',
    '--theme-surface1',
    '--theme-text',
    '--theme-heading',
    '--theme-body-rgb',
    '--theme-body-alpha',
    '--theme-subtext0',
    '--theme-overlay0',
    '--theme-accent',
    '--theme-link',
    '--theme-hover',
    '--theme-generated-base',
    '--theme-generated-border',
    '--theme-generated',
    '--theme-generated-hover',
    '--theme-generated-body-rgb',
    '--theme-button-text',
    '--graph-base',
    '--graph-chord',
    '--graph-color-0',
    '--graph-color-1',
    '--graph-color-2',
    '--graph-color-3',
    '--graph-color-4',
    '--graph-color-5',
  ];
  let selectedAccent = familyPalette ? familyPalette.currentPalette() : 'default';

  if (themeButtons.length === 0 && fontButtons.length === 0 && accentPickers.length === 0) return;

  function currentTheme() {
    return familyTheme ? familyTheme.currentTheme() : (lightQuery.matches ? 'light' : 'dark');
  }

  function currentFont() {
    return familyFont ? familyFont.currentFont() : 'inconsolata';
  }

  function defaultPalette() {
    const inlineValues = new Map(
      paletteProperties.map((property) => [property, root.style.getPropertyValue(property)])
    );
    paletteProperties.forEach((property) => root.style.removeProperty(property));
    const styles = getComputedStyle(root);
    const defaults = Object.fromEntries(
      paletteProperties.map((property) => [property, styles.getPropertyValue(property).trim()])
    );
    inlineValues.forEach((value, property) => {
      if (value) root.style.setProperty(property, value);
    });
    return defaults;
  }

  function accentColors(option) {
    if (option.key === 'default') return [defaultPalette()['--theme-accent'], ''];
    const colors = option[currentTheme()];
    return [colors[8], colors[9]];
  }

  function oklchToRgbChannels(color) {
    const match = /^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)$/i.exec(color);
    if (!match) return '';

    const lightness = Number(match[1]);
    const chroma = Number(match[2]);
    const hue = Number(match[3]) * Math.PI / 180;
    const a = chroma * Math.cos(hue);
    const b = chroma * Math.sin(hue);
    const lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b;
    const mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b;
    const sRoot = lightness - 0.0894841775 * a - 1.291485548 * b;
    const l = lRoot ** 3;
    const m = mRoot ** 3;
    const s = sRoot ** 3;
    const linear = [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    ];
    const channels = linear.map((value) => {
      const gamma = value <= 0.0031308
        ? 12.92 * value
        : 1.055 * value ** (1 / 2.4) - 0.055;
      return Math.round(Math.min(1, Math.max(0, gamma)) * 255);
    });
    return channels.join(', ');
  }

  function paletteTokens(option) {
    const theme = currentTheme();
    const colors = option[theme];
    const surface0 = theme === 'light' ? colors[3] : colors[2];
    const surface1 = theme === 'light' ? colors[5] : colors[4];
    const overlay = theme === 'light' ? colors[9] : colors[7];
    return {
      '--theme-base': colors[0],
      '--theme-mantle': colors[1],
      '--theme-surface0': surface0,
      '--theme-surface1': surface1,
      '--theme-text': colors[11],
      '--theme-heading': colors[11],
      '--theme-body-rgb': oklchToRgbChannels(colors[10]),
      '--theme-body-alpha': '1',
      '--theme-subtext0': colors[10],
      '--theme-overlay0': overlay,
      '--theme-accent': colors[8],
      '--theme-link': colors[8],
      '--theme-hover': colors[9],
      '--theme-generated-base': colors[1],
      '--theme-generated-border': colors[5],
      '--theme-generated': colors[8],
      '--theme-generated-hover': colors[9],
      '--theme-generated-body-rgb': oklchToRgbChannels(colors[10]),
      '--theme-button-text': option.dark[0],
      '--graph-base': colors[0],
      '--graph-chord': `rgba(${oklchToRgbChannels(colors[11])}, 0.08)`,
      '--graph-color-0': colors[6],
      '--graph-color-1': colors[7],
      '--graph-color-2': colors[8],
      '--graph-color-3': colors[9],
      '--graph-color-4': colors[10],
      '--graph-color-5': colors[11],
    };
  }

  function applyAccent() {
    const option = accents.find((accent) => accent.key === selectedAccent);
    paletteProperties.forEach((property) => root.style.removeProperty(property));
    if (option && option.key !== 'default') {
      Object.entries(paletteTokens(option)).forEach(([property, value]) => {
        root.style.setProperty(property, value);
      });
    }
    window.dispatchEvent(new CustomEvent('family-accent-change', {
      detail: { palette: selectedAccent, accent: selectedAccent, theme: currentTheme() },
    }));
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

  function renderFontButtons() {
    const font = currentFont();
    const label = font === 'inconsolata'
      ? 'Switch to JetBrains Mono'
      : 'Switch to Inconsolata';
    fontButtons.forEach((button) => {
      button.textContent = 'Aa';
      button.setAttribute('aria-label', label);
      button.setAttribute('title', label);
      button.setAttribute('aria-pressed', String(font === 'jetbrains-mono'));
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
      const nextPalette = button.dataset.accent;
      if (familyPalette) {
        familyPalette.setPalette(nextPalette, { updateUrl: true });
      } else {
        selectedAccent = nextPalette;
        applyAccent();
        accentPickers.forEach(renderAccentOptions);
      }
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
      if (familyTheme) {
        familyTheme.setTheme(nextTheme, { updateUrl: true });
      } else {
        root.setAttribute('data-theme', nextTheme);
        applyAccent();
        renderThemeButtons();
        accentPickers.forEach(renderAccentOptions);
      }
    });
  });

  fontButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const nextFont = currentFont() === 'inconsolata' ? 'jetbrains-mono' : 'inconsolata';
      if (familyFont) familyFont.setFont(nextFont, { updateUrl: true });
      else root.setAttribute('data-font', nextFont);
      renderFontButtons();
    });
  });

  applyAccent();
  accentPickers.forEach(buildAccentPicker);
  renderThemeButtons();
  renderFontButtons();

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

  function handlePaletteChange(event) {
    const nextPalette = event.detail && event.detail.palette;
    if (!accents.some((accent) => accent.key === nextPalette)) return;
    selectedAccent = nextPalette;
    applyAccent();
    accentPickers.forEach(renderAccentOptions);
  }

  lightQuery.addEventListener('change', handleThemeChange);
  window.addEventListener('family-theme-change', handleThemeChange);
  window.addEventListener('family-font-change', renderFontButtons);
  window.addEventListener('family-palette-change', handlePaletteChange);
})();
