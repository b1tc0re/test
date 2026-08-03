import type { StorybookConfig } from '@storybook/vue3-vite'
import type { PluginOption } from 'vite'

function removeDeclarationPlugin(plugin: PluginOption): PluginOption {
  if (Array.isArray(plugin)) {
    return plugin.map(removeDeclarationPlugin)
  }

  if (plugin && typeof plugin === 'object' && 'name' in plugin && plugin.name === 'vite:dts') {
    return false
  }

  return plugin
}

const config: StorybookConfig = {
  framework: { name: '@storybook/vue3-vite', options: {} },
  stories: ['../docs/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],
  addons: ['@storybook/addon-docs', '@storybook/addon-a11y', '@storybook/addon-themes'],
  core: { disableTelemetry: true },
  viteFinal(config) {
    config.cacheDir = 'build/cache/storybook'
    config.plugins = config.plugins?.map(removeDeclarationPlugin)
    return config
  },
}

export default config
