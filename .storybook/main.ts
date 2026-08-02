import ui from '@nuxt/ui/vite'
import type { StorybookConfig } from '@storybook/vue3-vite'

const config: StorybookConfig = {
  framework: { name: '@storybook/vue3-vite', options: {} },
  stories: ['../docs/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],
  addons: ['@storybook/addon-docs', '@storybook/addon-a11y', '@storybook/addon-themes'],
  core: { disableTelemetry: true },
  viteFinal(config) {
    config.cacheDir = 'build/cache/storybook'
    config.plugins ??= []
    config.plugins.push(...ui({ autoImport: false, components: false, colorMode: false, dts: false, router: false }))
    return config
  },
}

export default config
