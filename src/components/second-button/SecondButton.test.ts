import { fireEvent, render } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'
import SecondButton from './SecondButton.vue'

describe('SecondButton', () => {
  it('forwards class and data attributes to the root element', () => {
    const { getByRole } = render(SecondButton, {
      attrs: { class: 'catalog-secondary', 'data-test': 'catalog-secondary' },
      slots: { default: 'Show more' },
    })

    const button = getByRole('button', { name: 'Show more' })
    expect(button).toHaveClass('catalog-secondary')
    expect(button).toHaveAttribute('data-test', 'catalog-secondary')
  })

  it('replaces Nuxt UI utility classes with the CSS Module root', () => {
    const { getByRole } = render(SecondButton, { slots: { default: 'Show more' } })
    const className = getByRole('button', { name: 'Show more' }).className

    expect(className).not.toContain('bg-primary')
    expect(className).not.toContain('font-medium')
    expect(className).not.toContain('rounded-md')
  })

  it('emits click through Nuxt UI', async () => {
    const { emitted, getByRole } = render(SecondButton, { slots: { default: 'Show more' } })
    await fireEvent.click(getByRole('button', { name: 'Show more' }))
    expect(emitted().click).toHaveLength(1)
  })
})
