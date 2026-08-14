export async function loadHealth() {
  const res = await fetch('/api/health')
  return res.json()
}

export async function runScan(payload: unknown) {
  const res = await fetch('/api/scan', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
  return res.json()
}
