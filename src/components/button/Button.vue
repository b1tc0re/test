<script setup lang="ts">
import UButton from '@nuxt/ui/components/Button.vue'
import { useAttrs } from 'vue'
import type { ButtonProps } from './button.types'
import styles from './Button.module.scss'

defineOptions({ inheritAttrs: false })

const props = defineProps<ButtonProps>()
const attrs = useAttrs()
</script>

<template>
  <UButton v-bind="props" v-bind="attrs" :class="[styles.root, attrs.class]">
    <template v-for="(_, slotName) in $slots" #[slotName]="slotProps">
      <slot :name="slotName" v-bind="slotProps ?? {}" />
    </template>
  </UButton>
</template>
