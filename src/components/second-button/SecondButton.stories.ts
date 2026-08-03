import type { Meta, StoryObj } from '@storybook/vue3-vite'
import SecondButton from './SecondButton.vue'

const meta = {
  title: 'Components/SecondButton',
  component: SecondButton,
  tags: ['autodocs'],
  args: { label: 'Посмотреть ещё', size: 'md' },
  argTypes: {
    size: { control: 'select', options: ['xs', 'sm', 'md', 'lg', 'xl'] },
  },
} satisfies Meta<typeof SecondButton>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Block: Story = {
  args: { block: true },
}

export const Disabled: Story = {
  args: { disabled: true },
}
