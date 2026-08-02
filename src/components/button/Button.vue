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
    <template v-for="(_, slotName) in $slots" #[slotName]="slotProps">
      <slot :name="slotName" v-bind="slotProps ?? {}" />
    </template>
  </UButton>
</template>
