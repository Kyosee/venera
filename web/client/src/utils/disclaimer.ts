// Disclaimer text and consent state for the web client.

export const DISCLAIMER_PARAGRAPHS: string[] = [
  '本项目的软件代码以“原样”提供，不附带任何明示或暗示的担保；本项目维护者不保证其准确性、完整性或适用于任何特定用途，使用风险由使用者自行承担。',
  '本项目仅用于个人学习与研究，功能开发和维护由 AI 驱动。本项目不包含、不提供、不托管、也不分发任何内容；对于使用者通过或改造本软件访问、获取或处理的任何第三方内容，本项目不保证其合法性、准确性或完整性，亦不对其承担任何责任。使用者须自行判断、对自身使用行为负责，并遵守所在司法管辖区的全部适用法律法规。',
  '使用者不得利用本项目从事任何非法活动、传播恶意软件或病毒，或干扰任何公司或个人的正常运营及合法权益。本项目为非营利开源项目，禁止用于牟利，任何第三方的盈利行为均与本项目无关。',
  '禁止在各类公开/官方平台及官方账号区域（包括但不限于微博、微信公众号、X 等）宣传或推广本项目。',
  '一旦下载、复制、修改或使用本项目，即视为已阅读并接受本声明。本项目维护者保留随时修改或补充本声明的权利。',
]

export const DISCLAIMER_TITLE = '免责声明'

const CONSENT_REQUIRED = false
const CONSENT_STORAGE_KEY = 'venera_disclaimer_consented'

export function hasConsented(): boolean {
  try {
    return localStorage.getItem(CONSENT_STORAGE_KEY) === '1'
  } catch {
    return false
  }
}

export function setConsented(): void {
  try {
    localStorage.setItem(CONSENT_STORAGE_KEY, '1')
  } catch {
    // localStorage unavailable; consent is session-only in that case.
  }
}

/** Whether the consent gate should block the UI on this load. */
export function shouldShowConsentGate(): boolean {
  return CONSENT_REQUIRED && !hasConsented()
}
