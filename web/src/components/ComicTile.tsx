import { MouseEvent, ReactNode, useEffect, useRef, useState } from 'react'
import { BookOpen } from 'lucide-react'
import { imageProxyUrl } from '../api'
import { Menu } from '../ui/Menu'
import { Ripple } from '../ui/Ripple'
import styles from './ComicTile.module.css'

export type TileData = {
  id: string
  sourceKey: string
  title: string
  cover: string | null
  subtitle?: ReactNode
  badge?: ReactNode
}

export function ComicTile({ data, onOpen, menu, variant = 'list' }: {
  data: TileData
  onOpen: () => void
  menu?: { label: string; icon?: ReactNode; onClick: () => void; destructive?: boolean }[]
  variant?: 'list' | 'compact'
}) {
  const [open, setOpen] = useState(false)
  const [failed, setFailed] = useState(false)
  const anchor = useRef<HTMLButtonElement>(null)
  const onContext = (e: MouseEvent) => { e.preventDefault(); setOpen(true) }
  const coverUrl = data.cover
    ? data.cover.startsWith('/api/image?') ? data.cover : imageProxyUrl(data.cover)
    : null

  useEffect(() => {
    setFailed(false)
  }, [data.cover])

  return (
    <div className={`${styles.tile} ${variant === 'compact' ? styles.compact : ''}`}>
      <button ref={anchor} className={styles.trigger} onClick={onOpen} onContextMenu={onContext}>
        <Ripple>
          <div className={styles.coverWrap}>
            {coverUrl && !failed
              ? <img src={coverUrl} alt="" className={styles.cover} loading="lazy" onError={() => setFailed(true)} />
              : <div className={styles.coverPlaceholder}><BookOpen size={variant === 'compact' ? 24 : 22} /></div>}
            {data.badge && <div className={styles.badge}>{data.badge}</div>}
          </div>
          <div className={styles.meta}>
            <div className={styles.title}>{data.title}</div>
            {data.subtitle && <div className={styles.subtitle}>{data.subtitle}</div>}
          </div>
        </Ripple>
      </button>
      {menu && <Menu anchor={anchor.current} open={open} onClose={() => setOpen(false)} items={menu} />}
    </div>
  )
}
