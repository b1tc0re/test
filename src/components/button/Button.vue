<script setup lang="ts">
import UButton from '@nuxt/ui/components/Button.vue'
import { useAttrs } from 'vue'
import type { ButtonProps } from './button.types'
import styles from './Button.module.scss'

defineOptions({ inheritAttrs: false })

const props = withDefaults(defineProps<ButtonProps>(), {
  size: 'md',
  type: 'button',
})
const attrs = useAttrs()

function rootClasses() {
  return [
    styles.root,
    styles[`size-${props.size}`],
    props.block && styles.block,
    props.square && styles.square,
  ]
}

const internalUi = {
  base: rootClasses,
  label: () => styles.label,
  leadingIcon: () => styles['leading-icon'],
  trailingIcon: () => styles['trailing-icon'],
}

function forwardedProps() {
  const { ui: _ui, ...forwardedAttrs } = attrs

  return {
    ...props,
    ...forwardedAttrs,
  }
}
</script>

<template>
  <UButton v-bind="forwardedProps()" :ui="internalUi">
    <template v-if="$slots.leading" #leading>
      <slot name="leading" />
    </template>

    <template v-if="$slots.default" #default>
      <slot />
    </template>

    <template v-if="$slots.trailing" #trailing>
      <slot name="trailing" />
    </template>
  </UButton>
</template>
