import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // local dev: forward /api to the backend
  server: { proxy: { '/api': 'http://localhost:8000' } },
})
