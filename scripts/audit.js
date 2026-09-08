/* Dependency-free accessibility audit, run in the page via headless Chrome.
 * Covers the failure modes that actually apply to a static two-link page:
 * headings, image alt text, link naming, nested interactives, duplicate ids,
 * WCAG 2.2 target size, and real computed colour contrast.
 *
 * Usage: see scripts/audit.sh
 */
(function () {
  var problems = [];
  var notes = [];

  function srText(el) {
    var label = el.getAttribute('aria-label');
    if (label && label.trim()) return label.trim();
    return (el.textContent || '').replace(/\s+/g, ' ').trim();
  }

  /* ---------------------------------------------------------- headings ---- */
  var headings = [].slice.call(document.querySelectorAll('h1,h2,h3,h4,h5,h6'));
  var h1s = headings.filter(function (h) {
    return h.tagName === 'H1';
  });
  if (h1s.length !== 1) problems.push('expected exactly one h1, found ' + h1s.length);

  var previous = 0;
  headings.forEach(function (h) {
    var level = +h.tagName[1];
    if (previous && level > previous + 1) {
      problems.push('heading level skipped: ' + h.tagName + ' after H' + previous);
    }
    if (!srText(h)) problems.push('empty heading: ' + h.tagName);
    previous = level;
  });
  notes.push(
    'headings: ' +
      headings
        .map(function (h) {
          return h.tagName + '"' + srText(h) + '"';
        })
        .join(' ')
  );

  /* ------------------------------------------------------------- images --- */
  [].slice.call(document.images).forEach(function (img) {
    if (!img.hasAttribute('alt')) problems.push('img with no alt attribute: ' + img.currentSrc);
    else if (!img.alt.trim()) problems.push('img with empty alt: ' + img.currentSrc);
    if (!img.getAttribute('width') || !img.getAttribute('height')) {
      problems.push('img without intrinsic width/height (CLS risk): ' + img.currentSrc);
    }
  });
  notes.push('images: ' + document.images.length + ' checked');

  /* -------------------------------------------------------------- links --- */
  var links = [].slice.call(document.querySelectorAll('a[href]'));
  links.forEach(function (a) {
    if (!srText(a)) problems.push('link with no accessible name: ' + a.getAttribute('href'));
    if (a.querySelector('a,button,input,select,textarea')) {
      problems.push('nested interactive element inside link: ' + a.getAttribute('href'));
    }
    var rect = a.getBoundingClientRect();
    // WCAG 2.2 SC 2.5.8 target size (minimum) is 24x24 CSS px.
    if (rect.width && rect.height && (rect.width < 24 || rect.height < 24)) {
      problems.push(
        'target smaller than 24x24: "' +
          srText(a) +
          '" is ' +
          Math.round(rect.width) +
          'x' +
          Math.round(rect.height)
      );
    }
  });
  notes.push(
    'links: ' +
      links
        .map(function (a) {
          return '"' + srText(a) + '"->' + a.getAttribute('href');
        })
        .join(' | ')
  );

  /* ----------------------------------------------------------------- ids --- */
  var seen = {};
  [].slice.call(document.querySelectorAll('[id]')).forEach(function (el) {
    if (seen[el.id]) problems.push('duplicate id: ' + el.id);
    seen[el.id] = true;
  });

  /* -------------------------------------------------------------- lang ---- */
  if (!document.documentElement.lang) problems.push('<html> has no lang attribute');

  /* ---------------------------------------------------------- contrast ---- */
  function parseRGB(str) {
    var m = str.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var parts = m[1].split(',').map(parseFloat);
    return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
  }

  function luminance(c) {
    var chan = [c.r, c.g, c.b].map(function (v) {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * chan[0] + 0.7152 * chan[1] + 0.0722 * chan[2];
  }

  function over(fg, bg) {
    // flatten a translucent foreground onto an opaque background
    var a = fg.a;
    return {
      r: fg.r * a + bg.r * (1 - a),
      g: fg.g * a + bg.g * (1 - a),
      b: fg.b * a + bg.b * (1 - a),
      a: 1
    };
  }

  function ratio(fg, bg) {
    var l1 = luminance(fg);
    var l2 = luminance(bg);
    var hi = Math.max(l1, l2);
    var lo = Math.min(l1, l2);
    return (hi + 0.05) / (lo + 0.05);
  }

  // Effective page background. Every text element here sits on it.
  var pageBG = parseRGB(getComputedStyle(document.body).backgroundColor);

  var sampled = [
    ['.mark', 'top bar'],
    ['.wordmark', 'wordmark'],
    ['.deck', 'deck'],
    ['.card--skye .name .given', 'Skye given name'],
    ['.card--skye .name .family', 'Skye family name'],
    ['.card--skye .role', 'Skye role (cyan accent)'],
    ['.card--carl .role', 'Carl role (amber accent)'],
    ['.card--skye .bio', 'bio'],
    ['.cta', 'CTA label'],
    ['.elsewhere a', 'secondary link'],
    ['.footer p', 'footer text'],
    ['.footer a', 'footer link']
  ];

  sampled.forEach(function (pair) {
    var el = document.querySelector(pair[0]);
    if (!el) {
      problems.push('contrast sample missing: ' + pair[0]);
      return;
    }
    var cs = getComputedStyle(el);
    var fg = parseRGB(cs.color);
    var flat = over(fg, pageBG);
    var r = ratio(flat, pageBG);
    var px = parseFloat(cs.fontSize);
    var bold = parseInt(cs.fontWeight, 10) >= 700;
    // WCAG large text = >=24px, or >=18.66px bold.
    var large = px >= 24 || (bold && px >= 18.66);
    var need = large ? 3 : 4.5;
    var verdict = r >= need ? 'pass' : 'FAIL';
    var line =
      pair[1] +
      ': ' +
      r.toFixed(2) +
      ':1 (needs ' +
      need +
      ', ' +
      px.toFixed(1) +
      'px' +
      (large ? ' large' : '') +
      ') ' +
      verdict;
    if (r < need) problems.push('contrast ' + line);
    else notes.push('contrast ' + line);
  });

  /* -------------------------------------------------------- focus order --- */
  var focusables = [].slice.call(
    document.querySelectorAll('a[href],button,input,select,textarea,[tabindex]')
  );
  notes.push(
    'tab order: ' +
      focusables
        .map(function (el) {
          return '"' + srText(el).slice(0, 22) + '"';
        })
        .join(' > ')
  );

  var out =
    (problems.length ? 'PROBLEMS (' + problems.length + ')\n  ' + problems.join('\n  ') : 'NO PROBLEMS FOUND') +
    '\n\nDETAIL\n  ' +
    notes.join('\n  ');

  var pre = document.createElement('pre');
  pre.id = 'audit';
  pre.textContent = out;
  document.body.appendChild(pre);
})();
