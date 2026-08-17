const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

// Previews are screenshots of terminal output, so they hold only a couple
// thousand distinct colors across millions of pixels. Quantizing to a 256-color
// palette costs ~1 RMSE (invisible on antialiased glyph edges) and cuts the
// total asset weight by about 69%. pngquant aborts on its own if it cannot hit
// the quality floor, in which case we keep the untouched original.
const PNGQUANT_QUALITY = '70-95';

// Rendered pixel density. 2x keeps the previews crisp on retina displays.
// The images are served from GitHub rather than the published archive (see
// .pubignore), so their weight costs page load rather than `pub get`, and
// legibility wins over bytes. Render at the target density rather than
// downscaling afterwards: resampling blends flat terminal colors into
// gradients that quantize and compress far worse than a native render.
const DEVICE_SCALE = 2;

function hasCommand(cmd) {
  try {
    execSync(`command -v ${cmd}`, { stdio: 'ignore', shell: '/bin/sh' });
    return true;
  } catch {
    return false;
  }
}

const TOOLS = {
  pngquant: hasCommand('pngquant'),
  oxipng: hasCommand('oxipng'),
};

// Shrinks a PNG in place. Missing tools are skipped rather than fatal, so
// contributors without them still get working (if larger) previews.
function optimize(pngPath) {
  const before = fs.statSync(pngPath).size;

  if (TOOLS.pngquant) {
    const tmp = `${pngPath}.tmp`;
    try {
      execSync(
        `pngquant --quality=${PNGQUANT_QUALITY} --speed 1 --force ` +
          `--output "${tmp}" "${pngPath}"`,
        { stdio: 'ignore' },
      );
      fs.renameSync(tmp, pngPath);
    } catch {
      // Exit 99 means the quality floor was unreachable. Either way the
      // original is still intact, so just drop the partial output.
      if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
    }
  }

  if (TOOLS.oxipng) {
    try {
      execSync(`oxipng -o max --strip safe -q "${pngPath}"`, { stdio: 'ignore' });
    } catch {
      // Lossless pass is a bonus; leave the file as-is if it fails.
    }
  }

  return { before, after: fs.statSync(pngPath).size };
}

function report(name, before, after) {
  const pct = before === after ? '' : `  −${Math.round((1 - after / before) * 100)}%`;
  console.log(`  ${name.padEnd(16)} ${(after / 1024).toFixed(1).padStart(6)} KB${pct}`);
}

function warnMissingTools() {
  const missing = Object.keys(TOOLS).filter((t) => !TOOLS[t]);
  if (missing.length === 0) return;
  console.log(
    `Note: ${missing.join(' and ')} not found — previews will be larger ` +
      `than committed ones.\n      Install with: brew install ${missing.join(' ')}\n`,
  );
}

const PRESETS = [
  // name          — dart arg         — uses ANSI colors?
  ['terminal',       'terminal',       true],
  ['ide',            'ide',            false],
  ['ci',             'ci',             false],
  ['json',           'json',           false],
  ['custom_colors',  'custom_colors',  true],
  ['custom_box',     'custom_box',     false],
  ['data',           'data',           true],
  ['stacktrace',     'stacktrace',     true],
  ['full',           'full',           true],
  ['throttled',      'throttled',      false],
  ['hero',           'hero',           true],
  ['doc_data',       'doc_data',       true],
  ['doc_scoped',     'doc_scoped',     true],
  ['doc_scoped_silent', 'doc_scoped_silent', false],
  ['doc_minlevel',   'doc_minlevel',   true],
  ['doc_mixin',      'doc_mixin',      true],
];

function buildHtml(rawHtml, usesAnsi) {
  // For non-ANSI presets, use lighter text since there are no color spans.
  const textColor = usesAnsi ? '#d4d4d4' : '#c8c8c8';
  return `<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; }
  body {
    background: #191A1C;
    color: ${textColor};
    font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', Menlo, Monaco, monospace;
    font-size: 13px;
    line-height: 1.2;
    padding: 20px 24px;
    display: inline-block;
    white-space: pre;
    -webkit-font-smoothing: antialiased;
  }
</style>
</head>
<body>${rawHtml.trim()}</body>
</html>`;
}

async function renderPreset(puppeteer, [name, dartArg, usesAnsi]) {
  const tmpHtml = path.join(ROOT, `_preview_${name}.html`);
  const styledHtml = path.join(ROOT, `_preview_${name}_styled.html`);
  const outputPath = path.join(ROOT, 'assets', `preview_${name}.png`);

  // Generate ANSI output → HTML via aha
  execSync(
    `dart run tool/generate_preview.dart ${dartArg} | aha --no-header > _preview_${name}.html`,
    { cwd: ROOT, shell: true },
  );

  const rawHtml = fs.readFileSync(tmpHtml, 'utf8');
  fs.writeFileSync(styledHtml, buildHtml(rawHtml, usesAnsi));

  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 800, deviceScaleFactor: DEVICE_SCALE });
  await page.goto('file://' + path.resolve(styledHtml));

  // Uniform width, tight height from content
  const UNIFORM_WIDTH = 920;
  await page.setViewport({ width: UNIFORM_WIDTH, height: 2000, deviceScaleFactor: DEVICE_SCALE });
  // Measure actual content bounds
  const contentBox = await page.evaluate(() => {
    const body = document.body;
    const range = document.createRange();
    range.selectNodeContents(body);
    const rect = range.getBoundingClientRect();
    return { width: rect.width, height: rect.height };
  });
  // Padding matches the body CSS padding (20px top + 20px bottom)
  const finalHeight = Math.ceil(contentBox.height) + 40;
  await page.setViewport({
    width: UNIFORM_WIDTH,
    height: finalHeight,
    deviceScaleFactor: DEVICE_SCALE,
  });

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  await page.screenshot({ path: outputPath, fullPage: true });
  await browser.close();

  // Clean up
  fs.unlinkSync(tmpHtml);
  fs.unlinkSync(styledHtml);

  const { before, after } = optimize(outputPath);
  report(name, before, after);
}

// Recompresses the committed previews without re-rendering them. Useful after
// changing PNGQUANT_QUALITY, or to shrink assets generated before this step
// existed, since it needs neither puppeteer nor aha.
function optimizeExisting() {
  const dir = path.join(ROOT, 'assets');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.png'));

  console.log('Optimizing existing preview images...\n');
  let totalBefore = 0;
  let totalAfter = 0;
  for (const file of files) {
    const { before, after } = optimize(path.join(dir, file));
    report(path.basename(file, '.png').replace(/^preview_/, ''), before, after);
    totalBefore += before;
    totalAfter += after;
  }
  console.log('');
  report('TOTAL', totalBefore, totalAfter);
}

async function main() {
  warnMissingTools();

  if (process.argv.includes('--optimize-only')) {
    optimizeExisting();
    return;
  }

  let puppeteer;
  try {
    puppeteer = require('puppeteer');
  } catch {
    console.log('Installing puppeteer...');
    execSync('npm install puppeteer', { cwd: __dirname, stdio: 'inherit' });
    puppeteer = require('puppeteer');
  }

  console.log('Generating preview images...\n');
  for (const preset of PRESETS) {
    await renderPreset(puppeteer, preset);
  }
  console.log('\nDone!');
}

main().catch(console.error);
