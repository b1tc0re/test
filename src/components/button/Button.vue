<script setup lang="ts">
import UButton from '@nuxt/ui/components/Button.vue'
import { useAttrs } from 'vue'
import type { ButtonProps } from './button.types'
import styles from './Button.module.scss'

defineOptions({ inheritAttrs: false })

const props = defineProps<ButtonProps>()
const attrs = useAttrs()

const internalUi = {
  base: () => styles.root,
  label: () => styles.label,
  leadingIcon: () => styles.leadingIcon,
  trailingIcon: () => styles.trailingIcon,
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
