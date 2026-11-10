import React from 'react';
import { brand } from '../../config/brand';

/** Shared Splyzo artwork on a light badge keeps the full-color mark readable in dark mode. */
export const LogoBadge: React.FC<{ className?: string; imgClassName?: string }> = ({ className = '', imgClassName = 'h-14 w-14' }) => (
  <span className={`inline-flex items-center justify-center rounded-k-md bg-kraveo-cream px-2 py-2 shadow-k-soft ${className}`}>
    <img src="/brand/splyzo-logo.png" alt={brand.name} className={`w-auto object-contain ${imgClassName}`} />
  </span>
);

/** Square Splyzo launcher artwork for compact navigation and app identity. */
export const LogoMark: React.FC<{ size?: number; className?: string }> = ({ size = 44, className = '' }) => {
  return (
    <span
      role="img"
      aria-label={brand.name}
      className={`inline-flex shrink-0 items-center justify-center rounded-k-md bg-kraveo-cream text-kraveo-g800 shadow-k-soft ${className}`}
      style={{ width: size, height: size }}
    ><img src="/brand/splyzo-logo.png" alt="" className="h-full w-full rounded-k-md object-contain" /></span>
  );
};
