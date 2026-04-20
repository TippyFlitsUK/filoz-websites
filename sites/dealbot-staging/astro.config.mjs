import { defineConfig } from 'astro/config'
import react from '@astrojs/react'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'

const isProd = process.env.PROD_BUILD === '1'

export default defineConfig({
  site: isProd ? 'https://staging.dealbot.filoz.org' : 'https://dealbot-staging.filecoincloud.io',
  trailingSlash: 'ignore',
  build: { format: 'directory' },
  integrations: [react(), sitemap()],
  vite: {
    plugins: [tailwindcss()],
    resolve: {
      alias: {
        '@': new URL('./src', import.meta.url).pathname,
      },
    },
    server: {
      proxy: {
        '/api': {
          target: 'https://staging.dealbot.filoz.org',
          changeOrigin: true,
          secure: true,
        },
      },
    },
  },
})
