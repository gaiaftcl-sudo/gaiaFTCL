/** @type {import('tailwindcss').Config} */
export default {
	content: [
		"./index.html",
		"./src/**/*.{js,ts,jsx,tsx}",
	],
	theme: {
		extend: {
			colors: {
				'aviation-bg': '#0b0f19',
				'aviation-panel': '#111827',
				'aviation-border': '#1f2937',
				'radar-green': '#00ff00',
				'radar-amber': '#ffaa00',
				'radar-red': '#ff3333',
				'radar-cyan': '#00ffff',
			},
			fontFamily: {
				mono: ['Fira Code', 'monospace'],
				sans: ['Inter', 'system-ui', 'sans-serif'],
			},
			animation: {
				'radar-sweep': 'radar-sweep 4s linear infinite',
				'glow': 'glow 2s ease-in-out infinite',
			},
			keyframes: {
				'radar-sweep': {
					'0%': { transform: 'rotate(0deg)' },
					'100%': { transform: 'rotate(360deg)' },
				},
				'glow': {
					'0%, 100%': { boxShadow: '0 0 5px currentColor' },
					'50%': { boxShadow: '0 0 20px currentColor, 0 0 30px currentColor' },
				},
			},
		},
	},
	plugins: [],
}

