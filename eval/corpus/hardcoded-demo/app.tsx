import { getIdentity } from './data.js'

export default function App() {
  const id = getIdentity()
  return <input placeholder="you@example.com" defaultValue={id.email} />
}
