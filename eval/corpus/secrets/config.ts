// Negative controls only: none of these may be flagged. Positive cases live in
// test/secrets.test.ts, built at runtime — a real-format key literal here gets
// the push rejected by GitHub's secret scanning (this repo is public).
const anthropicKey = process.env.ANTHROPIC_API_KEY
const docsPlaceholder = 'your_api_key_here'
const publicCert = '-----BEGIN CERTIFICATE-----'

console.log([anthropicKey, docsPlaceholder, publicCert].length)
