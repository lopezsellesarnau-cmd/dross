import { test } from 'node:test'
import assert from 'node:assert/strict'
import { generateKeyPairSync } from 'node:crypto'
import { signLicense, verifyLicense, resolveLicenseKey } from '../src/license.js'

function ephemeralKeys() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519')
  return {
    pub: publicKey.export({ type: 'spki', format: 'pem' }).toString(),
    priv: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  }
}

test('a signed license verifies and round-trips its payload', () => {
  const { pub, priv } = ephemeralKeys()
  const key = signLicense({ email: 'buyer@example.com', plan: 'pro', iat: Date.now() }, priv)
  const status = verifyLicense(key, pub)
  assert.equal(status.valid, true)
  assert.equal(status.plan, 'pro')
  assert.equal(status.email, 'buyer@example.com')
})

test('an expired license is rejected', () => {
  const { pub, priv } = ephemeralKeys()
  const past = Date.now() - 1000
  const key = signLicense({ email: 'x@y.com', plan: 'pro', iat: past - 1000, exp: past }, priv)
  const status = verifyLicense(key, pub)
  assert.equal(status.valid, false)
  assert.match(status.reason ?? '', /expired/i)
})

test('a perpetual license (no exp) stays valid far in the future', () => {
  const { pub, priv } = ephemeralKeys()
  const key = signLicense({ email: 'x@y.com', plan: 'pro', iat: Date.now() }, priv)
  const tenYears = Date.now() + 10 * 365 * 24 * 60 * 60 * 1000
  assert.equal(verifyLicense(key, pub, tenYears).valid, true)
})

test('a tampered payload fails the signature check', () => {
  const { pub, priv } = ephemeralKeys()
  const key = signLicense({ email: 'free@rider.com', plan: 'free', iat: Date.now() }, priv)
  const [prefix, , sig] = key.split('.')
  const forgedPayload = Buffer.from(JSON.stringify({ email: 'free@rider.com', plan: 'pro', iat: Date.now() })).toString('base64url')
  const forged = `${prefix}.${forgedPayload}.${sig}`
  const status = verifyLicense(forged, pub)
  assert.equal(status.valid, false)
  assert.match(status.reason ?? '', /signature/i)
})

test('a key signed by a different private key is rejected by our public key', () => {
  const a = ephemeralKeys()
  const b = ephemeralKeys()
  const key = signLicense({ email: 'x@y.com', plan: 'pro', iat: Date.now() }, a.priv)
  assert.equal(verifyLicense(key, b.pub).valid, false)
})

test('malformed and empty keys are rejected without throwing', () => {
  const { pub } = ephemeralKeys()
  assert.equal(verifyLicense(undefined, pub).valid, false)
  assert.equal(verifyLicense('', pub).valid, false)
  assert.equal(verifyLicense('not-a-key', pub).valid, false)
  assert.equal(verifyLicense('wrong-prefix.aaa.bbb', pub).valid, false)
})

test('resolveLicenseKey prefers the DROSS_LICENSE_KEY env var', () => {
  const prev = process.env.DROSS_LICENSE_KEY
  process.env.DROSS_LICENSE_KEY = '  dross-v1.abc.def  '
  try {
    const r = resolveLicenseKey()
    assert.equal(r.source, 'env')
    assert.equal(r.key, 'dross-v1.abc.def')
  } finally {
    if (prev === undefined) delete process.env.DROSS_LICENSE_KEY
    else process.env.DROSS_LICENSE_KEY = prev
  }
})
