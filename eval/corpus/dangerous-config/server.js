const express = require('express')
const cors = require('cors')
const jwt = require('jsonwebtoken')

const app = express()
const SECRET = process.env.JWT_SECRET
if (!SECRET) throw new Error('Missing JWT_SECRET')

// Positives
app.use(cors({ origin: true, credentials: true }))
const legacy = (token) => jwt.verify(token, process.env.LEGACY_SECRET || 'legacy-dev-secret')

// Negative controls: env secret with startup check, fixed algorithm, gated TLS opt-out
const issue = (user) => jwt.sign({ sub: user.id }, SECRET, { expiresIn: '1h' })
const check = (token) => jwt.verify(token, SECRET, { algorithms: ['HS256'] })
const agentOpts = (insecure) => (insecure ? { rejectUnauthorized: false } : {})

app.get('/health', (req, res) => res.json({ ok: !!(legacy && issue && check && agentOpts) }))
app.listen(3000)
