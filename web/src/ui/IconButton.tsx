import { ButtonHTMLAttributes, ReactNode } from 'react'
import { Ripple } from './Ripple'
import styles from './IconButton.module.css'

export function IconButton({
  variant = 'standard', children, className, ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'standard' | 'filled' | 'tonal' | 'outlined'; children: ReactNode
}) {
  return (
    <button {...rest} className={`${styles.btn} ${styles[variant]} ${className ?? ''}`}>
      <Ripple disabled={rest.disabled}>{children}</Ripple>
    </button>
  )
}
