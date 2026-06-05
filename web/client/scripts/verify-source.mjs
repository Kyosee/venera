import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import ts from 'typescript'

const sourcePath = new URL('../src/utils/source.ts', import.meta.url)
const source = await readFile(sourcePath, 'utf8')
const { outputText } = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.ES2022,
    target: ts.ScriptTarget.ES2022,
  },
})
const moduleUrl = `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
const { normalizeComicSources, resolveSourceKey } = await import(moduleUrl)

const deduped = normalizeComicSources([
  { name: 'comic_source/source_a.js', key: 'source_a (1)' },
  { name: 'comic_source/source_a.js', key: 'source_a (2)' },
  { name: 'comic_source/source_b.js', key: 'source_b' },
  { name: 'comic_source/source_a.data', key: 'source_a.data' },
])

assert.equal(deduped.length, 2)
assert.deepEqual(deduped.map(item => item.key).sort(), ['source_a (1)', 'source_b'])
assert.equal(
  resolveSourceKey(
    { type: 557997769 },
    [{ key: 'source_a (1)', canonicalKey: 'source_a', type: 557997769 }],
  ),
  'source_a (1)',
)
assert.equal(resolveSourceKey({ sourceKey: 'source_a' }, [{ key: 'source_a (1)', canonicalKey: 'source_a' }]), 'source_a (1)')

console.log('source utils verification passed')
