import express from 'express'

const app = express()

app.get('/api/health', (req, res) => res.json({ ok: true }))

// Renamed from /api/scan — the client was never updated. This is the drift.
app.post('/api/scanReport', (req, res) => res.json({ report: [] }))

app.listen(3000)
