import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { brand } from './src/config/brand';

export default defineConfig(({mode}) => {\n  const env=loadEnv(mode,process.cwd(),'VITE_');\n  const isV21=env.VITE_ADMIN_VERSION==='v21';\n  return {
  plugins: [react(), {
    name: 'market-brand-title',
    transformIndexHtml: (html) => html.replace(/<title>.*?<\/title>/, `<title>${isV21?'BuildTo Administration · Staging':brand.name+' Operations'}</title>`),
  }],
  build: {
    // Never inline fonts/assets as data: URIs - the production CSP only allows font-src 'self'.
    assetsInlineLimit: 0,
  },
  server: {
    port: 3000
  }
};
});
