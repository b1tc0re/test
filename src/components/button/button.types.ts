import type { ButtonProps as NuxtButtonProps } from '@nuxt/ui/components/Button.vue'

export interface ButtonProps {
  label?: string
  color?: NuxtButtonProps['color']
  variant?: NuxtButtonProps['variant']
  size?: NuxtButtonProps['size']
  type?: 'button' | 'submit' | 'reset'
  disabled?: boolean
  loading?: boolean
  block?: boolean
  square?: boolean
  icon?: string
  leadingIcon?: string
  trailingIcon?: string
}
