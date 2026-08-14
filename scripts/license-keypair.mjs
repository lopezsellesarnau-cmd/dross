#!/usr/bin/env node
// Generate an Ed25519 keypair for license signing.
//
//   node scripts/license-keypair.mjs
//
// Writes the PRIVATE key to license-private.pem (gitignored — keep it secret,
// back it up outside the repo) and prints the PUBLIC key. Paste the public key
// into EMBEDDED_PUBLIC_KEY in src/license.ts. Run this once; rotating the key
// invalidates every previously minted license.
import { generateKeyPairSync } from 'node:crypto'
import { writeFileSync, existsSync } from 'node:fs'

const OUT = 'license-private.pem'
if (existsSync(OUT) && !process.argv.includes('--force')) {
  console.error(`${OUT} already exists. Refusing to overwrite (would invalidate all issued licenses). Pass --force to regenerate.`)
  process.exit(1)
}

const { publicKey, privateKey } = generateKeyPairSync('ed25519')
const priv = privateKey.export({ type: 'pkcs8', format: 'pem' })
const pub = publicKey.export({ type: 'spki', format: 'pem' })

writeFileSync(OUT, priv, { mode: 0o600 })
console.log(`Wrote private key → ${OUT} (gitignored, keep secret)\n`)
console.log('Paste this into EMBEDDED_PUBLIC_KEY in src/license.ts:\n')
console.log(pub)
