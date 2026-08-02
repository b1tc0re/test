import type { StorybookConfig } from '@storybook/vue3-vite'

const config: StorybookConfig = {
  framework: { name: '@storybook/vue3-vite', options: {} },
  stories: ['../docs/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],
  addons: ['@storybook/addon-docs', '@storybook/addon-a11y', '@storybook/addon-themes'],
  core: { disableTelemetry: true },
  viteFinal(config) {
    config.cacheDir = 'build/cache/storybook'
    config.plugins = config.plugins?.filter((plugin) => plugin && plugin.name !== 'vite:dts')
    return config
  },
}

export default config
