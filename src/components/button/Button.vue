<script setup lang="ts">
import UButton from '@nuxt/ui/components/Button.vue'
import { useAttrs } from 'vue'
import type { ButtonProps } from './button.types'
import styles from './Button.module.scss'

defineOptions({ inheritAttrs: false })

const props = defineProps<ButtonProps>()
const attrs = useAttrs()

function forwardedProps() {
  return {
    ...props,
    ...attrs,
    class: [styles.root, attrs.class],
  }
}
</script>

<template>
  <UButton v-bind="forwardedProps()">
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
