import { useRef, MouseEvent, ReactNode } from 'react'
import styles from './Ripple.module.css'

export function Ripple({ children, disabled }: { children: ReactNode; disabled?: boolean }) {
  const host = useRef<HTMLSpanElement>(null)
  const onPointerDown = (e: MouseEvent) => {
    if (disabled || !host.current) return
    const rect = host.current.getBoundingClientRect()
    const size = Math.max(rect.width, rect.height) * 2
    const dot = document.createElement('span')
    dot.className = styles.dot
    dot.style.width = dot.style.height = `${size}px`
    dot.style.left = `${e.clientX - rect.left - size / 2}px`
    dot.style.top = `${e.clientY - rect.top - size / 2}px`
    host.current.appendChild(dot)
    dot.addEventListener('animationend', () => dot.remove())
  }
  return (
    <span ref={host} className={styles.host} onMouseDown={onPointerDown}>
      {children}
    </span>
  )
}
