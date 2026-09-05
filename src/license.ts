import { verify as edVerify, sign as edSign, createPublicKey, createPrivateKey } from 'node:crypto'
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

/**
 * Offline license verification. A license key is an Ed25519-signed payload:
 *
 *   dross-v1.<base64url(payloadJson)>.<base64url(signature)>
 *
 * The public key below is embedded in the shipped engine; keys are minted with
 * the matching private key (kept secret, out of the repo — see
 * scripts/mint-license.mjs). No network, no server: verification is a local
 * signature check, which is exactly what "nothing leaves this Mac" needs.
 *
 * A determined attacker can patch the binary — acceptable at this price/stage.
 * A server-side activation check can layer on later by making `licenseStatus`
 * async without changing any call site's contract shape.
 */

const KEY_PREFIX = 'dross-v1'

// Embedded Ed25519 public key (SPKI PEM). Not a secret — safe to ship.
export const EMBEDDED_PUBLIC_KEY = `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAq0NqIwjXzF7gSbwDJqoKfJiPTaR1EuleXhVMx6ZqS/w=
-----END PUBLIC KEY-----
`

export type LicensePayload = {
  /** Buyer email — for support/audit, not enforced. */
  email: string
  /** Tier. v1 only has "pro" (unlocks the LLM drift pass). */
  plan: string
  /** Issued-at, epoch ms. */
  iat: number
  /** Optional expiry, epoch ms. Absent = perpetual (one-time purchase). */
  exp?: number
}

export type LicenseStatus = {
  valid: boolean
  plan?: string
  email?: string
  expiresAt?: number
  /** Human reason when invalid — surfaced in CLI/app. */
  reason?: string
  /** Where the key came from: env var, license file, or none. */
  source?: 'env' | 'file' | 'none'
}

function b64urlDecode(s: string): Buffer {
  return Buffer.from(s, 'base64url')
}

function b64urlEncode(b: Buffer): string {
  return b.toString('base64url')
}

/**
 * Verify a license key string against a public key (defaults to the embedded
 * one; injectable so tests can use an ephemeral keypair). Pure — no I/O.
 */
export function verifyLicense(
  key: string | undefined | null,
  publicKeyPem: string = EMBEDDED_PUBLIC_KEY,
  now: number = Date.now(),
): LicenseStatus {
  if (!key || typeof key !== 'string') {
    return { valid: false, reason: 'No license key.' }
  }
  const parts = key.trim().split('.')
  if (parts.length !== 3 || parts[0] !== KEY_PREFIX) {
    return { valid: false, reason: 'Malformed license key.' }
  }
  const [, payloadB64, sigB64] = parts

  let payload: LicensePayload
  let payloadBytes: Buffer
  try {
    payloadBytes = b64urlDecode(payloadB64)
    payload = JSON.parse(payloadBytes.toString('utf8')) as LicensePayload
  } catch {
    return { valid: false, reason: 'Unreadable license payload.' }
  }

  let signatureOk = false
  try {
    const pub = createPublicKey(publicKeyPem)
    signatureOk = edVerify(null, payloadBytes, pub, b64urlDecode(sigB64))
  } catch {
    return { valid: false, reason: 'Signature check failed.' }
  }
  if (!signatureOk) {
    return { valid: false, reason: 'Invalid signature — key is forged or corrupted.' }
  }

  if (typeof payload.exp === 'number' && now > payload.exp) {
    return {
      valid: false,
      plan: payload.plan,
      email: payload.email,
      expiresAt: payload.exp,
      reason: 'License expired.',
    }
  }

  return {
    valid: true,
    plan: payload.plan,
    email: payload.email,
    expiresAt: payload.exp,
  }
}

/**
 * Mint a license key from a payload + private key PEM. Used by the mint script
 * and tests. Kept here so signing and verification share one wire format.
 */
export function signLicense(payload: LicensePayload, privateKeyPem: string): string {
  const payloadBytes = Buffer.from(JSON.stringify(payload), 'utf8')
  const priv = createPrivateKey(privateKeyPem)
  const sig = edSign(null, payloadBytes, priv)
  return `${KEY_PREFIX}.${b64urlEncode(payloadBytes)}.${b64urlEncode(sig)}`
}

/** Path of the on-disk license file (`~/.dross/license`). */
export function licenseFilePath(): string {
  return join(homedir(), '.dross', 'license')
}

/**
 * Resolve the raw license key from the environment first (CI-friendly:
 * `DROSS_LICENSE_KEY`), then the on-disk file the app writes.
 */
export function resolveLicenseKey(): { key?: string; source: 'env' | 'file' | 'none' } {
  const fromEnv = process.env.DROSS_LICENSE_KEY?.trim()
  if (fromEnv) return { key: fromEnv, source: 'env' }
  try {
    const fromFile = readFileSync(licenseFilePath(), 'utf8').trim()
    if (fromFile) return { key: fromFile, source: 'file' }
  } catch {
    // no file — fall through
  }
  return { source: 'none' }
}

/**
 * TEMPORARY (added 5 sept 2026): Lemon Squeezy hasn't approved the
 * subscription product yet, so nobody can actually buy a license —
 * dross-license-server can't mint one. Rather than gate a paid feature
 * nobody can currently pay for, Pro is open to everyone until that's
 * resolved. Single choke point (this function), so un-gating later is
 * deleting this block, not touching any call site.
 * TODO: remove once Lemon Squeezy approves the subscription product.
 */
const TEMPORARY_FREE_FOR_ALL = true

/** Full resolved + verified status for the current environment. */
export function licenseStatus(now: number = Date.now()): LicenseStatus {
  if (TEMPORARY_FREE_FOR_ALL) {
    return { valid: true, plan: 'pro', reason: 'Free during launch.', source: 'none' }
  }
  const { key, source } = resolveLicenseKey()
  if (!key) return { valid: false, reason: 'No license found.', source: 'none' }
  return { ...verifyLicense(key, EMBEDDED_PUBLIC_KEY, now), source }
}

/**
 * Verify and persist a key to `~/.dross/license`. Refuses to store an invalid
 * key so activation can never leave a broken license on disk.
 */
export function activateLicense(key: string): LicenseStatus {
  const status = verifyLicense(key)
  if (!status.valid) return status
  const path = licenseFilePath()
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, key.trim() + '\n', { mode: 0o600 })
  return { ...status, source: 'file' }
}

/** Remove the stored license file, if any. */
export function deactivateLicense(): void {
  rmSync(licenseFilePath(), { force: true })
}
