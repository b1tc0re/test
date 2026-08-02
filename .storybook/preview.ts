import ui from '@nuxt/ui/vue-plugin'
import { withThemeByClassName } from '@storybook/addon-themes'
import type { Preview } from '@storybook/vue3-vite'
import { setup } from '@storybook/vue3-vite'
import '../src/styles/main.css'

setup((app) => { app.use(ui) })

const preview: Preview = {
  decorators: [
    withThemeByClassName({ themes: { light: '', dark: 'dark' }, defaultTheme: 'light' }),
  ],
  parameters: {
    controls: { expanded: true },
    docs: { codePanel: true },
    options: { storySort: { order: ['Introduction', 'Components'] } },
  },
}

export default preview
