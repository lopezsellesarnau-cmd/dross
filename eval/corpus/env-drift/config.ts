const apiUrl = process.env.API_URL
const port = process.env.PORT

export function getConfig() {
  return { apiUrl, port }
}
