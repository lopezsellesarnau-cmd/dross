import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fixDeleteDead } from '../src/fix/deleteDead.js'

function withTempFile(contents: string, run: (root: string, rel: string) => void) {
  const root = mkdtempSync(join(tmpdir(), 'dross-deletedead-'))
  const rel = 'work.ts'
  writeFileSync(join(root, rel), contents, 'utf8')
  try {
    run(root, rel)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

test('deletes a whole multi-line function whose params have their own balanced braces', () => {
  // Real case: a destructured, typed parameter (`{ step }: { step: 1|2|3 }`)
  // nets its own braces back to zero, and the params' `)` closes right
  // after — before the function body even opens. The old three-counter
  // walk treated that coincidence as "declaration complete" and deleted
  // only the signature line, leaving the body orphaned in the file.
  const src = [
    "import { View } from 'react-native';",
    '',
    "/** doc comment */",
    'export function SetupProgress({ step }: { step: 1 | 2 | 3 }) {',
    '  return (',
    '    <View />',
    '  );',
    '}',
    '',
    'const tail = 1;',
    '',
  ].join('\n')

  withTempFile(src, (root, rel) => {
    const result = fixDeleteDead(root, rel, 4)
    assert.equal(result.ok, true)
    const after = readFileSync(join(root, rel), 'utf8')
    assert.ok(!after.includes('SetupProgress'), 'declaration and its name should be gone')
    assert.ok(!after.includes('return ('), 'the body must be deleted too, not left orphaned')
    assert.ok(after.includes('const tail = 1;'), 'unrelated code after it must survive untouched')
  })
})

test('deletes an arrow function with no body braces, ending at the semicolon', () => {
  const src = 'export const add = (a: number, b: number) => a + b;\n\nconst tail = 1;\n'
  withTempFile(src, (root, rel) => {
    const result = fixDeleteDead(root, rel, 1)
    assert.equal(result.ok, true)
    const after = readFileSync(join(root, rel), 'utf8')
    assert.ok(!after.includes('add ='))
    assert.ok(after.includes('const tail = 1;'))
  })
})

test('deletes a multi-line array literal, not just its opening line', () => {
  const src = 'export const list = [\n  1,\n  2,\n];\n\nconst tail = 1;\n'
  withTempFile(src, (root, rel) => {
    const result = fixDeleteDead(root, rel, 1)
    assert.equal(result.ok, true)
    const after = readFileSync(join(root, rel), 'utf8')
    assert.ok(!after.includes('list ='))
    assert.ok(!after.includes('  2,'), 'the whole array body must go, not just the header')
    assert.ok(after.includes('const tail = 1;'))
  })
})

test('a stale line pointing at a leading comment still finds the real declaration nearby', () => {
  const src = [
    "import { View } from 'react-native';",
    '',
    '/** doc comment added after this finding was reported */',
    'export function Foo() {',
    '  return null;',
    '}',
    '',
  ].join('\n')
  withTempFile(src, (root, rel) => {
    // Line 3 (the comment) is what a stale report would say; line 4 is the
    // real declaration now that a comment was added above it.
    const result = fixDeleteDead(root, rel, 3)
    assert.equal(result.ok, true)
    const after = readFileSync(join(root, rel), 'utf8')
    assert.ok(!after.includes('function Foo'))
  })
})

test('a line with no declaration anywhere nearby fails clearly instead of guessing', () => {
  const src = [
    'export function Foo(x) {',
    '  x += 1;',
    '  x += 1;',
    '  x += 1;',
    '  x += 1;',
    '  x += 1;',
    '  return x;',
    '}',
    '',
  ].join('\n')
  withTempFile(src, (root, rel) => {
    // Line 5 is 4 lines away from Foo's own declaration at line 1 — outside
    // the ±3 search window, and none of lines 2–7 are declaration-shaped.
    const result = fixDeleteDead(root, rel, 5)
    assert.equal(result.ok, false)
    assert.match(result.message, /deletable declaration/)
  })
})
