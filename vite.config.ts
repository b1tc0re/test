import { resolve } from 'node:path'
import ui from '@nuxt/ui/vite'
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

export default defineConfig({
  cacheDir: 'build/cache/vite',
  plugins: [
    vue(),
    ui({ autoImport: false, components: false, colorMode: false, dts: false, router: false }),
    dts({
      entryRoot: 'src',
      include: ['src/components/**/*.ts', 'src/components/**/*.vue'],
      exclude: ['src/**/*.stories.ts', 'src/**/*.test.ts'],
      outDir: 'build/dist',
      tsconfigPath: 'tsconfig.app.json',
    }),
  ],
  resolve: { alias: { '@': resolve(import.meta.dirname, 'src') } },
  css: {
    postcss: './postcss.config.mjs',
    modules: { generateScopedName: 'dui_[name]_[local]_[hash:base64:6]' },
    preprocessorOptions: { scss: { api: 'modern-compiler' } },
  },
  build: {
    target: 'es2022',
    outDir: 'build/dist',
    emptyOutDir: true,
    lib: {
      entry: { 'components/button/index': resolve(import.meta.dirname, 'src/components/button/index.ts') },
      formats: ['es'],
    },
    rollupOptions: {
      external: ['vue', '@nuxt/ui', /^@nuxt\/ui\//],
      output: {
        assetFileNames: (assetInfo) => assetInfo.name === 'style.css' ? 'components/button/style.css' : 'assets/[name][extname]',
        entryFileNames: '[name].js',
      },
    },
  },
})
