<script setup lang="ts">
import { ref } from 'vue'
import DisclaimerDialog from './components/DisclaimerDialog.vue'
import { shouldShowConsentGate, setConsented } from './utils/disclaimer'

const showConsent = ref(shouldShowConsentGate())

function onAccept() {
  setConsented()
  showConsent.value = false
}
</script>

<template>
  <router-view v-slot="{ Component, route }">
    <keep-alive :max="10">
      <component :is="Component" :key="route.fullPath" />
    </keep-alive>
  </router-view>
  <DisclaimerDialog v-model:show="showConsent" gate @accept="onAccept" />
</template>

<style scoped>
</style>
