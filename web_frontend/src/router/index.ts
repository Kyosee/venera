import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      component: () => import('../pages/MainPage.vue'),
      redirect: '/home',
      children: [
        { path: 'home', component: () => import('../pages/home/HomePage.vue') },
        { path: 'favorites', component: () => import('../pages/favorites/FavoritesPage.vue') },
        { path: 'explore', component: () => import('../pages/explore/ExplorePage.vue') },
        { path: 'categories', component: () => import('../pages/categories/CategoriesPage.vue') },
        { path: 'settings', component: () => import('../pages/settings/SettingsPage.vue') },
        { path: 'tasks', component: () => import('../pages/tasks/TasksPage.vue') },
        { path: 'history', component: () => import('../pages/history/HistoryPage.vue') },
        { path: 'image-favorites', component: () => import('../pages/image-favorites/ImageFavoritesPage.vue') },
      ]
    },
    { path: '/comic/:sourceKey/:id', component: () => import('../pages/comic/ComicDetailPage.vue') },
    { path: '/reader/:sourceKey/:id', component: () => import('../pages/reader/ReaderPage.vue') },
    { path: '/search', component: () => import('../pages/search/SearchPage.vue') },
  ]
})

export default router
