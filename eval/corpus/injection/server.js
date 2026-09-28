const express = require('express')
const path = require('path')
const fs = require('fs')
const { exec, execFile } = require('child_process')

const app = express()
const FILES = path.join(__dirname, 'files')

// Positives
app.post('/convert', (req, res) => {
  exec('convert ' + req.body.file + ' out.png')
})
app.get('/user', async (req, res) => {
  const { id } = req.query
  res.json(await db.query(`SELECT * FROM users WHERE id = '${id}'`))
})
app.get('/download', (req, res) => {
  res.sendFile(path.join(FILES, req.query.name))
})

// Negative controls: parameterized, sanitized, no shell, guarded
app.get('/user-safe', async (req, res) => {
  res.json(await db.query('SELECT * FROM users WHERE id = $1', [req.query.id]))
})
app.post('/convert-safe', (req, res) => {
  execFile('convert', [req.body.file, 'out.png'])
})
app.get('/download-safe', (req, res) => {
  res.sendFile(path.join(FILES, path.basename(req.query.name)))
})
app.get('/page', (req, res) => {
  const n = Number(req.query.page)
  db.query(`SELECT * FROM posts LIMIT 10 OFFSET ${n * 10}`)
})
app.get('/read', (req, res) => {
  const p = path.resolve(FILES, req.query.p)
  if (!p.startsWith(FILES)) return res.status(400).end()
  fs.createReadStream(p).pipe(res)
})

app.listen(3000)
