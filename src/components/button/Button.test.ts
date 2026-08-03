import { cleanup, fireEvent, render } from '@testing-library/vue'
import { afterEach, describe, expect, it } from 'vitest'
import Button from './Button.vue'

afterEach(cleanup)

describe('Button', () => {
  it('forwards class and data attributes to the root element', () => {
    const { getByRole } = render(Button, {
      attrs: { class: 'card-button', 'data-test': 'catalog-action' },
      slots: { default: 'Open catalog' },
    })

    const button = getByRole('button', { name: 'Open catalog' })
    expect(button).toHaveClass('card-button')
    expect(button).toHaveAttribute('data-test', 'catalog-action')
  })

  it('replaces Nuxt UI utility classes with the CSS Module root', () => {
    const { getByRole } = render(Button, { slots: { default: 'Continue' } })
    const className = getByRole('button', { name: 'Continue' }).className

    expect(className).not.toContain('bg-primary')
    expect(className).not.toContain('font-medium')
    expect(className).not.toContain('rounded-md')
  })

  it('emits click through Nuxt UI', async () => {
    const { emitted, getByRole } = render(Button, { slots: { default: 'Continue' } })
    await fireEvent.click(getByRole('button', { name: 'Continue' }))
    expect(emitted().click).toHaveLength(1)
  })
})
