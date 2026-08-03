export type ButtonSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl'

export interface ButtonProps {
  label?: string
  size?: ButtonSize
  type?: 'button' | 'submit' | 'reset'
  disabled?: boolean
  loading?: boolean
  block?: boolean
  square?: boolean
  icon?: string
  leadingIcon?: string
  trailingIcon?: string
}
