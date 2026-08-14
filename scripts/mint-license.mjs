#!/usr/bin/env node
// Mint a Pro license key.
//
//   node scripts/mint-license.mjs <email> [plan] [--days N]
//
// Examples:
//   node scripts/mint-license.mjs buyer@example.com
//   node scripts/mint-license.mjs buyer@example.com pro --days 365
//
// Reads the private key from $DROSS_LICENSE_PRIVATE_KEY (PEM contents) or the
// license-private.pem file. Prints the license key to stdout — hand it to the
// buyer (they run `dross license activate <key>` or set DROSS_LICENSE_KEY).
//
// Wire this to your payment webhook (Gumroad/Lemon Squeezy/Stripe) to automate.
import { readFileSync } from 'node:fs'
import { signLicense } from '../dist/license.js'

const args = process.argv.slice(2)
const email = args.find((a) => !a.startsWith('--') && a.includes('@'))
if (!email) {
  console.error('Usage: node scripts/mint-license.mjs <email> [plan] [--days N]')
  process.exit(1)
}
const positionals = args.filter((a) => !a.startsWith('--') && a !== email)
const plan = positionals[0] ?? 'pro'
const daysIdx = args.indexOf('--days')
const days = daysIdx >= 0 ? Number(args[daysIdx + 1]) : undefined

const privateKeyPem =
  process.env.DROSS_LICENSE_PRIVATE_KEY ??
  (() => {
    try {
      return readFileSync('license-private.pem', 'utf8')
    } catch {
      console.error('No private key. Set $DROSS_LICENSE_PRIVATE_KEY or create license-private.pem (scripts/license-keypair.mjs).')
      process.exit(1)
    }
  })()

const iat = Date.now()
const payload = { email, plan, iat }
if (Number.isFinite(days)) payload.exp = iat + days * 24 * 60 * 60 * 1000

console.log(signLicense(payload, privateKeyPem))
