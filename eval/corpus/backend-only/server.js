import express from 'express'
import { getServicePrincipalName } from './graph.js'

const app = express()

app.get('/users', (req, res) => {
  res.json({ ok: true })
})

app.post('/login', async (req, res) => {
  const name = await getServicePrincipalName(req.token, req.body.id)
  res.json({ name })
})

app.listen(4000)
