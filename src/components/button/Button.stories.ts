import type { Meta, StoryObj } from '@storybook/vue3-vite'
import Button from './Button.vue'

const meta = {
  title: 'Components/Button',
  component: Button,
  tags: ['autodocs'],
  args: { label: 'Continue', color: 'primary', variant: 'solid' },
  argTypes: {
    color: { control: 'select', options: ['primary', 'secondary', 'success', 'info', 'warning', 'error', 'neutral'] },
    variant: { control: 'select', options: ['solid', 'outline', 'soft', 'subtle', 'ghost', 'link'] },
  },
} satisfies Meta<typeof Button>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
export const AdditionalRootClass: Story = {
  args: { class: 'card_button', 'data-test': 'storybook-button' },
}
