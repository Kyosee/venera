import { MouseEvent, ReactNode, useRef, useState } from 'react'
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

export function ComicTile({ data, onOpen, menu }: {
  data: TileData
  onOpen: () => void
  menu?: { label: string; icon?: ReactNode; onClick: () => void; destructive?: boolean }[]
}) {
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLButtonElement>(null)
  const onContext = (e: MouseEvent) => { e.preventDefault(); setOpen(true) }
  return (
    <div className={styles.tile}>
      <button ref={anchor} className={styles.trigger} onClick={onOpen} onContextMenu={onContext}>
        <Ripple>
          <div className={styles.coverWrap}>
            {data.cover
              ? <img src={data.cover} alt="" className={styles.cover} loading="lazy" />
              : <div className={styles.coverPlaceholder} />}
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
