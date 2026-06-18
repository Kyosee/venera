import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const ICON = 'https://raw.githubusercontent.com/Kyosee/venera/master/assets/app_icon.png';

function template() {
  return {
    name: 'Venera',
    identifier: 'io.github.kyosee.venera',
    subtitle: 'A cross-platform manga/comic reader',
    iconURL: ICON,
    apps: [{
      name: 'Venera',
      bundleIdentifier: 'io.github.kyosee.venera',
      developerName: 'Kyosee',
      subtitle: 'A cross-platform manga/comic reader',
      localizedDescription: 'Venera is a cross-platform manga/comic reader with self-hosted Web frontend support.',
      iconURL: ICON,
      category: 'entertainment',
      screenshots: [],
      versions: [],
    }],
    news: [],
  };
}

function verKey(v) {
  const p = String(v.version).split('.').map((n) => parseInt(n, 10) || 0);
  while (p.length < 3) p.push(0);
  return [p[0], p[1], p[2], parseInt(v.buildVersion, 10) || 0];
}

function cmpDesc(a, b) {
  const ka = verKey(a);
  const kb = verKey(b);
  for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return kb[i] - ka[i];
  return 0;
}

export function buildSource(existing, input) {
  const base = existing && Array.isArray(existing.apps) && existing.apps[0] ? existing : template();
  const app = base.apps[0];
  if (!Array.isArray(app.versions)) app.versions = [];

  const entry = {
    version: input.version,
    buildVersion: input.build,
    date: input.date,
    localizedDescription: input.description ?? '',
    downloadURL: input.downloadURL,
    size: Number(input.size),
    minOSVersion: input.minOSVersion || '14.0',
  };

  app.versions = app.versions.filter(
    (v) => !(v.version === entry.version && v.buildVersion === entry.buildVersion),
  );
  app.versions.push(entry);
  app.versions.sort(cmpDesc);

  const latest = app.versions[0];
  app.version = latest.version;
  app.versionDate = latest.date;
  app.versionDescription = latest.localizedDescription;
  app.downloadURL = latest.downloadURL;
  app.size = latest.size;
  return base;
}

function main() {
  const sourceFile = process.env.SOURCE_FILE || 'altstore-source.json';
  const existing = fs.existsSync(sourceFile)
    ? JSON.parse(fs.readFileSync(sourceFile, 'utf8'))
    : null;

  let description = '';
  const notes = process.env.NOTES_FILE;
  if (notes && fs.existsSync(notes)) description = fs.readFileSync(notes, 'utf8').trim();

  const next = buildSource(existing, {
    version: process.env.VERSION,
    build: process.env.BUILD,
    date: (process.env.PUB_DATE || '').slice(0, 10),
    description,
    downloadURL: process.env.DOWNLOAD_URL,
    size: process.env.SIZE,
    minOSVersion: process.env.MIN_OS || '14.0',
  });

  const out = JSON.stringify(next, null, 2) + '\n';
  const before = fs.existsSync(sourceFile) ? fs.readFileSync(sourceFile, 'utf8') : '';
  fs.writeFileSync(sourceFile, out);
  console.log(before === out ? 'unchanged' : 'updated');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
