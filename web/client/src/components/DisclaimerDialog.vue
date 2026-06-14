<script setup lang="ts">
import { ref } from 'vue'
import { DISCLAIMER_PARAGRAPHS, DISCLAIMER_TITLE } from '../utils/disclaimer'

const props = defineProps<{
  show: boolean
  // When true, the dialog blocks (no close, requires checkbox + accept).
  gate?: boolean
}>()

const emit = defineEmits<{
  (e: 'update:show', value: boolean): void
  (e: 'accept'): void
}>()

const checked = ref(false)

function close() {
  emit('update:show', false)
}

function accept() {
  if (!checked.value) return
  emit('accept')
}
</script>

<template>
  <van-popup
    :show="show"
    round
    position="center"
    :close-on-click-overlay="!gate"
    :style="{ width: '460px', maxWidth: '92vw', maxHeight: '82vh', padding: '24px', background: '#fff', color: '#1a1a1a', display: 'flex', flexDirection: 'column' }"
    @update:show="(v: boolean) => !gate && emit('update:show', v)"
  >
    <h3 class="disclaimer-title">{{ DISCLAIMER_TITLE }}</h3>
    <div class="disclaimer-body">
      <p v-for="(para, i) in DISCLAIMER_PARAGRAPHS" :key="i" class="disclaimer-para">{{ para }}</p>
    </div>
    <template v-if="gate">
      <label class="disclaimer-check">
        <van-checkbox v-model="checked" shape="square" icon-size="18px" />
        <span>我已阅读并同意以上免责声明</span>
      </label>
      <van-button type="primary" block :disabled="!checked" @click="accept">同意并继续</van-button>
    </template>
    <template v-else>
      <div class="disclaimer-actions">
        <van-button type="primary" size="small" @click="close">确定</van-button>
      </div>
    </template>
  </van-popup>
</template>

<style scoped>
.disclaimer-title { margin: 0 0 16px; font-size: 18px; font-weight: 600; text-align: center; }
.disclaimer-body { overflow-y: auto; flex: 1; margin-bottom: 16px; }
.disclaimer-para { margin: 0 0 12px; font-size: 13px; line-height: 1.6; color: #333; }
.disclaimer-para:last-child { margin-bottom: 0; }
.disclaimer-check { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; font-size: 13px; cursor: pointer; }
.disclaimer-actions { display: flex; justify-content: flex-end; }
</style>
