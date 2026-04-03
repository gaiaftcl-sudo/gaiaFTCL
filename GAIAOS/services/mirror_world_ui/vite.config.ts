import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
	plugins: [react()],
	server: {
		port: 3000,
		host: true,
		proxy: {
			// Proxy API calls to local backend for development
			// For production, change target to 'https://gaiaos.cloud'
			'/api': {
				target: 'http://localhost:8700',
				changeOrigin: true,
			},
			'/orchestrator': {
				target: 'http://localhost:8815',
				changeOrigin: true,
			},
			'/atc/api': {
				target: 'http://localhost:8820',
				changeOrigin: true,
				rewrite: (path) => path.replace(/^\/atc\/api/, '/api'),
			},
		},
	},
	build: {
		outDir: 'dist',
		sourcemap: true,
	},
})

