const express = require('express')
const { requireAuth } = require('./auth')

const app = express()
app.use(express.json())

app.post('/auth/login', (req, res) => res.json({ ok: true }))
app.post('/webhooks/stripe', (req, res) => res.end())
app.post('/invites/:token/accept', (req, res) => res.json({ ok: true }))

app.get('/projects', requireAuth, (req, res) => res.json([]))
app.post('/projects', requireAuth, (req, res) => res.status(201).end())
app.patch('/projects/:id', requireAuth, (req, res) => res.end())

// Positive: every other write requires auth, this one forgot it.
app.delete('/projects/:id', (req, res) => res.status(204).end())

app.get('/health', (req, res) => res.end())
app.listen(3000)
