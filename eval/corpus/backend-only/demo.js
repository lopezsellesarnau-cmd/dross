const BASE = process.env.DEMO_URL || 'http://localhost:4000'

async function main() {
  await fetch(`${BASE}/login`, { method: 'POST' })
  await fetch(`${BASE}/users`)
}

main()
