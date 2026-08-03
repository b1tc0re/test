export type SecondButtonSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl'

export interface SecondButtonProps {
  label?: string
  size?: SecondButtonSize
  type?: 'button' | 'submit' | 'reset'
  disabled?: boolean
  loading?: boolean
  block?: boolean
  square?: boolean
  icon?: string
  leadingIcon?: string
  trailingIcon?: string
}
