import ui from '@nuxt/ui/vite'
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  cacheDir: 'build/cache/vitest',
  plugins: [
    vue(),
    ui({ autoImport: false, components: false, colorMode: false, dts: false, router: false }),
  ],
  test: {
    environment: 'happy-dom',
    setupFiles: ['./src/test-setup.ts'],
    coverage: {
      provider: 'v8',
      reportsDirectory: 'build/coverage',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/components/**/*.vue'],
      exclude: ['src/**/*.stories.ts', 'src/**/*.test.ts'],
    },
  },
})
