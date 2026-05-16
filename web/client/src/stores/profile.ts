import { defineStore } from 'pinia'
import { ref } from 'vue'
import { setProfile as apiSetProfile, getProfile } from '../services/api'

export const useProfileStore = defineStore('profile', () => {
  const activeProfile = ref(getProfile())

  function setProfile(profile: string) {
    activeProfile.value = profile
    apiSetProfile(profile)
  }

  return { activeProfile, setProfile }
})
