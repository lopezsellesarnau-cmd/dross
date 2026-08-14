const GRAPH_BASE = 'https://graph.microsoft.com/v1.0'

export async function getServicePrincipalName(token, id) {
  const res = await fetch(`${GRAPH_BASE}/servicePrincipals/${id}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  return res.ok ? res.json() : null
}
