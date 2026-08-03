import { existsSync, readdirSync } from 'node:fs'
import { posix, resolve } from 'node:path'
import ui from '@nuxt/ui/vite'
import vue from '@vitejs/plugin-vue'
import type { OutputChunk } from 'rollup'
import type { Plugin } from 'vite'
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

const rootDir = import.meta.dirname
const componentsDir = resolve(rootDir, 'src/components')

function componentEntries() {
  return Object.fromEntries(
    readdirSync(componentsDir, { withFileTypes: true }).flatMap((entry) => {
      if (!entry.isDirectory()) {
        return []
      }

      const componentEntry = resolve(componentsDir, entry.name, 'index.ts')

      if (!existsSync(componentEntry)) {
        return []
      }

      return [[`components/${entry.name}/index`, componentEntry]]
    }),
  )
}

type ChunkWithViteMetadata = OutputChunk & {
  viteMetadata?: {
    importedCss: Set<string>
  }
}

function injectEntryCss(): Plugin {
  return {
    name: 'dilexy:inject-entry-css',
    enforce: 'post',
    renderChunk(code, chunk) {
      const importedCss = [...((chunk as ChunkWithViteMetadata).viteMetadata?.importedCss ?? [])]

      if (importedCss.length === 0) {
        return null
      }

      const imports = importedCss.map((cssFile) => {
        let importPath = posix.relative(posix.dirname(chunk.fileName), cssFile)

        if (!importPath.startsWith('.')) {
          importPath = `./${importPath}`
        }

        return `import ${JSON.stringify(importPath)};`
      })

      return {
        code: `${imports.join('\n')}\n${code}`,
        map: null,
      }
    },
  }
}

export default defineConfig({
  cacheDir: 'build/cache/vite',
  plugins: [
    vue(),
    ui({ autoImport: false, components: false, colorMode: false, dts: false, router: false }),
    injectEntryCss(),
    dts({
      entryRoot: componentsDir,
      include: ['src/components/**/*.ts', 'src/components/**/*.vue'],
      exclude: ['src/**/*.stories.ts', 'src/**/*.test.ts'],
      outDir: resolve(rootDir, 'build/dist/components'),
      tsconfigPath: resolve(rootDir, 'tsconfig.app.json'),
    }),
  ],
  resolve: {
    alias: {
      '@': resolve(rootDir, 'src'),
    },
  },
  css: {
    postcss: './postcss.config.mjs',
    modules: {
      generateScopedName: 'dui_[name]_[local]_[hash:base64:6]',
    },
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  build: {
    target: 'es2022',
    outDir: 'build/dist',
    emptyOutDir: true,
    cssCodeSplit: true,
    lib: {
      entry: componentEntries(),
      formats: ['es'],
    },
    rollupOptions: {
      external: ['vue', '@nuxt/ui', /^@nuxt\/ui\//],
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: 'chunks/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
        hoistTransitiveImports: false,
      },
    },
  },
})
