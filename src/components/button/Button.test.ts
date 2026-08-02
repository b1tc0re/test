import { fireEvent, render } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'
import Button from './Button.vue'

describe('Button', () => {
  it('forwards class and data attributes to the root element', () => {
    const { getByRole } = render(Button, {
      attrs: { class: 'card_button', 'data-test': 'catalog-action' },
      slots: { default: 'Open catalog' },
    })

    const button = getByRole('button', { name: 'Open catalog' })
    expect(button).toHaveClass('card_button')
    expect(button).toHaveAttribute('data-test', 'catalog-action')
  })

  it('emits click through Nuxt UI', async () => {
    const { emitted, getByRole } = render(Button, { slots: { default: 'Continue' } })
    await fireEvent.click(getByRole('button', { name: 'Continue' }))
    expect(emitted().click).toHaveLength(1)
  })
})
