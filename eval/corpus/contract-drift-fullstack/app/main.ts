import { loadHealth, runScan } from './client.js'

await loadHealth()
await runScan({})
