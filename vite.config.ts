import { resolve } from 'node:path'
import ui from '@nuxt/ui/vite'
import vue from '@vitejs/plugin-vue'
import type { Plugin } from 'vite'
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

const rootDir = import.meta.dirname
const buttonDistDir = resolve(rootDir, 'build/dist/components/button')

function normalizeButtonDeclarationPath(filePath: string) {
  const normalizedPath = filePath.replaceAll('\\', '/')
  const marker = '/components/button/src/components/button/'
  const markerIndex = normalizedPath.indexOf(marker)

  if (markerIndex === -1) {
    return filePath
  }

  return resolve(buttonDistDir, normalizedPath.slice(markerIndex + marker.length))
}

function injectButtonCss(): Plugin {
  return {
    name: 'dilexy:inject-button-css',
    enforce: 'post',
    generateBundle(_options, bundle) {
      const entry = bundle['components/button/index.js']

      if (entry?.type === 'chunk') {
        entry.code = `import '../../assets/ui.css';\n${entry.code}`
      }
    },
  }
}

export default defineConfig({
  cacheDir: 'build/cache/vite',
  plugins: [
    vue(),
    ui({ autoImport: false, components: false, colorMode: false, dts: false, router: false }),
    injectButtonCss(),
    dts({
      entryRoot: 'src',
      include: ['src/components/**/*.ts', 'src/components/**/*.vue'],
      exclude: ['src/**/*.stories.ts', 'src/**/*.test.ts'],
      outDir: 'build/dist',
      tsconfigPath: 'tsconfig.app.json',
      beforeWriteFile: (filePath, content) => ({
        filePath: normalizeButtonDeclarationPath(filePath),
        content,
      }),
    }),
  ],
  resolve: { alias: { '@': resolve(rootDir, 'src') } },
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
      entry: { 'components/button/index': resolve(rootDir, 'src/components/button/index.ts') },
      formats: ['es'],
    },
    rollupOptions: {
      external: ['vue', '@nuxt/ui', /^@nuxt\/ui\//],
      output: {
        assetFileNames: (assetInfo) =>
          assetInfo.name === 'style.css' ? 'components/button/style.css' : 'assets/[name][extname]',
        entryFileNames: '[name].js',
      },
    },
  },
})
