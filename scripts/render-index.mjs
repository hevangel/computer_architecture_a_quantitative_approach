import { readFile, writeFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const data = JSON.parse(await readFile(new URL('data/index.json', root), 'utf8'));
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const link = (path, label) => `<a href="${escape(path)}">${escape(label)}</a>`;
const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escape(data.description)}">
  <title>${escape(data.title)}</title>
  <style>
    :root { color-scheme: light; --ink: #202b36; --muted: #4e5e6b; --paper: #f7f6f1; --line: #cbd3d6; --link: #16536b; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--paper); color: var(--ink); font: 1rem/1.65 system-ui, sans-serif; }
    header, main, footer { width: min(74rem, 100% - 2.5rem); margin-inline: auto; }
    header { padding-block: 3rem 2rem; border-bottom: 1px solid var(--line); }
    h1, h2 { font-family: Georgia, serif; line-height: 1.15; text-wrap: balance; }
    h1 { max-width: 24ch; font-size: clamp(2.3rem, 6vw, 4.7rem); margin: .3em 0; }
    h2 { font-size: clamp(1.6rem, 4vw, 2.1rem); margin-top: 0; }
    h3 { margin: 0 0 .5rem; line-height: 1.4; overflow-wrap: anywhere; }
    p { max-width: 78ch; }
    a { color: var(--link); text-underline-offset: .2em; }
    a:hover { text-decoration-thickness: 2px; }
    a:focus-visible { outline: 3px solid var(--link); outline-offset: 4px; }
    .eyebrow { color: var(--muted); font-size: .8rem; letter-spacing: .12em; text-transform: uppercase; font-weight: 700; }
    nav ul, .resources { display: flex; flex-wrap: wrap; gap: .4rem 1.2rem; padding: 0; list-style: none; }
    section { padding-block: 2rem; border-bottom: 1px solid var(--line); scroll-margin-top: 1rem; }
    .examples { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 20rem), 1fr)); gap: 1rem; padding: 0; list-style: none; }
    article { height: 100%; padding: 1.2rem; border: 1px solid var(--line); border-radius: .5rem; background: #fff; }
    article p { margin: .5rem 0; }
    code { font-family: ui-monospace, Consolas, monospace; }
    pre { padding: 1rem; overflow: auto; border-radius: .4rem; background: #e8edf0; }
    footer { padding-block: 1.5rem; color: var(--muted); }
    .skip { position: absolute; top: -5rem; left: 1rem; padding: .5rem; background: white; }
    .skip:focus { top: .5rem; }
    @media (max-width: 480px) { header, main, footer { width: calc(100% - 2rem); } header { padding-top: 2rem; } }
  </style>
</head>
<body>
  <a class="skip" href="#main">${escape(data.labels.skip)}</a>
  <header>
    <p class="eyebrow">${escape(data.eyebrow)}</p>
    <h1>${escape(data.title)}</h1>
    <p>${escape(data.description)}</p>
    <nav aria-label="${escape(data.labels.navigation)}"><ul>
      <li>${link('#start', data.start.title)}</li>
      ${data.groups.map(group => `<li>${link('#' + group.path, group.title)}</li>`).join('\n      ')}
    </ul></nav>
  </header>
  <main id="main">
    <section id="start" aria-labelledby="start-title">
      <h2 id="start-title">${escape(data.start.title)}</h2>
      <p>${escape(data.start.description)}</p>
      <pre><code>${escape(data.start.commands.join('\n'))}</code></pre>
      <ul class="resources">${data.resources.map(item => `<li>${link(item.path, item.title)}</li>`).join('')}</ul>
      <p>${escape(data.scope)}</p>
    </section>
    ${data.groups.map(group => `<section id="${escape(group.path)}" aria-labelledby="${escape(group.path)}-title">
      <h2 id="${escape(group.path)}-title">${escape(group.title)}</h2>
      <p>${link(group.path + '/README.md', data.labels.chapter)}</p>
      ${group.note ? `<p>${escape(group.note)}</p>` : ''}
      ${group.examples.length ? `<ul class="examples">${group.examples.map(example => `<li><article>
        <h3>${link(example.path + '/README.md', example.title)}</h3>
        <p>${escape(example.description)}</p>
        <ul class="resources">${example.sources.map(source => `<li>${link(source.path, source.title)}</li>`).join('')}</ul>
      </article></li>`).join('\n')}</ul>` : ''}
    </section>`).join('\n')}
  </main>
  <footer><p>${escape(data.footer)}</p></footer>
</body>
</html>
`.replace(/[ \t]+$/gm, '');

const output = new URL('index.html', root);
if (process.argv.includes('--check')) {
  if ((await readFile(output, 'utf8')).replace(/\r\n/g, '\n') !== html) throw new Error('index.html is stale; run node scripts/render-index.mjs');
  console.log('index.html matches data/index.json');
} else {
  await writeFile(output, html);
  console.log('Generated index.html');
}
