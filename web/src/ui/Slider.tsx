import { InputHTMLAttributes } from 'react'
import styles from './Slider.module.css'
export function Slider(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input type="range" {...props} className={`${styles.slider} ${props.className ?? ''}`} />
}
